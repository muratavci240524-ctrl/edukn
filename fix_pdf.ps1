$filePath = 'c:\Users\mavci\Desktop\Projeler\eduKN\edukn21.11.2025\edukn\lib\services\pdf_service.dart'
$content = Get-Content -Raw -Path $filePath

$startMarker = 'await Future.delayed\(Duration.zero\);'
$endMarker = '  }\r?\n\r?\n  // --- PREMIUM UI BUILDER METHODS ---'

$replacement = @"
    await Future.delayed(Duration.zero);

    // --- SEGMENT 2: TRIAL EXAMS ---
    if (enabledModules.contains('deneme')) {
      modulesContent.add(_buildTrialExamsSection(studentData, startEachModuleOnNewPage, fontBold));
      await Future.delayed(Duration.zero);
    }

    // --- SEGMENT 3: WRITTEN EXAMS ---
    if (enabledModules.contains('yazili')) {
      modulesContent.add(_buildWrittenExamsSection(studentData, startEachModuleOnNewPage, fontBold));
      await Future.delayed(Duration.zero);
    }

    // --- SEGMENT 4: HOMEWORK & ATTENDANCE ---
    if (enabledModules.contains('odev')) {
      modulesContent.add(_buildHomeworkSection(studentData, startEachModuleOnNewPage, fontBold));
      await Future.delayed(Duration.zero);
    }
    
    if (enabledModules.contains('devamsizlik')) {
      modulesContent.add(_buildAttendanceSection(studentData, startEachModuleOnNewPage, fontBold));
      await Future.delayed(Duration.zero);
    }

    // --- SEGMENT 5: OTHER MODULES ---
    if (enabledModules.contains('gorusme')) {
      modulesContent.add(_buildInterviewsSection(studentData, startEachModuleOnNewPage, fontBold));
      await Future.delayed(Duration.zero);
    }

    if (enabledModules.contains('kitap')) {
      modulesContent.add(_buildBooksSection(studentData, startEachModuleOnNewPage, fontBold));
      await Future.delayed(Duration.zero);
    }

    if (enabledModules.contains('calisma')) {
      modulesContent.add(_buildStudyProgramsSection(studentData, startEachModuleOnNewPage, fontBold));
      await Future.delayed(Duration.zero);
    }

    // Add all pre-built segments to a MultiPage
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold, italic: fontItalic),
        header: (pw.Context context) {
          if (context.pageNumber == 1) return pw.SizedBox();
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

    return pdf.save();
  }
"@

# Perform regex replacement
$fixedContent = [regex]::Replace($content, "(?s)$startMarker.*?(?=$endMarker)", $replacement)

Set-Content -Path $filePath -Value $fixedContent -NoNewline -Encoding UTF8
