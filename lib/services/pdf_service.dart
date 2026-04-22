import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/assessment/trial_exam_model.dart';
import '../models/field_trip_model.dart'; // Add this import

class PdfService {
  Future<Uint8List> generatePreRegistrationOfferPdf(
    Map<String, dynamic> reg,
    Map<String, dynamic> settings,
  ) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final offer = reg['priceOffer'] as Map<String, dynamic>? ?? {};
    final priceTypes = settings['priceTypes'] as List<dynamic>? ?? ['Eğitim', 'Yemek'];
    final discounts = settings['discounts'] as List<dynamic>? ?? [];
    final paymentMethods = settings['paymentMethods'] as List<dynamic>? ?? [];

    // Logo (if exists in settings)
    pw.Widget logoWidget;
    if (settings['logo'] != null && settings['logo'].toString().isNotEmpty) {
      final logoBytes = Uint8List.fromList(List<int>.from(settings['logo'] is String 
          ? Uri.parse(settings['logo']).data!.contentAsBytes() 
          : settings['logo']));
      logoWidget = pw.Image(pw.MemoryImage(logoBytes), width: 100);
    } else {
      logoWidget = pw.Text('LOGO', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold));
    }

    // Validity Date: Last day of meeting month
    String meetingDateStr = reg['meetingDate']?.toString() ?? DateFormat('dd.MM.yyyy').format(DateTime.now());
    DateTime meetingDate = DateTime.now();
    try {
      if (meetingDateStr.contains('.')) {
        final parts = meetingDateStr.split('.');
        meetingDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
      } else {
        meetingDate = DateTime.parse(meetingDateStr);
      }
    } catch (_) {}
    final lastDayOfMonth = DateTime(meetingDate.year, meetingDate.month + 1, 0);
    final validityDateStr = DateFormat('dd.MM.yyyy').format(lastDayOfMonth);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header Logo
              pw.Center(child: logoWidget),
              pw.SizedBox(height: 20),
              
              pw.Text('ADAY ÖÄRENCİ ÜCRET FORMU', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 16),

              // Student Info Grid
              pw.Table(
                children: [
                   pw.TableRow(children: [
                     _pdfInfoCell('Öğrencinin Adı Soyadı:', reg['fullName']),
                     _pdfInfoCell('Tarih:', DateFormat('dd.MM.yyyy').format(DateTime.now())),
                   ]),
                   pw.TableRow(children: [
                     _pdfInfoCell('Kayıt Olacağı Okul Türü:', reg['schoolTypeName'] ?? '-'),
                     _pdfInfoCell('Sınıfı:', reg['classLevel']?.toString() ?? '-'),
                   ]),
                ]
              ),
              pw.SizedBox(height: 24),

              // Two columns: Eğitim & Yemek
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left Column: Eğitim (or first price type)
                  pw.Expanded(
                    child: _buildPriceColumn(priceTypes.isNotEmpty ? priceTypes[0].toString() : 'Eğitim', offer, discounts, paymentMethods, true),
                  ),
                  pw.SizedBox(width: 2),
                  // Right Column: Yemek (or second price type)
                  pw.Expanded(
                    child: priceTypes.length > 1 
                      ? _buildPriceColumn(priceTypes[1].toString(), offer, discounts, paymentMethods, false)
                      : pw.Container(),
                  ),
                ],
              ),
              
              // Footer Info
              pw.Spacer(),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  pw.TableRow(children: [
                    _pdfFooterCell('Veli Adı Soyadı:', reg['guardian1Name']),
                    _pdfFooterCell('Görüşme Geçerlilik Tarihi:', validityDateStr),
                  ]),
                   pw.TableRow(children: [
                    _pdfFooterCell('Telefon:', reg['phone']),
                    _pdfFooterCell('Görüşme Yapan Yönetici:', reg['responsibleName']),
                  ]),
                ]
              ),
              pw.SizedBox(height: 12),
              pw.Center(child: pw.Text('abc.k12.tr  444 222 1', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600))),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _pdfInfoCell(String label, String? value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(width: 8),
          pw.Text(value ?? '-', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      )
    );
  }

  pw.Widget _pdfFooterCell(String label, String? value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(value ?? '-', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      )
    );
  }

  pw.Widget _buildPriceColumn(String type, Map<String, dynamic> offer, List<dynamic> discounts, List<dynamic> paymentMethods, bool showTotals) {
    final baseAmt = (offer[type] ?? 0.0).toDouble();
    final appliedIds = offer['appliedDiscounts'] as List<dynamic>? ?? [];
    
    // Calculate global discounts for this type
    final typeDiscounts = <pw.Widget>[];
    double totalGlobalDiscForThisType = 0;
    
    for (var d in discounts) {
      final dName = d['name']?.toString() ?? '';
      final dApplyToRaw = d['applyTo'] as List<dynamic>?;
      bool applies = false;
      if (dApplyToRaw == null || dApplyToRaw.isEmpty) {
        applies = true;
      } else {
         final tL = type.toLowerCase().replaceAll('ğ', 'g').replaceAll('ş', 's').replaceAll('ı', 'i').replaceAll('ü', 'u').replaceAll('ö', 'o').replaceAll('ç', 'c');
         for (var a in dApplyToRaw) {
            final aL = a.toString().toLowerCase().replaceAll('ğ', 'g').replaceAll('ş', 's').replaceAll('ı', 'i').replaceAll('ü', 'u').replaceAll('ö', 'o').replaceAll('ç', 'c');
            if (tL.contains(aL) || aL.contains(tL)) { applies = true; break; }
         }
      }
      
      if (applies) {
        if (appliedIds.contains(d['id'])) {
          final perc = (offer['_manualPerc_${d['id']}'] as num?)?.toDouble() ?? (d['percentage'] as num?)?.toDouble() ?? 0.0;
          final dAmt = baseAmt * (perc / 100);
          totalGlobalDiscForThisType += dAmt;
          typeDiscounts.add(_pdfTableRow(dName + ':', '%${perc.toInt()}', isBold: false, fontSize: 9));
        } else {
          // Show empty as in image? Actually image shows labels Erken Kayıt, Burs etc.
          // Let's list some common ones if they exist in settings
          typeDiscounts.add(_pdfTableRow(dName + ':', '', isBold: false, fontSize: 9));
        }
      }
    }
    
    final amtAfterGlobal = baseAmt - totalGlobalDiscForThisType;

    // Combined totals logic (if this is the second column)
    double combinedTaksit = 0;
    double combinedPesin = 0;
    double combinedTek = 0;
    
    if (!showTotals) {
       // Calculation for ALL types combined (for the Right-column summary)
       final priceTypes = offer.keys.where((k) => !['appliedDiscounts', 'discount', 'total', 'autoGenerated', 'perTypePaymentMethods'].contains(k)).toList();
       for (var mt in paymentMethods) {
          final mName = mt['name']?.toString().toLowerCase() ?? '';
          final disc = (mt['discount'] as num?)?.toDouble() ?? 0.0;
          double typeCombined = 0;
          for (var pt in priceTypes) {
             // Redo the global discount calc for pt...
             double ptBase = (offer[pt.toString()] ?? 0.0).toDouble();
             double ptGlobalDisc = 0;
             for (var d in discounts) {
                if (appliedIds.contains(d['id'])) {
                   final dApplyToRaw = d['applyTo'] as List<dynamic>?;
                   bool ptApplies = false;
                   if (dApplyToRaw == null || dApplyToRaw.isEmpty) ptApplies = true;
                   else {
                      final ptL = pt.toString().toLowerCase().replaceAll('ğ', 'g').replaceAll('ş', 's').replaceAll('ı', 'i').replaceAll('ü', 'u').replaceAll('ö', 'o').replaceAll('ç', 'c');
                      for (var a in dApplyToRaw) {
                         final aL = a.toString().toLowerCase().replaceAll('ğ', 'g').replaceAll('ş', 's').replaceAll('ı', 'i').replaceAll('ü', 'u').replaceAll('ö', 'o').replaceAll('ç', 'c');
                         if (ptL.contains(aL) || aL.contains(ptL)) { ptApplies = true; break; }
                      }
                   }
                   if (ptApplies) {
                     final p = (offer['_manualPerc_${d['id']}'] as num?)?.toDouble() ?? (d['percentage'] as num?)?.toDouble() ?? 0.0;
                     ptGlobalDisc += ptBase * (p / 100);
                   }
                }
             }
             typeCombined += (ptBase - ptGlobalDisc) * (1 - disc / 100);
          }
          if (mName.contains('peşin')) combinedPesin = typeCombined;
          else if (mName.contains('tek çekim')) combinedTek = typeCombined;
          else if (mName.contains('taksit')) combinedTaksit = typeCombined;
       }
    }

    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
      child: pw.Column(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            color: PdfColors.indigo,
            width: double.infinity,
            alignment: pw.Alignment.center,
            child: pw.Text(type.toUpperCase(), style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 12)),
          ),
          _pdfTableRow('Ücreti:', baseAmt, isBold: true, bgColor: PdfColors.grey100),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            color: PdfColors.indigo400,
            width: double.infinity,
            child: pw.Text('Uygulanan İndirimler:', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          ...typeDiscounts,
          pw.Divider(thickness: 0.5, height: 1),
          // Individual Payment Plans for this type
          ...paymentMethods.map((m) {
             final disc = (m['discount'] as num?)?.toDouble() ?? 0.0;
             final pAmt = amtAfterGlobal * (1 - disc / 100);
             return _pdfTableRow('${m['name']} ($type):', pAmt, isBold: true, fontSize: 9);
          }).toList(),

          if (!showTotals) ...[
             pw.Container(
               padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
               color: PdfColors.indigo,
               width: double.infinity,
               child: pw.Text('Eğitim + Yemek Toplam Ücretler:', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
             ),
             _pdfTableRow('Taksitli:', combinedTaksit, isBold: true),
             _pdfTableRow('Peşin:', combinedPesin, isBold: true),
             _pdfTableRow('Tek Çekim:', combinedTek, isBold: true),
          ]
        ],
      ),
    );
  }

  pw.Widget _pdfTableRow(String label, dynamic value, {bool isBold = false, PdfColor? bgColor, double fontSize = 10}) {
    final valStr = value is double 
        ? NumberFormat.currency(locale: 'tr_TR', symbol: '').format(value)
        : value.toString();
    
    return pw.Container(
      color: bgColor,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : null)),
          pw.Text(valStr, style: pw.TextStyle(fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : null)),
        ],
      ),
    );
  }


  Future<Uint8List> generateStaffPdf(
    Map<String, dynamic> staff,
    List<String> selectedSections,
  ) async {
    final pdf = pw.Document();
    
    // ... rest of the existing code ...

    // Font yükleme (Türkçe karakter desteği için)
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context context) {
          return [
            _buildHeader(staff),
            pw.SizedBox(height: 20),
            if (selectedSections.contains('personal'))
              _buildPersonalSection(staff),
            if (selectedSections.contains('job')) _buildJobSection(staff),
            if (selectedSections.contains('education'))
              _buildEducationSection(staff),
            if (selectedSections.contains('experience'))
              _buildExperienceSection(staff),
            if (selectedSections.contains('files')) _buildFilesSection(staff),
            if (selectedSections.contains('status')) _buildStatusSection(staff),
          ];
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildHeader(Map<String, dynamic> staff) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              staff['fullName'] ?? 'İsimsiz Personel',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              staff['title'] ?? 'Ünvan Belirtilmemiş',
              style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
            ),
          ],
        ),
        pw.Text(
          'Personel Detay Raporu',
          style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey500),
        ),
      ],
    );
  }

  pw.Widget _buildPersonalSection(Map<String, dynamic> staff) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Kişisel Bilgiler',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          _buildInfoRow('TC Kimlik No', staff['tc']),
          _buildInfoRow('Doğum Tarihi', staff['birthDate']),
          _buildInfoRow('Doğum Yeri', staff['birthPlace']),
          _buildInfoRow('Cinsiyet', staff['gender']),
          _buildInfoRow('Medeni Durum', staff['maritalStatus']),
          _buildInfoRow('Uyruk', staff['nationality']),
          _buildInfoRow('Kan Grubu', staff['bloodGroup']),
          pw.SizedBox(height: 10),
          pw.Text(
            'İletişim & Adres',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          _buildInfoRow('Kurumsal E-posta', staff['corporateEmail']),
          _buildInfoRow('Kişisel E-posta', staff['personalEmail']),
          _buildInfoRow('Cep Telefonu', staff['mobilePhone']),
          _buildInfoRow(
            'İl / İlçe',
            '${staff['city'] ?? ''} / ${staff['district'] ?? ''}',
          ),
          _buildInfoRow('Adres', staff['address']),
          pw.SizedBox(height: 10),
          pw.Text(
            'Acil Durum',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          _buildInfoRow('Kişi', staff['emergencyContactName']),
          _buildInfoRow('Telefon', staff['emergencyContactPhone']),
        ],
      ),
    );
  }

  pw.Widget _buildJobSection(Map<String, dynamic> staff) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'İş & Pozisyon Bilgileri',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          _buildInfoRow('Departman', staff['department']),
          _buildInfoRow('Ünvan', staff['title']),
          _buildInfoRow('Yönetici', staff['managerName']),
          _buildInfoRow('Çalışma Yeri', staff['workLocation']),
          _buildInfoRow('Başlama Tarihi', staff['jobStartDate']),
          _buildInfoRow('İstihdam Türü', staff['employmentType']),
          _buildInfoRow('Deneme Süresi', staff['probationInfo']),
        ],
      ),
    );
  }

  pw.Widget _buildEducationSection(Map<String, dynamic> staff) {
    final formal = List<dynamic>.from(staff['formalEducations'] ?? []);
    final certs = List<dynamic>.from(staff['certificates'] ?? []);
    final langs = List<dynamic>.from(staff['languages'] ?? []);

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Eğitim Bilgileri',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          if (formal.isNotEmpty) ...[
            pw.Text(
              'Formal Eğitim',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            ...formal.map(
              (e) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 5),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '${e['school'] ?? '-'} / ${e['program'] ?? '-'}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      '${e['degree'] ?? '-'} (${e['start'] ?? '-'} - ${e['end'] ?? '-'})',
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 10),
          ],
          if (certs.isNotEmpty) ...[
            pw.Text(
              'Sertifikalar',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            ...certs.map(
              (e) => pw.Text(
                '${e['name'] ?? '-'} - ${e['provider'] ?? '-'} (${e['date'] ?? '-'})',
              ),
            ),
            pw.SizedBox(height: 10),
          ],
          if (langs.isNotEmpty) ...[
            pw.Text(
              'Yabancı Diller',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            ...langs.map(
              (e) => pw.Text(
                '${e['language'] ?? '-'} (Okuma: ${e['read'] ?? '-'}, Yazma: ${e['write'] ?? '-'}, Konuşma: ${e['speak'] ?? '-'})',
              ),
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _buildExperienceSection(Map<String, dynamic> staff) {
    final experiences = List<dynamic>.from(staff['experiences'] ?? []);

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'İş Deneyimi',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          if (experiences.isEmpty)
            pw.Text('Kayıtlı iş deneyimi bulunmamaktadır.')
          else
            ...experiences.map(
              (e) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '${e['company'] ?? '-'} - ${e['position'] ?? '-'}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text('${e['start'] ?? '-'} - ${e['end'] ?? '-'}'),
                    if ((e['reason'] ?? '').isNotEmpty)
                      pw.Text('Ayrılma Nedeni: ${e['reason']}'),
                    if ((e['description'] ?? '').isNotEmpty)
                      pw.Text('Açıklama: ${e['description']}'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _buildFilesSection(Map<String, dynamic> staff) {
    final official = Map<String, dynamic>.from(staff['officialDocs'] ?? {});
    final contracts = Map<String, dynamic>.from(staff['contractDocs'] ?? {});

    bool isUploaded(Map<String, dynamic> map, String key) {
      final value = map[key];
      if (value is bool) return value;
      if (value is Map && value['uploaded'] is bool) return value['uploaded'];
      if (value is String && value.isNotEmpty) return true;
      return false;
    }

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Dosyalar ve Belgeler',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Resmi Belgeler',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          _buildFileRow('Nüfus Cüzdanı', isUploaded(official, 'id_copy')),
          _buildFileRow('İkametgÃ¢h', isUploaded(official, 'residence')),
          _buildFileRow(
            'Adli Sicil Kaydı',
            isUploaded(official, 'criminal_record'),
          ),
          _buildFileRow('Sağlık Raporu', isUploaded(official, 'health_report')),
          _buildFileRow('Diploma', isUploaded(official, 'diploma')),
          pw.SizedBox(height: 10),
          pw.Text(
            'Sözleşmeler',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          _buildFileRow(
            'İş Sözleşmesi',
            isUploaded(contracts, 'employment_contract'),
          ),
          _buildFileRow(
            'İşe Giriş Bildirgesi',
            isUploaded(contracts, 'employment_notification'),
          ),
          _buildFileRow('Gizlilik Sözleşmesi', isUploaded(contracts, 'nda')),
          _buildFileRow('CV', isUploaded(contracts, 'cv')),
        ],
      ),
    );
  }

  pw.Widget _buildFileRow(String label, bool uploaded) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label),
          pw.Text(
            uploaded ? 'Yüklü' : 'Eksik',
            style: pw.TextStyle(
              color: uploaded ? PdfColors.green : PdfColors.red,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildStatusSection(Map<String, dynamic> staff) {
    final isActive = (staff['isActive'] ?? true) as bool;
    final inactiveReason = (staff['inactiveReason'] ?? '').toString();
    final exitDate = (staff['exitDate'] ?? '').toString();
    final username = (staff['username'] ?? '').toString();
    final role = (staff['role'] ?? 'personel').toString();

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Durum ve Sistem Bilgileri',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          _buildInfoRow('Çalışma Durumu', isActive ? 'Aktif' : 'Pasif'),
          if (!isActive) ...[
            _buildInfoRow('Pasif Nedeni', inactiveReason),
            _buildInfoRow('Ayrılış Tarihi', exitDate),
          ],
          _buildInfoRow('Kullanıcı Adı', username),
          _buildInfoRow('Rol', role),
        ],
      ),
    );
  }

  pw.Widget _buildInfoRow(String label, dynamic value) {
    final displayValue = value?.toString() ?? '-';
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(child: pw.Text(displayValue)),
        ],
      ),
    );
  }

  Future<Uint8List> generateAssessmentReportPdf({
    required List<TrialExam> exams,
    required List<Map<String, dynamic>> students,
    required Map<String, Map<String, double>> stats,
    required List<Map<String, dynamic>> risingStars,
    required double avgScore,
    required double avgNet,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context context) {
          return [
            _buildAssessmentHeader(exams.length, students.length),
            pw.SizedBox(height: 20),
            _buildAssessmentSummary(avgScore, avgNet),
            pw.SizedBox(height: 30),
            _buildPdfSectionTitle('Öğrenci Performans Sıralaması (İlk 10)'),
            _buildTopStudentsTable(students),
            pw.SizedBox(height: 30),
            _buildPdfSectionTitle('Gelişim Liderleri'),
            _buildRisingStarsTable(risingStars),
            pw.SizedBox(height: 30),
            _buildPdfSectionTitle('Sınav Bazlı Katılım ve Başarı'),
            _buildExamParticipationTable(exams, stats),
          ];
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildAssessmentHeader(int examCount, int studentCount) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Birleştirilmiş Analiz Raporu',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo900,
              ),
            ),
            pw.Text(
              'Kurumsal Akademik Değerlendirme Çıktısı',
              style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              '$examCount Sınav Seçildi',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              '$studentCount Toplam Öğrenci',
              style: pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildAssessmentSummary(double score, double net) {
    return pw.Row(
      children: [
        _buildStatBox(
          'Genel Puan Ort.',
          score.toStringAsFixed(1),
          PdfColors.indigo50,
        ),
        pw.SizedBox(width: 20),
        _buildStatBox(
          'Genel Net Ort.',
          net.toStringAsFixed(1),
          PdfColors.teal50,
        ),
      ],
    );
  }

  pw.Widget _buildStatBox(String label, String value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.indigo900,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfSectionTitle(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.indigo700,
            ),
          ),
          pw.Container(height: 1, width: 60, color: PdfColors.indigo700),
        ],
      ),
    );
  }

  pw.Widget _buildTopStudentsTable(List<Map<String, dynamic>> students) {
    final sorted = List<Map<String, dynamic>>.from(students)
      ..sort((a, b) {
        double aAvg = 0;
        final aExams = a['exams'] as Map;
        for (var v in aExams.values) aAvg += (v['score'] as num).toDouble();
        aAvg = aExams.isEmpty ? 0 : aAvg / aExams.length;

        double bAvg = 0;
        final bExams = b['exams'] as Map;
        for (var v in bExams.values) bAvg += (v['score'] as num).toDouble();
        bAvg = bExams.isEmpty ? 0 : bAvg / bExams.length;

        return bAvg.compareTo(aAvg);
      });

    final top10 = sorted.take(10).toList();

    return pw.TableHelper.fromTextArray(
      context: null,
      headers: ['Sıra', 'Öğrenci Adı', 'Åube', 'Ort. Puan'],
      data: top10.asMap().entries.map((e) {
        double avg = 0;
        final exams = e.value['exams'] as Map;
        for (var v in exams.values) avg += (v['score'] as num).toDouble();
        avg = exams.isEmpty ? 0 : avg / exams.length;

        return [
          e.key + 1,
          e.value['name'],
          e.value['branch'],
          avg.toStringAsFixed(1),
        ];
      }).toList(),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
      cellHeight: 25,
      cellAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
      },
    );
  }

  pw.Widget _buildRisingStarsTable(List<Map<String, dynamic>> stars) {
    return pw.TableHelper.fromTextArray(
      context: null,
      headers: ['Öğrenci', 'Åube', 'İlk Net', 'Son Net', 'Gelişim'],
      data: stars
          .map(
            (s) => [
              s['name'],
              s['branch'],
              s['firstNet'].toStringAsFixed(1),
              s['lastNet'].toStringAsFixed(1),
              '+${s['improvement'].toStringAsFixed(1)}',
            ],
          )
          .toList(),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.green700),
      cellHeight: 25,
    );
  }

  pw.Widget _buildExamParticipationTable(
    List<TrialExam> exams,
    Map<String, Map<String, double>> stats,
  ) {
    return pw.TableHelper.fromTextArray(
      context: null,
      headers: ['Sınav Adı', 'Tarih', 'Katılım', 'Puan Ort.', 'Net Ort.'],
      data: exams.map((e) {
        final s = stats[e.id] ?? {};
        return [
          e.name,
          '${e.date.day}.${e.date.month}.${e.date.year}',
          s['count']?.toInt().toString() ?? '-',
          s['scoreAvg']?.toStringAsFixed(1) ?? '-',
          s['netAvg']?.toStringAsFixed(1) ?? '-',
        ];
      }).toList(),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey900),
      cellHeight: 25,
    );
  }

  Future<Uint8List> generateTrendReportPdf({
    required List<TrialExam> exams,
    required Map<String, Map<String, double>> examStats,
    required Map<String, Map<String, double>> branchExamStats,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context context) {
          return [
            _buildReportHeader(
              'Gelişim Trendi Raporu',
              'Sınavlar Arası Performans Değişimi',
            ),
            pw.SizedBox(height: 20),
            _buildPdfSectionTitle('Genel Puan ve Net Gelişimi'),
            _buildExamParticipationTable(exams, examStats),
            pw.SizedBox(height: 30),
            _buildPdfSectionTitle('Åube Bazlı İlerleme Özeti'),
            _buildBranchTrendTable(exams, branchExamStats),
          ];
        },
      ),
    );
    return pdf.save();
  }

  Future<Uint8List> generateBranchReportPdf({
    required List<TrialExam> exams,
    required List<String> branches,
    required List<String> subjects,
    required Map<String, Map<String, double>> subjectExamStats,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context context) {
          return [
            _buildReportHeader(
              'Åube Analiz Raporu',
              'Åubeler Arası Akademik Kıyaslama',
            ),
            pw.SizedBox(height: 20),
            _buildPdfSectionTitle('Åube Performans Tablosu'),
            _buildDetailedBranchTable(branches, subjects, subjectExamStats),
          ];
        },
      ),
    );
    return pdf.save();
  }

  Future<Uint8List> generateTopicReportPdf({
    required Map<String, Map<String, dynamic>> topicStats,
    required List<String> subjects,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context context) {
          return [
            _buildReportHeader(
              'Konu Analiz Raporu',
              'Kazanım Bazlı Başarı Seviyeleri',
            ),
            pw.SizedBox(height: 20),
            ...subjects.map((s) {
              final topics = topicStats[s] ?? {};
              if (topics.isEmpty) return pw.SizedBox();
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildPdfSectionTitle(s),
                  _buildDetailedTopicTable(topics),
                  pw.SizedBox(height: 20),
                ],
              );
            }),
          ];
        },
      ),
    );
    return pdf.save();
  }

  Future<Uint8List> generateRankingReportPdf({
    required List<Map<String, dynamic>> students,
    required String mode,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context context) {
          return [
            _buildReportHeader(
              'Başarı Sıralaması Raporu',
              '$mode Bazlı Genel Sıralama',
            ),
            pw.SizedBox(height: 20),
            _buildPdfSectionTitle('Tüm Öğrenciler'),
            _buildFullRankingTable(students, mode),
          ];
        },
      ),
    );
    return pdf.save();
  }

  pw.Widget _buildReportHeader(String title, String subtitle) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo900,
              ),
            ),
            pw.Text(
              subtitle,
              style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            ),
          ],
        ),
        pw.Text(
          'Tarih: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}',
          style: pw.TextStyle(fontSize: 10),
        ),
      ],
    );
  }

  pw.Widget _buildBranchTrendTable(
    List<TrialExam> exams,
    Map<String, Map<String, double>> bStats,
  ) {
    Set<String> branches = {};
    for (var m in bStats.values) branches.addAll(m.keys);

    return pw.TableHelper.fromTextArray(
      context: null,
      headers: ['Åube', ...exams.map((e) => 'S${exams.indexOf(e) + 1}')],
      data: branches.map((b) {
        return [
          b,
          ...exams.map((e) => bStats[e.id]?[b]?.toStringAsFixed(1) ?? '-'),
        ];
      }).toList(),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo700),
      cellHeight: 25,
    );
  }

  pw.Widget _buildDetailedBranchTable(
    List<String> branches,
    List<String> subjects,
    Map<String, Map<String, double>> sStats,
  ) {
    return pw.TableHelper.fromTextArray(
      context: null,
      headers: ['Åube', ...subjects],
      data: branches.where((b) => b != 'Tümü').map((b) {
        return [
          b,
          ...subjects.map((s) {
            // This is a simplified view since branch data structure might be complex
            return '-'; // In a real scenario, we'd pass branch-subject cross matrix
          }),
        ];
      }).toList(),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
        fontSize: 10,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
      cellHeight: 25,
    );
  }

  pw.Widget _buildDetailedTopicTable(Map<String, dynamic> topics) {
    return pw.TableHelper.fromTextArray(
      context: null,
      headers: ['Konu Adı', 'Doğru', 'Yanlış', 'Başarı %'],
      data: topics.entries.map((e) {
        final d = e.value;
        double total = (d['correct'] + d['wrong'] + d['empty']).toDouble();
        double pct = total > 0 ? (d['correct'] / total) * 100 : 0;
        return [
          e.key,
          d['correct'].toString(),
          d['wrong'].toString(),
          '%${pct.toStringAsFixed(1)}',
        ];
      }).toList(),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
      cellHeight: 25,
    );
  }

  pw.Widget _buildFullRankingTable(
    List<Map<String, dynamic>> students,
    String mode,
  ) {
    final sorted = List<Map<String, dynamic>>.from(students)
      ..sort((a, b) {
        final aExams = a['exams'] as Map;
        final bExams = b['exams'] as Map;
        double aVal = 0, bVal = 0;
        String key = mode == 'Puan' ? 'score' : 'net';
        for (var v in aExams.values) aVal += (v[key] as num).toDouble();
        for (var v in bExams.values) bVal += (v[key] as num).toDouble();
        return bVal.compareTo(aVal);
      });

    return pw.TableHelper.fromTextArray(
      context: null,
      headers: ['Sıra', 'İsim', 'Åube', 'Toplam $mode', 'Ort. $mode'],
      data: sorted.asMap().entries.map((e) {
        final st = e.value;
        final exams = st['exams'] as Map;
        double total = 0;
        String key = mode == 'Puan' ? 'score' : 'net';
        for (var v in exams.values) total += (v[key] as num).toDouble();
        double avg = exams.isEmpty ? 0 : total / exams.length;
        return [
          e.key + 1,
          st['name'],
          st['branch'],
          total.toStringAsFixed(1),
          avg.toStringAsFixed(1),
        ];
      }).toList(),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
      cellHeight: 25,
    );
  }

  Future<Uint8List> generateSubstituteTeacherReportPdf({
    required String title,
    required String dateRange,
    required List<String> headers,
    required List<List<String>> data,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape, // Landscape for wide tables
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      title,
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.indigo900,
                      ),
                    ),
                    pw.Text(
                      dateRange,
                      style: const pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  'Oluşturulma: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              context: null,
              headers: headers,
              data: data,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                fontSize: 10,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.indigo900,
              ),
              cellHeight: 25,
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellAlignments: Map.fromIterables(
                List.generate(headers.length, (index) => index),
                List.generate(
                  headers.length,
                  (index) => index == 0
                      ? pw.Alignment.centerLeft
                      : pw.Alignment.center,
                ),
              ),
            ),
          ];
        },
      ),
    );
    return pdf.save();
  }

  Future<Uint8List> generateDutySchedulePdf({
    required String periodName,
    required String weekRange,
    required List<String> days, // Headers: Location, Mon, Tue...
    required List<List<String>>
    rows, // [LocationName, TeacherMon, TeacherTue...]
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Nöbet Çizelgesi - $periodName',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.indigo900,
                      ),
                    ),
                    pw.Text(
                      weekRange,
                      style: const pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  'Oluşturulma: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Table.fromTextArray(
              context: context,
              headers: days,
              data: rows,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                fontSize: 10,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.indigo900,
                borderRadius: pw.BorderRadius.vertical(
                  top: pw.Radius.circular(4),
                ),
              ),
              cellHeight: 40,
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                for (var i = 1; i < days.length; i++) i: pw.Alignment.center,
              },
              oddRowDecoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
              ),
            ),
          ];
        },
      ),
    );
    return pdf.save();
  }

  Future<Uint8List> generateDutyStatsPdf({
    required String periodName,
    required String dateRange,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Nöbet İstatistikleri - $periodName',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.indigo900,
                      ),
                    ),
                    pw.Text(
                      dateRange,
                      style: const pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  'Oluşturulma: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Table.fromTextArray(
              context: context,
              headers: headers,
              data: rows,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                fontSize: 10,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.indigo900,
                borderRadius: pw.BorderRadius.vertical(
                  top: pw.Radius.circular(4),
                ),
              ),
              cellHeight: 25,
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                for (var i = 1; i < headers.length; i++) i: pw.Alignment.center,
              },
              oddRowDecoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
              ),
            ),
          ];
        },
      ),
    );
    return pdf.save();
  }

  Future<Uint8List> generateFieldTripGroupsPdf({
    required FieldTrip trip,
    required Map<String, Map<String, dynamic>> studentDetails,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    for (var group in trip.groups) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(base: font, bold: fontBold),
          build: (pw.Context context) {
            return [
              // Header
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Gezi Grubu Listesi',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.indigo900,
                    ),
                  ),
                  pw.Text(
                    '${trip.name} - ${trip.purpose}',
                    style: const pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.Divider(color: PdfColors.grey300),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Grup: ${group.name}',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        '${group.studentIds.length} Öğrenci',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 5),
                  pw.Row(
                    children: [
                      pw.Text(
                        'Öğretmenler: ',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        group.teacherNames.isNotEmpty
                            ? group.teacherNames.join(', ')
                            : 'Atanmamış',
                      ),
                    ],
                  ),
                  if (group.vehiclePlate != null || group.driverPhone != null)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 4),
                      child: pw.Row(
                        children: [
                          if (group.vehiclePlate != null)
                            pw.Text(
                              'Araç: ${group.vehiclePlate}   ',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          if (group.driverPhone != null)
                            pw.Text('Åoför: ${group.driverPhone}'),
                        ],
                      ),
                    ),
                ],
              ),
              pw.SizedBox(height: 15),

              // Student Table
              pw.TableHelper.fromTextArray(
                context: context,
                headers: [
                  'No',
                  'Öğrenci Adı Soyadı',
                  'Sınıfı',
                  'Öğrenci Tel',
                  'Veli Adı',
                  'Veli Tel',
                ],
                data: List.generate(group.studentIds.length, (index) {
                  final sid = group.studentIds[index];
                  final details = studentDetails[sid] ?? {};
                  return [
                    (index + 1).toString(),
                    details['fullName'] ?? '-',
                    details['className'] ?? '-',
                    details['phone'] ?? '-',
                    details['parentName'] ?? '-',
                    details['parentPhone'] ?? '-',
                  ];
                }),
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                  fontSize: 10,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.indigo900,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.center,
                  3: pw.Alignment.center,
                  4: pw.Alignment.centerLeft,
                  5: pw.Alignment.center,
                },
                columnWidths: {
                  0: const pw.FixedColumnWidth(30),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(2),
                  4: const pw.FlexColumnWidth(3),
                  5: const pw.FlexColumnWidth(2),
                },
              ),
            ];
          },
        ),
      );
    }

    return pdf.save();
  }

  Future<Uint8List> generateAcademicSelfConceptPdf({
    required String title,
    required String subTitle,
    required Map<String, double> averages,
    required Map<String, String> subscaleNames,
    required int respondentCount,
    required String advice,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context context) {
          return [
            _buildReportHeader(title, subTitle),
            pw.SizedBox(height: 10),
            pw.Text(
              'Toplam Katılımcı Sayısı: $respondentCount',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 20),
            _buildPdfSectionTitle('Alt Ölçek Puan Ortalamaları (%)'),
            pw.TableHelper.fromTextArray(
              context: context,
              headers: ['Alt Ölçek', 'Yüzdelik Puan (%)', 'Durum'],
              data: subscaleNames.entries.map((e) {
                final score = averages[e.key] ?? 0;
                String status = 'Orta';
                if (score >= 75) status = 'Güçlü';
                if (score < 25) status = 'Geliştirilmeli';
                return [e.value, '%${score.toStringAsFixed(1)}', status];
              }).toList(),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                fontSize: 10,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.indigo900,
              ),
              cellHeight: 18,
              cellStyle: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 20),
            _buildPdfSectionTitle('Rehberlik Değerlendirmesi ve Öneriler'),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.indigo50,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Text(
                advice,
                style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.5),
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  Future<Uint8List> generateSurveyReportPdf({
    required String title,
    required String subTitle,
    required Map<String, double> averages,
    required Map<String, String> categoryNames,
    required Map<String, int> categoryMax,
    required int respondentCount,
    required String advice,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context context) {
          return [
            _buildReportHeader(title, subTitle),
            pw.SizedBox(height: 20),
            pw.Text(
              'Toplam Yanıt: $respondentCount',
              style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 20),
            _buildPdfSectionTitle('Alt Boyut Puan Analizi'),
            pw.TableHelper.fromTextArray(
              context: null,
              headers: ['Alt Boyut', 'Puan / Maksimum'],
              data: categoryNames.keys.map((key) {
                return [
                  categoryNames[key]!,
                  '${averages[key]?.toStringAsFixed(1) ?? '0'} / ${categoryMax[key]}',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.indigo900,
              ),
              cellHeight: 30,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.center,
              },
            ),
            pw.SizedBox(height: 30),
            _buildPdfSectionTitle('Değerlendirme Notları'),
            pw.Container(
              padding: const pw.EdgeInsets.all(15),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Text(
                advice,
                style: const pw.TextStyle(fontSize: 10, lineSpacing: 2.0),
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  Future<Uint8List> generateBurdonReportPdf({
    required String title,
    required String scopeType,
    required String scopeName,
    required Map<String, dynamic> metrics,
    required String interpretationTitle,
    required String interpretationText,
    List<List<dynamic>>? grid,
    List<List<dynamic>>? selections,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        title,
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.indigo900,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        '$scopeType: $scopeName',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.indigo700,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Text(
                  'Burdon Dikkat Testi',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey,
                  ),
                ),
              ],
            ),
            pw.Divider(thickness: 1, color: PdfColors.indigo100),
            pw.SizedBox(height: 20),
            _buildPdfSectionTitle('Genel Metrikler'),
            pw.Row(
              children: [
                _buildPdfMetricBox(
                  'Ort. Doğru',
                  metrics['avgCorrect'].toStringAsFixed(1),
                  PdfColors.green,
                ),
                pw.SizedBox(width: 10),
                _buildPdfMetricBox(
                  'Ort. Atlanan',
                  metrics['avgMissed'].toStringAsFixed(1),
                  PdfColors.orange,
                ),
                pw.SizedBox(width: 10),
                _buildPdfMetricBox(
                  'Ort. Hatalı',
                  metrics['avgWrong'].toStringAsFixed(1),
                  PdfColors.red,
                ),
                pw.SizedBox(width: 10),
                _buildPdfMetricBox(
                  'Dikkat İndeksi',
                  '%${(metrics['attentionIndex'] * 100).toStringAsFixed(1)}',
                  PdfColors.indigo,
                ),
              ],
            ),
            pw.SizedBox(height: 30),
            _buildPdfSectionTitle('Değerlendirme ve Öneriler'),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                border: pw.Border.all(color: PdfColors.indigo100),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    interpretationTitle,
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.indigo700,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    interpretationText,
                    style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.5),
                  ),
                ],
              ),
            ),
            if (grid != null && selections != null) ...[
              pw.SizedBox(height: 30),
              _buildPdfSectionTitle('Test Matrisi'),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey200),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(8),
                  ),
                ),
                child: pw.Column(
                  children: List.generate(grid.length, (rowIndex) {
                    final rowChars = grid[rowIndex];
                    final rowSels = selections[rowIndex];
                    return pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 0.5),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: List.generate(rowChars.length, (colIndex) {
                          final char = rowChars[colIndex].toString();
                          final isSelected = rowSels[colIndex] as bool;
                          final isTarget = ['a', 'b', 'd', 'g'].contains(char);

                          PdfColor textColor = PdfColors.black;
                          pw.BoxDecoration? decoration;

                          if (isSelected && isTarget) {
                            textColor = PdfColors.green;
                            decoration = const pw.BoxDecoration(
                              color: PdfColors.green50,
                            );
                          } else if (isSelected && !isTarget) {
                            textColor = PdfColors.red;
                            decoration = const pw.BoxDecoration(
                              color: PdfColors.red50,
                            );
                          } else if (!isSelected && isTarget) {
                            textColor = PdfColors.orange800;
                            decoration = pw.BoxDecoration(
                              border: pw.Border.all(color: PdfColors.orange200),
                            );
                          }

                          return pw.Container(
                            width: 10,
                            height: 12,
                            alignment: pw.Alignment.center,
                            decoration: decoration,
                            child: pw.Text(
                              char,
                              style: pw.TextStyle(
                                fontSize: 7,
                                color: textColor,
                                fontWeight: isTarget
                                    ? pw.FontWeight.bold
                                    : pw.FontWeight.normal,
                              ),
                            ),
                          );
                        }),
                      ),
                    );
                  }),
                ),
              ),
            ],
            pw.SizedBox(height: 20),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Rapor Tarihi: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildPdfMetricBox(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: color, width: 0.5),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 8, color: color)),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<Uint8List> generateClassSchedulePdf({
    required List<Map<String, dynamic>> multiClassData, // List of {className, scheduleData, lessonStats}
    required List<String> days,
    required List<Map<String, dynamic>> lessonHours,
    required Map<String, String> institutionInfo,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    for (var classData in multiClassData) {
      final className = classData['className'];
      final scheduleData = classData['scheduleData'];
      final lessonStats = List<Map<String, dynamic>>.from(classData['lessonStats'] ?? []);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(base: font, bold: fontBold),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildModernScheduleHeader(institutionInfo, 'Sınıfın Adı: $className'),
                pw.SizedBox(height: 15),
                _buildScheduleTable(days, lessonHours, scheduleData, isClassSchedule: true),
                pw.SizedBox(height: 15),
                _buildAttendanceStatsTable(lessonStats),
                pw.Spacer(),
                _buildScheduleFooter(institutionInfo['principalName'] ?? ''),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  Future<Uint8List> generateTeacherSchedulePdf({
    required List<Map<String, dynamic>> multiTeacherData, // List of {teacherName, scheduleData, lessonStats}
    required List<String> days,
    required List<Map<String, dynamic>> lessonHours,
    required Map<String, String> institutionInfo,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    for (var teacherData in multiTeacherData) {
      final teacherName = teacherData['teacherName'];
      final scheduleData = teacherData['scheduleData'];
      final lessonStats = List<Map<String, dynamic>>.from(teacherData['lessonStats'] ?? []);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(base: font, bold: fontBold),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildModernScheduleHeader(institutionInfo, ''), // Başlık boş bırakıldı, Sayı/Konu yeterli
                pw.SizedBox(height: 20),
                pw.Center(
                  child: pw.Text(
                    'Sayın $teacherName',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  '          2025/2026 eğitim öğretim yılı geçerli ders programınız aşağıda gösterilmiştir. Bilgilerinizi ve gereğini rica eder, başarılar dilerim.',
                  style: const pw.TextStyle(fontSize: 10),
                  textAlign: pw.TextAlign.left,
                ),
                pw.SizedBox(height: 20),
                _buildScheduleTable(days, lessonHours, scheduleData, isClassSchedule: false),
                pw.SizedBox(height: 20),
                _buildTeacherStatsTable(lessonStats),
                pw.Spacer(),
                _buildScheduleFooter(institutionInfo['principalName'] ?? ''),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  Future<Uint8List> generateMasterSchedulePdf({
    required List<String> days,
    required List<Map<String, dynamic>> lessonHours,
    required List<Map<String, dynamic>> rows,
    required Map<String, String> institutionInfo,
    required String typeLabel,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a3.landscape,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context context) {
          return [
            pw.Center(
              child: pw.Text(
                'Toplu Çarşaf Liste: $typeLabel',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                '${institutionInfo['city']} - ${institutionInfo['district']} / ${institutionInfo['schoolName']}',
                style: const pw.TextStyle(fontSize: 12),
              ),
            ),
            pw.SizedBox(height: 20),
            _buildMasterScheduleGrid(days, lessonHours, rows),
          ];
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildModernScheduleHeader(Map<String, String> info, String subTitle) {
    return pw.Column(
      children: [
        pw.Center(child: pw.Text('T.C.', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
        pw.Center(child: pw.Text('${info['city']} - ${info['district']}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
        pw.Center(child: pw.Text(info['schoolName'] ?? '', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Sayı  :', style: const pw.TextStyle(fontSize: 9)),
                pw.Text('Konu  : Haftalık Ders Programı', style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
            pw.Text(subTitle, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(width: 50),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildScheduleTable(
    List<String> days,
    List<Map<String, dynamic>> hours,
    Map<String, dynamic> schedule, {
    bool isClassSchedule = true,
  }) {
    const double dayColumnWidth = 80; // Gün sütunu genişliği (tek satır olması için artırıldı)
    const double hourColumnWidth = 45; // Ders saatleri sütun genişliği
    const double cellHeight = 40; // Sabit hücre yüksekliği

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(dayColumnWidth),
        ...Map.fromIterable(
          List.generate(hours.length, (i) => i + 1),
          key: (i) => i,
          value: (_) => const pw.FixedColumnWidth(hourColumnWidth),
        ),
      },
      children: [
        // Header Row
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            pw.Container(
              height: cellHeight,
              alignment: pw.Alignment.center,
              child: pw.Text('', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ),
            ...hours.map((h) => pw.Container(
                  height: cellHeight,
                  alignment: pw.Alignment.center,
                  padding: const pw.EdgeInsets.all(2),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text('${hours.indexOf(h) + 1}.Ders', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      pw.Text('${h['startTime']}\n${h['endTime']}', style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
                    ],
                  ),
                )),
          ],
        ),
        // Days Rows
        ...days.map((day) {
          return pw.TableRow(
            verticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: [
              pw.Container(
                height: cellHeight,
                padding: const pw.EdgeInsets.symmetric(horizontal: 4),
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(day, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), softWrap: false),
              ),
              ...List.generate(hours.length, (hIndex) {
                final key = '${day}_$hIndex';
                final data = schedule[key];
                
                // Boş hücre olsa bile sabit boyutta kalması için Container döner
                if (data == null) {
                  return pw.Container(height: cellHeight);
                }

                return pw.Container(
                  height: cellHeight,
                  padding: const pw.EdgeInsets.all(2),
                  alignment: pw.Alignment.center,
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      // Öncelikli olarak kısa ismi (shortName) kullan, yoksa tam ismi kullan
                      pw.Text(
                        (data['shortName'] != null && data['shortName'].toString().isNotEmpty) 
                            ? data['shortName'].toString() 
                            : (data['lessonName'] ?? ''), 
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), 
                        textAlign: pw.TextAlign.center
                      ),
                      pw.Text(
                        isClassSchedule ? (data['teacherName'] ?? '') : (data['className'] ?? ''), 
                        style: const pw.TextStyle(fontSize: 7), 
                        textAlign: pw.TextAlign.center
                      ),
                    ],
                  ),
                );
              }),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _buildAttendanceStatsTable(List<Map<String, dynamic>> stats) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(3),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _tableHeaderCell('Dersin Adı'),
            _tableHeaderCell('HDS'),
            _tableHeaderCell('Öğretmenin Adı'),
          ],
        ),
        ...stats.map((s) {
          final lName = s['lessonName'] ?? '';
          final sName = s['shortName'] ?? '';
          final displayName = sName.isNotEmpty ? '$lName ($sName)' : lName;
          
          return pw.TableRow(
            children: [
              _tableDataCell(displayName),
              _tableDataCell(s['count'].toString()),
              _tableDataCell(s['teacherName'] ?? ''),
            ],
          );
        }),
        pw.TableRow(
          children: [
            _tableDataCell('Toplam Saat', isBold: true),
            _tableDataCell(stats.fold(0, (prev, element) => prev + (element['count'] as int)).toString(), isBold: true),
            pw.Container(),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildTeacherStatsTable(List<Map<String, dynamic>> stats) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(3),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _tableHeaderCell('Dersin Adı'),
            _tableHeaderCell('HDS'),
            _tableHeaderCell('Åube Adı (Sınıf)'),
          ],
        ),
        ...stats.map((s) {
          final lName = s['lessonName'] ?? '';
          final sName = s['shortName'] ?? '';
          final displayName = sName.isNotEmpty ? '$lName ($sName)' : lName;
          
          return pw.TableRow(
            children: [
              _tableDataCell(displayName),
              _tableDataCell(s['count']?.toString() ?? '0'),
              _tableDataCell(s['className'] ?? ''),
            ],
          );
        }),
        pw.TableRow(
          children: [
            _tableDataCell('Toplam Saat', isBold: true),
            _tableDataCell(stats.fold(0, (prev, element) => prev + (element['count'] as int? ?? 0)).toString(), isBold: true),
            pw.Container(),
          ],
        ),
      ],
    );
  }

  pw.Widget _tableHeaderCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
    );
  }

  pw.Widget _tableDataCell(String text, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 8, fontWeight: isBold ? pw.FontWeight.bold : null)),
    );
  }

  pw.Widget _buildScheduleFooter(String principal) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Column(
          children: [
            pw.Text(principal, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.Text('Okul Müdürü', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 20),
            pw.Text('İmza', style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
        pw.SizedBox(width: 40),
      ],
    );
  }


  pw.Widget _buildMasterScheduleGrid(List<String> days, List<Map<String, dynamic>> hours, List<Map<String, dynamic>> rows) {
    const double nameWidth = 85;
    const double hdsWidth = 25;
    const double hourWidth = 25;
    const double cellHeight = 35;
    const double headerHeight = 32;

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      children: [
        // Header Row: Days and Hours
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            // Name Column Header
            pw.Container(
              width: nameWidth,
              height: headerHeight,
              alignment: pw.Alignment.centerLeft,
              padding: const pw.EdgeInsets.symmetric(horizontal: 4),
              child: pw.Text('Adı Soyadı / Sınıf', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ),
            // HDS Column Header
            pw.Container(
              width: hdsWidth,
              height: headerHeight,
              alignment: pw.Alignment.center,
              child: pw.Text('HDS', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ),
            // Days Blocks Headers
            ...days.map((d) => pw.Container(
              width: hourWidth * hours.length,
              height: headerHeight,
              child: pw.Column(
                children: [
                  // Merged Day Name
                  pw.Container(
                    height: headerHeight / 2,
                    width: hourWidth * hours.length,
                    alignment: pw.Alignment.center,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.5)),
                    ),
                    child: pw.Text(d, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  ),
                  // Hour Numbers Row
                  pw.Row(
                    children: hours.map((h) => pw.Container(
                      width: hourWidth,
                      height: headerHeight / 2,
                      alignment: pw.Alignment.center,
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          right: h != hours.last ? const pw.BorderSide(color: PdfColors.black, width: 0.5) : pw.BorderSide.none,
                        ),
                      ),
                      child: pw.Text('${hours.indexOf(h) + 1}', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                    )).toList(),
                  ),
                ],
              ),
            )),
          ],
        ),
        // Data Rows
        ...rows.map((row) {
          final schedule = row['scheduleData'] as Map<String, dynamic>;
          
          // Calculate HDS (Total hours assigned)
          int hdsCount = 0;
          schedule.forEach((key, value) {
            if (value != null) hdsCount++;
          });

          return pw.TableRow(
            verticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: [
              // Individual / Class Name
              pw.Container(
                height: cellHeight,
                width: nameWidth,
                alignment: pw.Alignment.centerLeft,
                padding: const pw.EdgeInsets.symmetric(horizontal: 4),
                child: pw.Text(row['name'] ?? '', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ),
              // HDS Count
              pw.Container(
                height: cellHeight,
                width: hdsWidth,
                alignment: pw.Alignment.center,
                child: pw.Text(hdsCount.toString(), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ),
              // Assigned Lessons for each day
              ...days.map((d) => pw.Row(
                children: List.generate(hours.length, (hIndex) {
                  final key = '${d}_$hIndex';
                  final data = schedule[key];
                  
                  return pw.Container(
                    width: hourWidth,
                    height: cellHeight,
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        right: (hIndex == hours.length - 1 && d == days.last) 
                            ? pw.BorderSide.none 
                            : const pw.BorderSide(color: PdfColors.black, width: 0.5),
                      ),
                    ),
                    padding: const pw.EdgeInsets.all(1),
                    child: data != null ? pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        // Short lesson name or Full name
                        pw.Text(
                          (data['shortName'] != null && data['shortName'].toString().isNotEmpty) 
                              ? data['shortName'].toString() 
                              : (data['lessonName'] ?? ''),
                          style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold), 
                          textAlign: pw.TextAlign.center,
                        ),
                        // Teacher or Class name
                        pw.Text(
                          data['teacherName'] ?? data['className'] ?? '', 
                          style: const pw.TextStyle(fontSize: 5), 
                          textAlign: pw.TextAlign.center,
                        ),
                      ],
                    ) : pw.Container(),
                  );
                }),
              )),
            ],
          );
        }),
      ],
    );
  }


  Future<Uint8List> generateDetailedPortfolioPdf({
    required Map<String, dynamic> studentData,
    required List<String> enabledModules,
    required bool startEachModuleOnNewPage,
    required Map<String, dynamic> schoolSettings,
    Uint8List? systemLogo,
    pw.Font? baseFont,
    pw.Font? boldFont,
    pw.Font? italicFont,
  }) async {
    try {
      final pdf = pw.Document();
      final font = baseFont ?? await PdfGoogleFonts.robotoRegular();
      final fontBold = boldFont ?? await PdfGoogleFonts.robotoBold();
      final fontItalic = italicFont ?? await PdfGoogleFonts.robotoItalic();

      List<pw.Widget> modulesContent = [];
      
      // 1. Dashboard
      modulesContent.addAll(_buildPremiumFirstPage(studentData, systemLogo, fontBold));
      await Future.delayed(const Duration(milliseconds: 10));

      if (enabledModules.contains('deneme')) {
        modulesContent.addAll(await _buildTrialExamsSection(studentData, startEachModuleOnNewPage, fontBold));
        await Future.delayed(const Duration(milliseconds: 10));
      }

      if (enabledModules.contains('yazili')) {
        modulesContent.addAll(_buildWrittenExamsSection(studentData, startEachModuleOnNewPage, fontBold));
        await Future.delayed(const Duration(milliseconds: 10));
      }

      if (enabledModules.contains('odev')) {
        modulesContent.addAll(_buildHomeworkSection(studentData, startEachModuleOnNewPage, fontBold));
        await Future.delayed(const Duration(milliseconds: 10));
      }
      
      if (enabledModules.contains('devamsizlik')) {
        modulesContent.addAll(_buildAttendanceSection(studentData, startEachModuleOnNewPage, fontBold));
        await Future.delayed(const Duration(milliseconds: 10));
      }

      if (enabledModules.contains('gorusme')) {
        modulesContent.addAll(_buildInterviewsSection(studentData, startEachModuleOnNewPage, fontBold));
        await Future.delayed(const Duration(milliseconds: 10));
      }

      if (enabledModules.contains('kitap')) {
        modulesContent.addAll(_buildBooksSection(studentData, startEachModuleOnNewPage, fontBold));
        await Future.delayed(const Duration(milliseconds: 10));
      }

      if (enabledModules.contains('calisma')) {
        modulesContent.addAll(_buildStudyProgramsSection(studentData, startEachModuleOnNewPage, fontBold));
        await Future.delayed(const Duration(milliseconds: 10));
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          theme: pw.ThemeData.withFont(base: font, bold: fontBold, italic: fontItalic),
          header: (pw.Context context) {
            return pw.Column(
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('ÖĞRENCİ PORTFOLYO RAPORU', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900, fontSize: 14)),
                    if (systemLogo != null) pw.Image(pw.MemoryImage(systemLogo), height: 35),
                  ],
                ),
                pw.Divider(thickness: 1, color: PdfColors.indigo900),
                pw.SizedBox(height: 10),
              ],
            );
          },
          footer: (pw.Context context) {
            return pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(top: 10),
              child: pw.Text(
                'Sayfa ${context.pageNumber} / ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
            );
          },
          build: (pw.Context context) => modulesContent,
        ),
      );

      await Future.delayed(Duration.zero);
      return pdf.save();
    } catch (e) {
      print("PDF Build Error: $e");
      final errPdf = pw.Document();
      errPdf.addPage(pw.Page(build: (p) => pw.Center(child: pw.Text("Rapor hazirlanirken hata olustu: $e"))));
      return errPdf.save();
    }
  }

  pw.Widget _sectionMiniHeader(String title, PdfColor color) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      decoration: pw.BoxDecoration(color: color, borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(4))),
      child: pw.Text(title, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.center),
    );
  }

  String _mapSubjectToCode(String subject) {
    final s = subject.toLowerCase().trim()
        .replaceAll('i̇', 'i').replaceAll('ı', 'i')
        .replaceAll('ö', 'o').replaceAll('ü', 'u')
        .replaceAll('ş', 's').replaceAll('ç', 'c')
        .replaceAll('ğ', 'g');
    if (s.contains('turkce') || s.contains('trk') || s.contains('tur')) return 'TRK';
    if (s.contains('matematik') || s.contains('mat') || s.contains('mtm')) return 'MAT';
    if (s.contains('fen') || s.contains('bilim') || s.contains('fb')) return 'FEN';
    if (s.contains('sosyal') || s.contains('sos') || s.contains('ink') || s.contains('sb')) return 'SOS';
    if (s.contains('ing') || s.contains('eng')) return 'İNG';
    if (s.contains('din') || s.contains('dkab') || s.contains('ahlak')) return 'DİN';
    return subject.toUpperCase();
  }

  pw.Widget _buildSummaryAveragesTable(Map<dynamic, dynamic> nets, Map<dynamic, dynamic> counts) {
    const subjects = ['TRK', 'SOS', 'DİN', 'İNG', 'MAT', 'FEN', 'T.NET'];
    
    dynamic getNet(String code) {
      if (code == 'T.NET') {
        double total = 0;
        ['TRK', 'MAT', 'FEN', 'SOS', 'İNG', 'DİN'].forEach((c) => total += (nets[c] as num? ?? 0.0).toDouble());
        return total > 0 ? total : (nets['T.NET'] ?? 0.0);
      }
      return nets[code] ?? 0.0;
    }

    pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );

    List<pw.TableRow> rows = [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: ['', ...subjects].map((s) => _cell(s, bold: true)).toList()
      ),
      pw.TableRow(
        children: [
          _cell('ORTALAMA NET', bold: true),
          ...subjects.map((s) => _cell(_formatNum(getNet(s)), bold: true))
        ]
      ),
      pw.TableRow(
        children: [
          _cell('ORTALAMA SORU SAYISI', bold: true),
          ...subjects.map((s) => _cell((counts[s] as num?)?.toString() ?? '0'))
        ]
      )
    ];

    return pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300), children: rows);
  }

  String _formatNum(dynamic v, {int precision = 2}) {
    if (v == null) return '0';
    if (v is! num) {
      final n = double.tryParse(v.toString());
      if (n == null) return '0';
      return n.toStringAsFixed(precision);
    }
    return v.toStringAsFixed(precision);
  }

  pw.Widget _sectionHeader(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 5, top: 10),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.indigo900, width: 2))),
      child: pw.Row(children: [
         pw.Text(title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
      ]),
    );
  }

  Future<List<pw.Widget>> _buildTrialExamsSection(Map<String, dynamic> data, bool newPage, pw.Font fontBold) async {
    final trialExams = data['trialExams'] as List<dynamic>? ?? [];
    final summary = data['summary'] as Map<String, dynamic>? ?? {};
    
    if (trialExams.isEmpty) return [if (newPage) pw.NewPage(), _sectionHeader('DENEME SINAVLARI ANALİZİ'), pw.Text('Deneme sınav verisi bulunamadı.')];

    List<pw.Widget> widgets = [];
    if (newPage) widgets.add(pw.NewPage());
    widgets.add(_sectionHeader('DENEME SINAVLARI ANALİZİ'));
    widgets.add(pw.SizedBox(height: 15));

    widgets.add(_sectionMiniHeader('BİREYSEL SINAV SONUÇLARI', PdfColors.indigo900));
    
    List<pw.TableRow> examRows = [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('SINAV ADI (TARİH)', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('PUAN', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('TOPLAM NET', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
            ...['TRK', 'SOS', 'DİN', 'İNG', 'MAT', 'FEN'].map((s) => pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(s, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)))),
        ]
      )
    ];

    for (var e in trialExams) {
        final examName = e['examName'] ?? 'Adsız Sınav';
        final date = e['date'] ?? '';
        final subjects = e['subjects'] as Map? ?? {};
        
        dynamic getVal(List<String> keys) {
            String normalize(String s) {
              return s.toLowerCase().trim()
                  .replaceAll('i̇', 'i').replaceAll('ı', 'i')
                  .replaceAll('ö', 'o').replaceAll('ü', 'u')
                  .replaceAll('ş', 's').replaceAll('ç', 'c')
                  .replaceAll('ğ', 'g');
            }

            for (var entry in subjects.entries) {
              final kNorm = normalize(entry.key.toString());
              for (var key in keys) {
                final targetNorm = normalize(key);
                if (kNorm == targetNorm || kNorm.contains(targetNorm)) {
                  return entry.value['net'] ?? entry.value['netler'] ?? '0';
                }
              }
            }
            return '0';
        }

        final trk = getVal(['Türkçe', 'TRK', 'TUR']);
        final sos = getVal(['Sosyal Bilgiler', 'SOS', 'SB', 'İnkılap Tarihi', 'İNK']);
        final din = getVal(['Din Kültürü ve Ahlak Bilgisi', 'Din Kültürü', 'DİN', 'DKAB', 'Ahlak']);
        final ing = getVal(['İngilizce', 'İNG', 'ENG', 'i̇ng', 'ıng']);
        final mat = getVal(['İlköğretim Matematik', 'Matematik', 'MAT', 'MTM']);
        final fen = getVal(['Fen Bilimleri', 'FEN', 'FB']);

        examRows.add(pw.TableRow(
            children: [
                pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$examName ($date)', style: const pw.TextStyle(fontSize: 7))),
                pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(_formatNum(e['score'], precision: 3), style: const pw.TextStyle(fontSize: 8))),
                pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(_formatNum(e['net'], precision: 2), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900))),
                ...[trk, sos, din, ing, mat, fen].map((v) => pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(_formatNum(v, precision: 2), style: const pw.TextStyle(fontSize: 8)))),
            ]
        ));
    }

    widgets.add(pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300), children: examRows));
    widgets.add(pw.SizedBox(height: 20));

    widgets.add(_sectionMiniHeader('SINAVLARA GÖRE BAŞARI GRAFİĞİ', PdfColors.indigo900));
    widgets.add(pw.Container(
      height: 100,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.TableBorder.all(color: PdfColors.grey300)),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: trialExams.map((e) {
          final double success = (e['success'] as num?)?.toDouble() ?? 0.0;
          final double percent = success.clamp(0, 100);
          
          return pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('${percent.toStringAsFixed(0)}%', style: const pw.TextStyle(fontSize: 7, color: PdfColors.purple900)),
              pw.SizedBox(height: 2),
              pw.Container(
                width: 20,
                height: (percent * 0.6) + 2,
                decoration: const pw.BoxDecoration(
                  color: PdfColors.purple200,
                  border: pw.Border(left: pw.BorderSide(color: PdfColors.purple800, width: 1)),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text('${trialExams.indexOf(e) + 1}', style: const pw.TextStyle(fontSize: 7)),
            ],
          );
        }).toList(),
      ),
    ));

    // Success Chart removed percentile logic from here

    final topicStats = summary['globalTopicStats'] as Map<String, dynamic>? ?? {};
    
    if (topicStats.isNotEmpty) {
      widgets.add(pw.NewPage());
      widgets.add(_sectionHeader('KONU / KAZANIM BAŞARI ANALİZİ'));
      widgets.add(pw.SizedBox(height: 10));

      List<pw.TableRow> tableRows = [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.purple900),
          children: [
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('DERS / KONU ADI', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8))),
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('SS', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8))),
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('D', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8))),
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Y', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8))),
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('B', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8))),
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('NET', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8))),
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('BAŞARI', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8))),
          ]
        )
      ];

      for (var entry in topicStats.entries) {
        final subj = entry.key;
        final topics = entry.value as Map;
        
        await Future.delayed(const Duration(milliseconds: 5));

        // Subject Header Row
        tableRows.add(pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.purple50),
          children: [
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(subj.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.purple900, fontSize: 8))),
            ...List.generate(6, (_) => pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(''))),
          ]
        ));

        topics.forEach((tName, stats) {
          final net = (stats['net'] as num?)?.toDouble() ?? 0.0;
          final ss = (stats['ss'] as num?)?.toInt() ?? 1;
          final d = stats['d'] ?? 0;
          final y = stats['y'] ?? 0;
          final b = stats['b'] ?? 0;
          final success = (d / ss * 100).clamp(0, 100);
          
          PdfColor badgeColor = PdfColors.red;
          if (success > 80) badgeColor = PdfColors.green;
          else if (success > 50) badgeColor = PdfColors.orange;

          tableRows.add(pw.TableRow(
            children: [
              pw.Padding(padding: const pw.EdgeInsets.only(left: 10, top: 4, bottom: 4), child: pw.Text(tName.toString(), style: const pw.TextStyle(fontSize: 7))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(ss.toString(), style: const pw.TextStyle(fontSize: 7))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(d.toString(), style: pw.TextStyle(fontSize: 7, color: PdfColors.green700))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(y.toString(), style: pw.TextStyle(fontSize: 7, color: PdfColors.red700))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(b.toString(), style: pw.TextStyle(fontSize: 7))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(net.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 7))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), 
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: pw.BoxDecoration(color: badgeColor, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
                  child: pw.Text('%${success.toInt()}', style: pw.TextStyle(color: PdfColors.white, fontSize: 7, fontWeight: pw.FontWeight.bold)),
                )
              ),
            ]
          ));
        });
      }

      widgets.add(pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300),
        columnWidths: {0: const pw.FlexColumnWidth(4), 6: const pw.IntrinsicColumnWidth()},
        children: tableRows,
      ));
    }

    return widgets;
  }

  List<pw.Widget> _buildPremiumFirstPage(Map<String, dynamic> data, Uint8List? logo, pw.Font fontBold) {
     final summary = data['summary'] as Map<String, dynamic>? ?? {};
     final studentPhoto = data['studentPhoto'] as Uint8List?;
     final double avgPoint = (summary['avgPoint'] as num?)?.toDouble() ?? 0.0;

     // Robust Percentile logic for the first page
     String displayPercentile = "0.00";
     if (avgPoint > 100) {
        final trials = data['trialExams'] as List? ?? [];
        double realP = 0.0;
        if (trials.isNotEmpty) {
          realP = (trials.first['percentile'] as num?)?.toDouble() ?? 0.0;
        }
        
        if (realP > 0) {
          displayPercentile = realP.toStringAsFixed(2);
        } else {
          // Fallback LGS estimation
          if (avgPoint >= 490) displayPercentile = "0.10";
          else if (avgPoint >= 450) displayPercentile = "2.00";
          else if (avgPoint >= 400) displayPercentile = "8.00";
          else if (avgPoint >= 350) displayPercentile = "15.00";
          else if (avgPoint >= 300) displayPercentile = "25.00";
          else displayPercentile = "45.00";
        }
     }
     
     return [
         // Header with Student Profile
         pw.Container(
           padding: const pw.EdgeInsets.all(20),
           decoration: const pw.BoxDecoration(
             color: PdfColors.indigo900,
             borderRadius: pw.BorderRadius.all(pw.Radius.circular(15)),
           ),
           child: pw.Row(
             children: [
               data['studentPhoto'] != null 
                ? pw.ClipRRect(
                  horizontalRadius: 40, verticalRadius: 40,
                  child: pw.Image(pw.MemoryImage(data['studentPhoto'] as Uint8List), width: 80, height: 80, fit: pw.BoxFit.cover)
                )
                : pw.Container(
                  width: 80, height: 80,
                  decoration: const pw.BoxDecoration(color: PdfColors.white, shape: pw.BoxShape.circle),
                  child: pw.Center(
                    child: pw.Text(
                      (data['fullName'] ?? data['name'] ?? 'X')[0].toUpperCase(),
                      style: pw.TextStyle(fontSize: 40, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)
                    )
                  )
                ),
               pw.SizedBox(width: 25),
               pw.Column(
                 crossAxisAlignment: pw.CrossAxisAlignment.start,
                 children: [
                    pw.Text((data['fullName'] ?? 'Öğrenci Adı Soyadı').toString().toUpperCase(), 
                      style: pw.TextStyle(color: PdfColors.white, fontSize: 22, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 8),
                    pw.Row(children: [
                      pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4), 
                        decoration: const pw.BoxDecoration(color: PdfColors.indigo700, borderRadius: pw.BorderRadius.all(pw.Radius.circular(20))),
                        child: pw.Text(data['className'] ?? data['classLevel'] ?? 'Sınıf Bilgisi', style: const pw.TextStyle(color: PdfColors.white, fontSize: 10))),
                      pw.SizedBox(width: 10),
                      pw.Text('Okul No: ${data['studentNumber'] ?? data['schoolNumber'] ?? '-'}', style: const pw.TextStyle(color: PdfColors.white, fontSize: 12)),
                    ]),
                 ],
               ),
             ],
           ),
         ),
         pw.SizedBox(height: 30),

         // Summary Dashboard Section
         _sectionHeader('GENEL BAKIŞ VE ÖZET'),
         pw.SizedBox(height: 20),
         pw.Container(
           height: 70,
           child: pw.Row(
             mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
             crossAxisAlignment: pw.CrossAxisAlignment.stretch,
             children: [
               pw.Expanded(child: _dashboardCard('Sınav Ortalaması', ['${_formatNum(summary['avgPoint'], precision: 1)} Puan', '${_formatNum(summary['avgNet'], precision: 2)} Net'], PdfColors.blue50)),
               pw.SizedBox(width: 10),
               pw.Expanded(child: _dashboardCard('Ödev Takibi', ['Toplam: ${summary['totalHw'] ?? 0}', 'Tamam: ${summary['completedHw'] ?? 0}'], PdfColors.green50)),
               pw.SizedBox(width: 10),
               pw.Expanded(child: _dashboardCard('Devamsızlık', ['${_formatNum(summary['totalAbsence'], precision: 1)} Gün'], PdfColors.orange50)),
             ],
           ),
         ),
         pw.SizedBox(height: 30),

         // Requested: Summary Averages on first page
         if (summary.containsKey('subjectAvgNets')) ...[
            _sectionMiniHeader('GENEL DENEME ORTALAMALARI', PdfColors.indigo900),
            _buildSummaryAveragesTable(summary['subjectAvgNets'] ?? {}, summary['subjectQuestionCounts'] ?? {}),
            
            // Percentile Box moved here
            if (avgPoint > 100) ...[
              pw.SizedBox(height: 15),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.purple50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                  border: pw.Border.all(color: PdfColors.purple200)
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Text('Tahmini Yüzdelik Dilim', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.purple900)),
                        pw.Spacer(),
                        pw.Text('2025 LGS Verilerine Göre', style: const pw.TextStyle(fontSize: 8, color: PdfColors.purple300)),
                      ]
                    ),
                    pw.SizedBox(height: 10),
                    pw.Center(
                      child: pw.Text('%$displayPercentile', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.purple900)),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Text(
                      "LGS'de yüzdelik dilimler sadece puana değil, o yıl sınava giren öğrenci sayısına ve standart sapmaya da bağlıdır. Bu veriler 'genel ortalamaları' yansıtır. Sistem, öğrenciye bu sonuçları gösterirken her zaman 'Tahmini Referans Değerleridir' ibaresini eklemelidir.",
                      style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700, fontStyle: pw.FontStyle.italic)
                    ),
                  ]
                )
              ),
            ],
            pw.SizedBox(height: 30),
         ],
 
         pw.Divider(thickness: 1, color: PdfColors.indigo900),
         pw.Padding(
           padding: const pw.EdgeInsets.symmetric(vertical: 10),
           child: pw.Row(
             mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
             children: [
               pw.Text('EDU-KN EĞİTİM YÖNETİM SİSTEMİ', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
               pw.Text('Rapor Tarihi: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
             ],
           ),
         ),
       ];
  }

  String _formatDate(dynamic date) {
    if (date == null) return '-';
    if (date is DateTime) return DateFormat('dd.MM.yyyy').format(date);
    if (date is String) return date;
    try {
      if (date.runtimeType.toString().contains('Timestamp')) {
        return DateFormat('dd.MM.yyyy').format(date.toDate());
      }
    } catch (_) {}
    return date.toString();
  }

  pw.Widget _dashboardCard(String title, List<String> lines, PdfColor color) {
    return pw.Container(
      width: double.infinity, 
      height: 65,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(title.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.grey800)),
          pw.SizedBox(height: 8),
          ...lines.map((l) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Text(l, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF1A237E))),
          )),
        ],
      ),
    );
  }

  pw.Widget _infoRowPlain(String label, dynamic val) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        children: [
          pw.SizedBox(width: 100, child: pw.Text('$label:', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700))),
          pw.Expanded(child: pw.Text(val?.toString() ?? '-', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold))),
        ],
      ),
    );
  }

  List<pw.Widget> _buildWrittenExamsSection(Map<String, dynamic> data, bool newPage, pw.Font fontBold) {
     final exams = data['writtenExams'] as List<dynamic>? ?? [];
     return [
       if (newPage) pw.NewPage(),
       _sectionHeader('Yazılı Sınavlar'),
       pw.SizedBox(height: 15),
       if (exams.isEmpty) pw.Text('Yazılı sınav kaydı bulunmamaktadır.', style: const pw.TextStyle(fontSize: 10))
       else pw.TableHelper.fromTextArray(
         headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo700),
         headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
         cellStyle: const pw.TextStyle(fontSize: 10),
         data: [
           ['Ders', 'Sınav', 'Tarih', 'Not'],
           ...exams.map((e) => [e['subject'] ?? '-', e['examName'] ?? '-', _formatDate(e['date']), e['score']?.toString() ?? '-'])
         ]
       )
     ];
  }

  List<pw.Widget> _buildHomeworkSection(Map<String, dynamic> data, bool newPage, pw.Font fontBold) {
     final homeworks = data['homeworks'] as List<dynamic>? ?? [];
     return [
       if (newPage) pw.NewPage(),
       _sectionHeader('Ödev Takibi'),
       pw.SizedBox(height: 15),
       if (homeworks.isEmpty) pw.Text('Ödev kaydı bulunmamaktadır.', style: const pw.TextStyle(fontSize: 10))
       else pw.TableHelper.fromTextArray(
         headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo700),
         headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
         cellStyle: const pw.TextStyle(fontSize: 10),
         data: [
           ['Ders', 'Konu', 'Teslim Tarihi', 'Durum'],
           ...homeworks.map((h) => [h['subject'] ?? '-', h['title'] ?? '-', _formatDate(h['deadline']), h['status'] ?? 'Bekliyor'])
         ]
       )
     ];
  }

  List<pw.Widget> _buildAttendanceSection(Map<String, dynamic> data, bool newPage, pw.Font fontBold) {
     final attendance = data['attendance'] as List<dynamic>? ?? [];
     return [
       if (newPage) pw.NewPage(),
       _sectionHeader('Devamsızlık Takibi'),
       pw.SizedBox(height: 15),
       if (attendance.isEmpty) pw.Text('Devamsızlık kaydı bulunmamaktadır.', style: const pw.TextStyle(fontSize: 10))
       else pw.TableHelper.fromTextArray(
         headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo700),
         headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
         cellStyle: const pw.TextStyle(fontSize: 10),
         data: [
           ['Tür', 'Tarih', 'Okul No', 'Durum / Açıklama'],
           ...attendance.map((a) {
             final status = a['status']?.toString().toLowerCase() ?? '';
             String trStatus = 'Devamsız';
             if (status == 'permitted' || status == 'izinli') trStatus = 'İzinli';
             else if (status == 'late' || status == 'geç') trStatus = 'Geç';
             else if (status == 'report' || status == 'raporlu') trStatus = 'Raporlu';
             
             return [
               trStatus, 
               _formatDate(a['date']), 
               a['studentNumber']?.toString() ?? '-', 
               a['description'] ?? trStatus
             ];
           })
         ]
       )
     ];
  }

  List<pw.Widget> _buildInterviewsSection(Map<String, dynamic> data, bool newPage, pw.Font fontBold) {
     final interviews = data['interviews'] as List<dynamic>? ?? [];
     return [
       if (newPage) pw.NewPage(),
       _sectionHeader('Görüşmeler'),
       pw.SizedBox(height: 15),
       if (interviews.isEmpty) pw.Text('Görüşme kaydı bulunmamaktadır.', style: const pw.TextStyle(fontSize: 10))
       else pw.TableHelper.fromTextArray(
         headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo700),
         headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
         cellStyle: const pw.TextStyle(fontSize: 10),
         data: [
           ['Görüşmeci', 'Tür', 'Tarih', 'Özet'],
           ...interviews.map((i) => [i['counselorName'] ?? '-', i['type'] ?? 'Genel', _formatDate(i['date']), i['summary'] ?? '-'])
         ]
       )
     ];
  }

  List<pw.Widget> _buildBooksSection(Map<String, dynamic> data, bool newPage, pw.Font fontBold) {
     final books = data['books'] as List<dynamic>? ?? [];
     return [
       if (newPage) pw.NewPage(),
       _sectionHeader('Kitap ve Okuma'),
       pw.SizedBox(height: 15),
       if (books.isEmpty) pw.Text('Okuma kaydı bulunmamaktadır.', style: const pw.TextStyle(fontSize: 10))
       else pw.TableHelper.fromTextArray(
         headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo700),
         headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
         cellStyle: const pw.TextStyle(fontSize: 10),
         data: [
           ['Kitap Adı', 'Yazar', 'Bitiş Tarihi', 'Sayfa'],
           ...books.map((b) => [b['bookName'] ?? '-', b['author'] ?? '-', _formatDate(b['finishDate']), b['pageCount']?.toString() ?? '-'])
         ]
       )
     ];
  }

  List<pw.Widget> _buildStudyProgramsSection(Map<String, dynamic> data, bool newPage, pw.Font fontBold) {
     final progs = data['studyPrograms'] as List<dynamic>? ?? [];
     return [
       if (newPage) pw.NewPage(),
       _sectionHeader('Çalışma Programları'),
       pw.SizedBox(height: 15),
       if (progs.isEmpty) pw.Text('Program kaydı bulunmamaktadır.', style: const pw.TextStyle(fontSize: 10))
       else pw.TableHelper.fromTextArray(
         headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo700),
         headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
         cellStyle: const pw.TextStyle(fontSize: 10),
         data: [
           ['Program Adı', 'Tarih', 'Tamamlama (%)'],
           ...progs.map((p) => [p['name'] ?? '-', _formatDate(p['date']), '%${(p['progress'] ?? 0).toStringAsFixed(0)}'])
         ]
       )
     ];
  }
}
