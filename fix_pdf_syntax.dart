import 'dart:io';

void main() {
  final file = File('lib/services/pdf_service.dart');
  if (!file.existsSync()) {
    print('File not found');
    return;
  }

  String content = file.readAsStringSync();

  // 1. Remove the previously inserted methods (2511 to 2838 area) 
  // and replace with corrected versions using pw.Table (not TableHelper) for custom widgets.

  String correctedMethods = """
  pw.Widget _sectionMiniHeader(String title, PdfColor color) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      decoration: pw.BoxDecoration(color: color, borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(4))),
      child: pw.Text(title, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.center),
    );
  }

  pw.Widget _buildSummaryAveragesTable(Map<dynamic, dynamic> nets, Map<dynamic, dynamic> counts) {
    const subjects = ['T.NET', 'TRK', 'MAT', 'FEN', 'SOS', 'İNG', 'DİN'];
    
    double totalNet = 0;
    int totalQ = 0;
    nets.values.forEach((v) => totalNet += (v as num).toDouble());
    counts.values.forEach((v) => totalQ += (v as num).toInt());

    final headerRow = ['', ...subjects];
    final row1 = ['ORTALAMA SORU SAYISI', totalQ.toString()];
    final row2 = ['ORTALAMA NET', totalNet.toStringAsFixed(2)];

    for (var s in subjects.skip(1)) {
      final key = nets.keys.firstWhere((k) => k.toString().toUpperCase().contains(s), orElse: () => null);
      if (key != null) {
        row1.add(counts[key]?.toString() ?? '-');
        row2.add((nets[key] as double? ?? 0.0).toStringAsFixed(2));
      } else {
        row1.add('-');
        row2.add('-');
      }
    }

    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
      cellStyle: const pw.TextStyle(fontSize: 8),
      data: [headerRow, row1, row2],
    );
  }

  pw.Widget _buildPremiumFirstPage(Map<String, dynamic> data, Uint8List? logo, pw.Font fontBold) {
    final summary = data['summary'] ?? {};
    final fullName = data['fullName']?.toString().toUpperCase() ?? 'İSİMSİZ ÖĞRENCİ';
    final examCount = summary['examCount'] ?? 0;
    
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('PORTFOLYO GELİŞİM RAPORU', style: pw.TextStyle(font: fontBold, fontSize: 24, color: PdfColors.indigo900)),
                pw.Text('Rapor Tarihi: \${DateFormat('dd.MM.yyyy').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              ],
            ),
            if (logo != null) pw.Image(pw.MemoryImage(logo), height: 60),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(thickness: 2, color: PdfColors.indigo900),
        pw.SizedBox(height: 15),

        // Profile Section
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 100, height: 100,
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                border: pw.Border.all(color: PdfColors.indigo900, width: 2),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
              ),
              alignment: pw.Alignment.center,
              child: pw.Icon(pw.IconData(0xe7fd), color: PdfColors.indigo900, size: 50),
            ),
            pw.SizedBox(width: 20),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(fullName, style: pw.TextStyle(font: fontBold, fontSize: 18, color: PdfColors.indigo900)),
                  pw.SizedBox(height: 10),
                  pw.Row(children: [
                    pw.Expanded(child: _infoRowPlain('Okul No', data['schoolNumber'] ?? data['studentNumber'] ?? data['no'])),
                    pw.Expanded(child: _infoRowPlain('Sınıf / Şube', data['className'] ?? data['classLevel'])),
                  ]),
                  pw.Row(children: [
                    pw.Expanded(child: _infoRowPlain('Cinsiyet', data['gender'])),
                    pw.Expanded(child: _infoRowPlain('Rapor Periyodu', 'Aktif Dönem')),
                  ]),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 20),

        // Exam Summary Sentence
        pw.Text('Sayın \$fullName girmiş olduğunuz \$examCount deneme ile analiziniz yapıldı. Deneme sonuçlarınıza göre aldığınız puan ve ortalamalar aşağıdaki gibidir.', 
           style: const pw.TextStyle(fontSize: 10, color: PdfColors.black)),
        pw.SizedBox(height: 15),

        // ORTALAMA NETLER Table
        _sectionMiniHeader('ORTALAMA NETLER', PdfColors.purple900),
        _buildSummaryAveragesTable(summary['subjectAvgNets'] ?? {}, summary['subjectQuestionCounts'] ?? {}),
        
        pw.SizedBox(height: 20),

        // PUAN VE YÜZDELİK DİLİM
        _sectionMiniHeader('PUAN VE ANALİZ ÖZETİ', PdfColors.purple900),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.purple900),
          cellStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: PdfColors.black),
          columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(1)},
          data: [
            ['ANALİZ TÜRÜ', 'DEĞER'],
            ['GENEL PUAN ORTALAMASI', (summary['avgPoint'] as double? ?? 0.0).toStringAsFixed(2)],
            ['GENEL NET ORTALAMASI', (summary['avgNet'] as double? ?? 0.0).toStringAsFixed(2)],
          ],
        ),

        pw.SizedBox(height: 15),
        
        // Other Stats Row
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _dashboardCard('ÖDEV TAKİBİ', [
              'Yapılan: \${summary['completedHw'] ?? 0}',
              'Eksi: \${summary['missingHw'] ?? 0}',
            ], PdfColors.green50),
            _dashboardCard('DEVAMSIZLIK', [
              'Toplam Gün: \${summary['totalAbsence']?.toStringAsFixed(1) ?? '0.0'}',
            ], PdfColors.orange50),
          ],
        ),
        
        pw.Spacer(),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: const pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          width: double.infinity,
          child: pw.Text(
            'Bu rapor öğrencinin seçili dönem boyunca akademik gelişimi kapsayan bütüncül bir değerlendirmedir.',
            style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
            textAlign: pw.TextAlign.center,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildTrialExamsSection(Map<String, dynamic> data, bool newPage, pw.Font fontBold) {
    final trialExams = data['trialExams'] as List<dynamic>? ?? [];
    final summary = data['summary'] ?? {};
    
    List<pw.Widget> widgets = [];
    if (newPage) widgets.add(pw.NewPage());
    widgets.add(_sectionHeader('Deneme Sınavı Performansı'));
    
    if (trialExams.isEmpty) {
      widgets.add(pw.Padding(padding: const pw.EdgeInsets.only(top: 15), child: pw.Text('Kayda değer deneme sınavı verisi bulunamadı.', style: const pw.TextStyle(fontSize: 10))));
      return pw.Column(children: widgets);
    }

    widgets.add(pw.SizedBox(height: 15));
    _sectionMiniHeader('DEĞERLENDİRİLEN SINAVLAR', PdfColors.purple900);
    
    const subjects = ['T.NET', 'TRK', 'MAT', 'FEN', 'SOS', 'İNG', 'DİN'];
    
    widgets.add(pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.purple800),
      cellStyle: const pw.TextStyle(fontSize: 8),
      data: [
        ['Sınav Adı', 'SS', ...subjects],
        ...trialExams.asMap().entries.map((entry) {
          final idx = entry.key + 1;
          final exam = entry.value;
          final row = ['\$idx. \${exam['examName']}'];
          row.add(exam['totalQuestions']?.toString() ?? '-');
          row.add(exam['net']?.toStringAsFixed(1) ?? '-');

          final subNets = exam['subjects'] as Map? ?? {};
          for (var s in subjects.skip(1)) {
            final key = subNets.keys.firstWhere((k) => k.toString().toUpperCase().contains(s), orElse: () => null);
            row.add(key != null ? (subNets[key]['net'] ?? '-').toString() : '-');
          }
          return row;
        }).toList(),
        ['ORTALAMA', '-', summary['avgNet']?.toStringAsFixed(2) ?? '-', 
          ...subjects.skip(1).map((s) {
            final key = (summary['subjectAvgNets'] as Map?)?.keys.firstWhere((k) => k.toString().toUpperCase().contains(s), orElse: () => null);
            return key != null ? (summary['subjectAvgNets'][key] as double).toStringAsFixed(2) : '-';
          })
        ]
      ],
    ));

    // Success Bar Chart Placeholder
    widgets.add(pw.SizedBox(height: 30));
    widgets.add(pw.Center(child: pw.Text('SINAV BAŞARI YÜZDELERİ GRAFİĞİ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.purple900))));
    widgets.add(pw.SizedBox(height: 10));
    
    widgets.add(pw.Container(
      height: 120,
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: trialExams.map((e) {
          final net = (e['net'] as num?)?.toDouble() ?? 0.0;
          final q = (e['totalQuestions'] as num?)?.toInt() ?? 1;
          final percent = (net / q * 100).clamp(0, 100).toDouble();
          
          return pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('\${percent.toStringAsFixed(0)}%', style: const pw.TextStyle(fontSize: 7, color: PdfColors.purple900)),
              pw.SizedBox(height: 2),
              pw.Container(
                width: 20,
                height: (percent * 0.8) + 2,
                decoration: const pw.BoxDecoration(
                  color: PdfColors.purple200,
                  border: pw.Border(left: pw.BorderSide(color: PdfColors.purple800, width: 1)),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text('\${trialExams.indexOf(e) + 1}', style: const pw.TextStyle(fontSize: 7)),
            ],
          );
        }).toList(),
      ),
    ));

    // 3. Topic Analysis Section
    widgets.add(pw.NewPage());
    widgets.add(_sectionHeader('KONU BAŞARI ANALİZİ'));
    widgets.add(pw.SizedBox(height: 15));
    
    final topicStats = summary['globalTopicStats'] as Map<String, dynamic>? ?? {};
    
    if (topicStats.isEmpty) {
      widgets.add(pw.Text('Konu bazlı analiz verisi bulunamadı.', style: const pw.TextStyle(fontSize: 10)));
    } else {
      // Use pw.Table because fromTextArray won't handle the Container badges easily without specific config
      List<pw.TableRow> tableRows = [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.purple900),
          children: [
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('DERS / KONU ADI', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8))),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('SS', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8))),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('D', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8))),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Y', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8))),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('B', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8))),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('NET', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8))),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('BAŞARI', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8))),
          ]
        )
      ];
      
      topicStats.forEach((subj, topics) {
        tableRows.add(pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(subj.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900, fontSize: 8))),
            pw.Text(''), pw.Text(''), pw.Text(''), pw.Text(''), pw.Text(''), pw.Text(''),
          ]
        ));
        
        (topics as Map).forEach((tName, stats) {
          final net = stats['net'] as double;
          final ss = stats['ss'] as int;
          final success = (net / ss * 100).clamp(0, 100);
          
          PdfColor badgeColor = PdfColors.red;
          if (success > 80) badgeColor = PdfColors.green;
          else if (success > 50) badgeColor = PdfColors.orange;

          tableRows.add(pw.TableRow(
            children: [
              pw.Padding(padding: const pw.EdgeInsets.only(left: 10, top: 4, bottom: 4), child: pw.Text(tName.toString(), style: const pw.TextStyle(fontSize: 8))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(ss.toString(), style: const pw.TextStyle(fontSize: 8))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(stats['d'].toString(), style: const pw.TextStyle(fontSize: 8))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(stats['y'].toString(), style: const pw.TextStyle(fontSize: 8))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(stats['b'].toString(), style: const pw.TextStyle(fontSize: 8))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(net.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 8))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Container(
                 padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                 decoration: pw.BoxDecoration(color: badgeColor, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
                 child: pw.Text('%\${success.toStringAsFixed(0)}', style: pw.TextStyle(color: PdfColors.white, fontSize: 7, fontWeight: pw.FontWeight.bold)),
              )),
            ]
          ));
        });
      });

      widgets.add(pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300),
        columnWidths: {0: const pw.FlexColumnWidth(4), 6: const pw.IntrinsicColumnWidth()},
        children: tableRows,
      ));
    }

    return pw.Column(children: widgets);
  }
""";

  // Re-identifying the indices in the CURRENT file content
  int startIdx = content.indexOf('pw.Widget _sectionMiniHeader');
  int endIdx = content.indexOf('pw.Widget _buildInterviewsSection');

  if (startIdx != -1 && endIdx != -1) {
    String finalContent = content.substring(0, startIdx) + correctedMethods + "\n\n  " + content.substring(endIdx);
    file.writeAsStringSync(finalContent);
    print('Fix complete');
  } else {
    print('Failed to locate headers');
  }
}
