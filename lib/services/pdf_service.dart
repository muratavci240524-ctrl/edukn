import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/assessment/trial_exam_model.dart';
import '../models/field_trip_model.dart'; // Add this import

class PdfService {
  Future<Uint8List> generateStaffPdf(
    Map<String, dynamic> staff,
    List<String> selectedSections,
  ) async {
    final pdf = pw.Document();

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
          _buildFileRow('İkametgâh', isUploaded(official, 'residence')),
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
      headers: ['Sıra', 'Öğrenci Adı', 'Şube', 'Ort. Puan'],
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
      headers: ['Öğrenci', 'Şube', 'İlk Net', 'Son Net', 'Gelişim'],
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
            _buildPdfSectionTitle('Şube Bazlı İlerleme Özeti'),
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
              'Şube Analiz Raporu',
              'Şubeler Arası Akademik Kıyaslama',
            ),
            pw.SizedBox(height: 20),
            _buildPdfSectionTitle('Şube Performans Tablosu'),
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
      headers: ['Şube', ...exams.map((e) => 'S${exams.indexOf(e) + 1}')],
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
      headers: ['Şube', ...subjects],
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
      headers: ['Sıra', 'İsim', 'Şube', 'Toplam $mode', 'Ort. $mode'],
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
                            pw.Text('Şoför: ${group.driverPhone}'),
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
}
