import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/odak_models.dart';
import 'odak_engine.dart';

/// ODAK-64 raporunu PDF'e dönüştürür (sıfır API maliyeti, tamamen yerel).
///
/// Yapı: her sınıf için bir kapak/özet sayfası, ardından her ders (branş)
/// KENDİ yeni sayfasından başlayan ayrıntılı bir bölümdür.
class OdakPdfService {
  static const _teal = PdfColors.teal700;
  static const _tealDark = PdfColors.teal900;

  /// Dosya adı öneki: marka Türkçe karakterlerden arındırılır (ör. "Performans_Ozeti", "ODAK64").
  static String fileBase(String brand) => brand
      .replaceAll('-', '')
      .replaceAll('Ö', 'O').replaceAll('ö', 'o')
      .replaceAll('Ü', 'U').replaceAll('ü', 'u')
      .replaceAll('Ş', 'S').replaceAll('ş', 's')
      .replaceAll('Ç', 'C').replaceAll('ç', 'c')
      .replaceAll('Ğ', 'G').replaceAll('ğ', 'g')
      .replaceAll('İ', 'I').replaceAll('ı', 'i')
      .replaceAll(RegExp(r'\s+'), '_');

  /// [classIds] boşsa tüm sınıflar, doluysa yalnızca verilen sınıflar basılır.
  static Future<Uint8List> build({
    required List<OdakClassGroup> groups,
    required OdakAnalyzer analyzer,
    required List<String> subjects,
    required String examName,
    String? schoolName,
    Set<String> classIds = const {},
    String brand = 'ODAK-64',
  }) async {
    final font = await PdfGoogleFonts.robotoRegular();
    final bold = await PdfGoogleFonts.robotoBold();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: bold),
      title: '$brand Raporu',
    );

    final selected =
        OdakClassGroup.visibleGroups(groups).where((g) => classIds.isEmpty || classIds.contains(g.id)).toList();
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

    pw.Widget header(String left) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _teal, width: 1.2)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                left,
                style: pw.TextStyle(font: bold, fontSize: 11, color: PdfColors.teal800),
              ),
              pw.Text(
                [if (schoolName != null && schoolName.isNotEmpty) schoolName, examName]
                    .join(' • '),
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
            ],
          ),
        );

    pw.Widget footer(pw.Context c) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '$brand • Kural tabanlı sınav analizi',
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey500),
            ),
            pw.Text(
              'Rapor tarihi: $dateStr • Sayfa ${c.pageNumber}/${c.pagesCount}',
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
            ),
          ],
        );

    for (final g in selected) {
      final gSubjects = g.filterSubjects(subjects);
      // 1) Sınıf kapak / özet sayfası
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (c) => _classCoverPage(g, analyzer, gSubjects, bold, header, dateStr, brand),
        ),
      );
      // 2) Her ders AYRI sayfadan başlar
      for (final subject in gSubjects) {
        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(28),
            header: (c) => header('$brand • ${g.name} • $subject'),
            footer: footer,
            build: (c) => _subjectSection(g, analyzer, subject, bold),
          ),
        );
      }
      // 3) Şubeye bağlı kurlar (ör. İngilizce kuru): şubenin içinde, kur olduğu belirtilerek
      for (final lk in OdakClassGroup.linkedTracks(g, analyzer.groups)) {
        for (final subject in lk.filterSubjects(subjects)) {
          doc.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(28),
              header: (c) => header('$brand • ${g.name} • $subject (Kur ${lk.shortLabel})'),
              footer: footer,
              build: (c) => _subjectSection(lk, analyzer, subject, bold),
            ),
          );
        }
      }
    }
    return doc.save();
  }

  // ───────────────────────── Sınıf kapağı ─────────────────────────

  static pw.Widget _classCoverPage(
    OdakClassGroup g,
    OdakAnalyzer a,
    List<String> subjects,
    pw.Font bold,
    pw.Widget Function(String) header,
    String dateStr,
    String brand,
  ) {
    final risky = a.getStudentWarnings(g.id);
    final riskyIds = risky.map((r) => r.ranked.student.id).toSet();
    final scores = g.students.map((s) => s.score).toList();
    final maxScore = scores.isEmpty ? 0.0 : scores.reduce((x, y) => x > y ? x : y);
    final minScore = scores.isEmpty ? 0.0 : scores.reduce((x, y) => x < y ? x : y);
    final n = g.students.length;

    // A4 (842pt) - kenar boşlukları (2x24) = ~794pt kullanılabilir yükseklik.
    // Sabit bölümler çıkarıldıktan sonra kalan yükseklik sınıf listesine verilir;
    // öğrenci sayısına göre sütun sayısı ve satır yüksekliği otomatik ayarlanır.
    const usable = 794.0;
    final fixed = 22.0 // üst başlık
        + 8 + 34 // banner
        + 8 + 48 // KPI
        + 26 // "Sınıf Listesi" başlığı
        + 26 // "Derslere Genel Bakış" başlığı
        + (subjects.length + 1) * 15.0 // ders tablosu
        + 22 // dipnot
        + 20; // alt bilgi
    final listH = (usable - fixed).clamp(150.0, 600.0);

    final cols = n <= 28 ? 1 : (n <= 60 ? 2 : 3);
    final rowsPerCol = n == 0 ? 1 : (n / cols).ceil();
    final rowH = (listH / (rowsPerCol + 1)).clamp(7.0, 17.0); // +1 başlık satırı
    final fs = (rowH * 0.56).clamp(4.5, 9.0);

    pw.Widget cell(String t, {double? w, pw.Alignment al = pw.Alignment.centerLeft, bool b = false, PdfColor? color}) {
      final txt = pw.Text(
        t,
        maxLines: 1,
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(font: b ? bold : null, fontSize: fs, color: color),
      );
      final box = pw.Container(
        alignment: al,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3),
        child: txt,
      );
      return w == null ? pw.Expanded(child: box) : pw.SizedBox(width: w, child: box);
    }

    pw.Widget colHeader() => pw.Container(
          height: rowH,
          color: _teal,
          child: pw.Row(
            children: [
              cell('Sıra', w: 24, al: pw.Alignment.center, b: true, color: PdfColors.white),
              cell('Öğrenci', b: true, color: PdfColors.white),
              cell('Şube', w: 30, al: pw.Alignment.center, b: true, color: PdfColors.white),
              cell('Puan', w: 32, al: pw.Alignment.centerRight, b: true, color: PdfColors.white),
            ],
          ),
        );

    pw.Widget listColumn(int start, int end) => pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 2),
            child: pw.Column(
              children: [
                colHeader(),
                for (var i = start; i < end; i++)
                  pw.Container(
                    height: rowH,
                    color: i.isEven ? PdfColors.white : PdfColors.grey100,
                    child: pw.Row(
                      children: [
                        cell('${g.students[i].rank}', w: 24, al: pw.Alignment.center),
                        cell(
                          '${g.students[i].student.name}'
                          '${riskyIds.contains(g.students[i].student.id) ? ' (!)' : ''}',
                          color: riskyIds.contains(g.students[i].student.id)
                              ? PdfColors.red700
                              : null,
                        ),
                        cell(g.students[i].student.branch, w: 30, al: pw.Alignment.center),
                        cell(g.students[i].score.toStringAsFixed(1),
                            w: 32, al: pw.Alignment.centerRight, b: true),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );

    final listCols = <pw.Widget>[];
    for (var c = 0; c < cols; c++) {
      final s = c * rowsPerCol;
      final e = (s + rowsPerCol) > n ? n : (s + rowsPerCol);
      if (s < n) listCols.add(listColumn(s, e));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        header('$brand • ${g.name} • Sınıf Özeti'),
        pw.SizedBox(height: 8),
        _banner('${g.name} — Sınıf Listesi', 'Sınıf listesi ve ders bazlı genel görünüm', bold),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            _kpi('Öğrenci', '$n', bold),
            _kpi('Sınıf Ort. (OdakScore)', g.avgScore.toStringAsFixed(1), bold),
            _kpi('En Yüksek', maxScore.toStringAsFixed(1), bold),
            _kpi('En Düşük', minScore.toStringAsFixed(1), bold),
            _kpi('Riskli', '${risky.length}', bold, color: PdfColors.red700),
          ],
        ),
        _h('Sınıf Listesi', bold, top: 6),
        pw.SizedBox(
          height: listH,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: listCols,
          ),
        ),
        pw.Text(
          '(!) ${a.riskRuleText} kalan riskli öğrenci.',
          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
        ),
        _h('Derslere Genel Bakış', bold, top: 6),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(font: bold, fontSize: 8, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: _teal),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2.5),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.center,
            2: pw.Alignment.center,
            3: pw.Alignment.center,
            4: pw.Alignment.center,
          },
          headers: ['Ders', 'Haftalık Saat', 'Sınıf Başarısı', 'Genel Başarı', 'Durum'],
          data: [
            for (final s in subjects)
              () {
                final r = a.subjectClassRate(g.id, s);
                final overall = a.subjectOverallRate(s);
                return [
                  s,
                  (a.lessonHours[s] ?? 0) > 0 ? '${a.lessonHours[s]}' : '—',
                  '%${(r * 100).round()}',
                  '%${(overall * 100).round()}',
                  _level(r),
                ];
              }(),
          ],
        ),
        pw.Spacer(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '$brand • Kural tabanlı sınav analizi',
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey500),
            ),
            pw.Text(
              'Rapor tarihi: $dateStr',
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
            ),
          ],
        ),
      ],
    );
  }

  // ───────────────────────── Ders bölümü (yeni sayfa) ─────────────────────────

  static List<pw.Widget> _subjectSection(
    OdakClassGroup g,
    OdakAnalyzer a,
    String subject,
    pw.Font bold,
  ) {
    final weak = a.getWeakOutcomes(g.id, top: 12, subject: subject);
    final empties = a.getMostEmptyQuestions(g.id, subject: subject);
    final dist = a.getMostFallenDistractor(g.id, subject: subject);
    final risky = a.getSubjectWarnings(g.id, subject);
    final riskyNames = risky.map((r) => r.name).toSet();
    final plan = a.buildSubjectPlan(g.id, subject);
    final rate = a.subjectClassRate(g.id, subject);
    final overall = a.subjectOverallRate(subject);
    final t = a.subjectTotals(g.id, subject);
    final hours = a.lessonHours[subject] ?? 0;
    final qs = a.questionStats(g.id, subject);
    final rows = a.subjectStudentRows(g.id, subject);
    final byClass = a.subjectRatesByClass(subject);
    final students = g.students.length;
    final avgNet = students == 0 ? 0.0 : t.net / students;
    final diff = ((rate - overall) * 100).round();

    final rankedClasses = byClass.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    final classPos = rankedClasses.indexWhere((e) => e.key == g.id) + 1;

    String outcomeOf(String o) => o.isNotEmpty && o != '-' ? o : 'Kazanım tanımsız';

    return [
      pw.SizedBox(height: 10),
      _banner('$subject Raporu', hours > 0 ? '${g.name} • haftada $hours saat • $students öğrenci' : '${g.name} • $students öğrenci', bold),
      pw.SizedBox(height: 10),
      pw.Row(
        children: [
          _kpi('Sınıf Başarısı', '%${(rate * 100).round()}', bold),
          _kpi('Genel (Tüm Sınıflar)', '%${(overall * 100).round()}', bold),
          _kpi('Fark', '${diff >= 0 ? '+' : ''}$diff puan', bold,
              color: diff >= 0 ? PdfColors.green700 : PdfColors.red700),
          _kpi('Sınıf Sırası', '$classPos/${byClass.length}', bold),
          _kpi('Ort. Net', avgNet.toStringAsFixed(1), bold),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Row(
        children: [
          _kpi('Toplam Doğru', '${t.correct}', bold, color: PdfColors.green700),
          _kpi('Toplam Yanlış', '${t.wrong}', bold, color: PdfColors.red700),
          _kpi('Toplam Boş', '${t.empty}', bold, color: PdfColors.orange800),
          _kpi('Riskli Öğrenci', '${risky.length}', bold, color: PdfColors.red700),
          _kpi('Durum', _level(rate), bold),
        ],
      ),

      _h('Sınıfların Karşılaştırması ($subject başarısı)', bold),
      for (final e in rankedClasses)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Row(
            children: [
              pw.SizedBox(
                width: 60,
                child: pw.Text(
                  'Sınıf ${a.groupLabel(e.key)}',
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 9,
                    color: e.key == g.id ? _tealDark : PdfColors.grey800,
                  ),
                ),
              ),
              pw.Expanded(
                child: _bar(e.value, highlight: e.key == g.id),
              ),
              pw.SizedBox(
                width: 36,
                child: pw.Text(
                  '%${(e.value * 100).round()}',
                  textAlign: pw.TextAlign.right,
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
            ],
          ),
        ),

      _h('Soru Bazlı Analiz (tüm sorular)', bold),
      if (qs.isEmpty)
        _p('Soru verisi bulunamadı.')
      else
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(font: bold, fontSize: 8, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: _teal),
          cellStyle: const pw.TextStyle(fontSize: 8),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          cellAlignments: {
            0: pw.Alignment.center,
            2: pw.Alignment.center,
            3: pw.Alignment.center,
            4: pw.Alignment.center,
            5: pw.Alignment.center,
            6: pw.Alignment.center,
          },
          columnWidths: {
            0: const pw.FixedColumnWidth(24),
            1: const pw.FlexColumnWidth(5),
            2: const pw.FixedColumnWidth(36),
            3: const pw.FixedColumnWidth(36),
            4: const pw.FixedColumnWidth(36),
            5: const pw.FixedColumnWidth(34),
            6: const pw.FixedColumnWidth(58),
          },
          headers: ['No', 'Kazanım', 'Doğru', 'Yanlış', 'Boş', 'Cevap', 'En çok yanlış'],
          data: [
            for (final q in qs)
              [
                '${q.questionNo}',
                q.outcome.isEmpty ? '—' : q.outcome,
                '%${(q.correctRate * 100).round()}',
                '%${(q.wrongRate * 100).round()}',
                '%${(q.emptyRate * 100).round()}',
                q.correctOption.isEmpty ? '?' : q.correctOption,
                q.topWrongOption.isEmpty
                    ? '—'
                    : '${q.topWrongOption} (%${q.total == 0 ? 0 : (q.topWrongCount * 100 / q.total).round()})',
              ],
          ],
        ),

      _h('Kazanım Başarı Sıralaması (zayıftan güçlüye)', bold),
      if (weak.isEmpty)
        _p('Zayıf kazanım tespit edilemedi.')
      else
        for (final w in weak)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Text(w.label, style: const pw.TextStyle(fontSize: 9)),
                    ),
                    pw.Text(
                      '%${(w.successRate * 100).round()}  (${w.questionCount} soru)',
                      style: pw.TextStyle(font: bold, fontSize: 9),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
                _bar(w.successRate),
              ],
            ),
          ),

      _h('En Çok Boş Bırakılan 3 Soru', bold),
      if (empties.isEmpty)
        _p('Boş bırakılan soru yok.')
      else
        for (final e in empties)
          _p('• ${e.questionNo}. soru — %${(e.ratio * 100).round()} boş '
              '(${e.emptyCount}/${e.total}) • ${outcomeOf(e.outcome)}'),

      _h('Çeldirici Analizi', bold),
      if (dist.isEmpty)
        _p('Sınıfın %40\'ından fazlasının aynı yanlış şıkka düştüğü soru yok.')
      else
        for (final d in dist)
          _p('• ${d.questionNo}. soru — ${d.option} şıkkı ${d.count}/${d.total} öğrenci '
              '(%${(d.ratio * 100).round()}) tarafından işaretlendi; doğru: '
              '${d.correctOption.isEmpty ? '?' : d.correctOption} (${d.correctCount} kişi). '
              '${outcomeOf(d.outcome)}'),

      _h('Öğrenci Bazlı $subject Sonuçları', bold),
      pw.TableHelper.fromTextArray(
        headerStyle: pw.TextStyle(font: bold, fontSize: 8.5, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: _teal),
        cellStyle: const pw.TextStyle(fontSize: 8.5),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        cellAlignments: {
          0: pw.Alignment.center,
          2: pw.Alignment.center,
          3: pw.Alignment.center,
          4: pw.Alignment.center,
          5: pw.Alignment.center,
          6: pw.Alignment.center,
        },
        columnWidths: {
          0: const pw.FixedColumnWidth(26),
          1: const pw.FlexColumnWidth(4),
          2: const pw.FixedColumnWidth(36),
          3: const pw.FixedColumnWidth(36),
          4: const pw.FixedColumnWidth(30),
          5: const pw.FixedColumnWidth(36),
          6: const pw.FixedColumnWidth(44),
        },
        headers: ['Sıra', 'Öğrenci', 'Doğru', 'Yanlış', 'Boş', 'Net', 'Başarı'],
        data: [
          for (var i = 0; i < rows.length; i++)
            [
              '${i + 1}',
              '${rows[i].name}${riskyNames.contains(rows[i].name) ? '  (!)' : ''}',
              '${rows[i].stat.correct}',
              '${rows[i].stat.wrong}',
              '${rows[i].stat.empty}',
              rows[i].stat.net.toStringAsFixed(2),
              '%${(rows[i].stat.successRate * 100).round()}',
            ],
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        '(!) işareti: $subject başarısı ${a.riskRuleText} kalan öğrenci.',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),

      _h('Riskli Öğrenciler ($subject)', bold),
      if (risky.isEmpty)
        _p('Ders başarısı ${a.riskRuleText} kalan öğrenci yok.')
      else
        for (final r in risky)
          _p('• ${r.name} — %${(r.rate * 100).round()} '
              '(sınıf %${(r.classRate * 100).round()}, -%${r.gapPercent.round()})'),

      _h('Öğretmen İçin Değerlendirme', bold),
      for (final line in _teacherNotes(
        subject: subject,
        rate: rate,
        overall: overall,
        weak: weak,
        empties: empties,
        dist: dist,
        riskyCount: risky.length,
        students: students,
        hours: hours,
      ))
        _p('• $line'),

      if (a.showActionPlan) ...[
        _h('Haftalık Aksiyon Planı', bold),
        for (final s in plan.summary) _p('• $s'),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(font: bold, fontSize: 8.5, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey700),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          columnWidths: {
            0: const pw.FixedColumnWidth(34),
            1: const pw.FlexColumnWidth(),
          },
          headers: ['Hafta', 'Plan'],
          data: [
            for (final w in plan.weeks) ['H${w.week}', w.detail],
          ],
        ),
      ],
    ];
  }

  /// Kural tabanlı, sabit metinli öğretmen değerlendirmesi.
  static List<String> _teacherNotes({
    required String subject,
    required double rate,
    required double overall,
    required List<OdakWeakOutcome> weak,
    required List<OdakEmptyQuestion> empties,
    required List<OdakDistractorFinding> dist,
    required int riskyCount,
    required int students,
    required int hours,
  }) {
    final notes = <String>[];
    final pct = (rate * 100).round();
    if (rate < 0.4) {
      notes.add('$subject başarısı %$pct ile kritik düzeyde. İlk haftalar temel kavram '
          've ön bilgi eksiklerinin kapatılmasına ayrılmalı.');
    } else if (rate < 0.6) {
      notes.add('$subject başarısı %$pct ile gelişmeye açık. Zayıf kazanımlarda '
          'konu tekrarı ve bol örnek çözümü önerilir.');
    } else if (rate < 0.75) {
      notes.add('$subject başarısı %$pct ile orta düzeyde. Zayıf kazanımları '
          'hedefleyen kısa tekrar ve karma testler yeterli olur.');
    } else {
      notes.add('$subject başarısı %$pct ile iyi düzeyde. Üst düzey soru tipleri ve '
          'zaman yönetimi çalışmalarına ağırlık verilebilir.');
    }
    if (rate < overall) {
      notes.add('Sınıf, tüm sınıfların ortalamasının '
          '${((overall - rate) * 100).round()} puan altında; ek ders saati veya '
          'ödev desteği değerlendirilmeli.');
    } else if (rate > overall) {
      notes.add('Sınıf, tüm sınıfların ortalamasının '
          '${((rate - overall) * 100).round()} puan üzerinde; mevcut yöntem korunabilir.');
    }
    if (weak.isNotEmpty) {
      notes.add('Öncelikli kazanımlar: ${weak.take(3).map((w) => w.label).join('; ')}.');
    }
    if (empties.isNotEmpty) {
      notes.add('Boş bırakma yüksek (ör. ${empties.first.questionNo}. soruda '
          '%${(empties.first.ratio * 100).round()}): "tahmin ve eleme" tekniği ve '
          'süre yönetimi çalışılmalı.');
    }
    if (dist.isNotEmpty) {
      notes.add('${dist.length} soruda belirgin çeldirici tuzağı var; bu sorular tahtada '
          'şık şık tartışılarak çözülmeli.');
    }
    if (riskyCount > 0) {
      notes.add('$riskyCount öğrenci ders ortalamasının belirgin altında: birebir geri '
          'bildirim, ek çalışma kâğıdı ve veli bilgilendirmesi planlanmalı.');
    }
    if (hours > 0 && students > 0) {
      notes.add('Haftalık $hours saatlik süre, kazanım sırasına göre bölünmeli; '
          'son hafta genel tekrar ve mini deneme için ayrılmalı.');
    }
    return notes;
  }

  // ───────────────────────── Ortak parçalar ─────────────────────────

  /// Türkçe alfabe sırasına uygun karşılaştırma anahtarı.
  static String _trKey(String s) {
    const map = {
      'ç': 'c{', 'ğ': 'g{', 'ı': 'h{', 'ö': 'o{', 'ş': 's{', 'ü': 'u{',
    };
    final lower = s
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .toLowerCase();
    final b = StringBuffer();
    for (final ch in lower.split('')) {
      b.write(map[ch] ?? ch);
    }
    return b.toString();
  }

  /// KAPI LİSTESİ: her sınıf için tek sayfa, yalnızca numaralı isimler
  /// (alfabetik). Puan, yüzde veya sıralama içermez.
  static Future<Uint8List> buildDoorList({
    required List<OdakClassGroup> groups,
    required String examName,
    String? schoolName,
    Set<String> classIds = const {},
    String brand = 'ODAK-64',
  }) async {
    final font = await PdfGoogleFonts.robotoRegular();
    final bold = await PdfGoogleFonts.robotoBold();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: bold),
      title: 'Kapı Listesi',
    );
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    final selected =
        groups.where((g) => classIds.isEmpty || classIds.contains(g.id)).toList();

    for (final g in selected) {
      final names = g.students.map((s) => s.student.name.trim()).toList()
        ..sort((a, b) => _trKey(a).compareTo(_trKey(b)));
      final n = names.length;
      final cols = n <= 24 ? 1 : (n <= 48 ? 2 : 3);
      final rowsPerCol = n == 0 ? 1 : (n / cols).ceil();
      const listH = 600.0;
      final rowH = (listH / rowsPerCol).clamp(10.0, 28.0);
      final fs = (rowH * 0.5).clamp(7.0, 15.0);

      pw.Widget row(int i) => pw.Container(
            height: rowH,
            margin: const pw.EdgeInsets.only(bottom: 0),
            decoration: pw.BoxDecoration(
              color: i.isEven ? PdfColors.teal50 : PdfColors.white,
              border: const pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.4),
              ),
            ),
            child: pw.Row(
              children: [
                pw.SizedBox(
                  width: 30,
                  child: pw.Center(
                    child: pw.Text(
                      '${i + 1}',
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: fs,
                        color: PdfColors.teal800,
                      ),
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    names[i],
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(fontSize: fs),
                  ),
                ),
              ],
            ),
          );

      final columns = <pw.Widget>[];
      for (var c = 0; c < cols; c++) {
        final s = c * rowsPerCol;
        final e = (s + rowsPerCol) > n ? n : (s + rowsPerCol);
        if (s >= n) break;
        columns.add(
          pw.Expanded(
            child: pw.Container(
              margin: const pw.EdgeInsets.symmetric(horizontal: 4),
              child: pw.Column(children: [for (var i = s; i < e; i++) row(i)]),
            ),
          ),
        );
      }

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (c) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                decoration: pw.BoxDecoration(
                  gradient: const pw.LinearGradient(
                    colors: [PdfColors.teal700, PdfColors.cyan800, PdfColors.blue900],
                  ),
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      g.name,
                      style: pw.TextStyle(font: bold, fontSize: 30, color: PdfColors.white),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Sınıf Kapı Listesi • $n öğrenci',
                      style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey200),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              pw.SizedBox(
                height: listH + 10,
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: columns,
                ),
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    [
                      if (schoolName != null && schoolName.isNotEmpty) schoolName,
                      if (examName.isNotEmpty) examName,
                    ].join(' • '),
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    '$brand • $dateStr',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }

  static String _level(double r) {
    if (r < 0.4) return 'Kritik';
    if (r < 0.6) return 'Gelişmeli';
    if (r < 0.75) return 'Orta';
    return 'İyi';
  }

  static pw.Widget _banner(String title, String sub, pw.Font bold) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: pw.BoxDecoration(
          gradient: const pw.LinearGradient(
            colors: [PdfColors.teal700, PdfColors.cyan800, PdfColors.blue900],
          ),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(font: bold, fontSize: 15, color: PdfColors.white),
            ),
            pw.Text(
              sub,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey200),
            ),
          ],
        ),
      );

  static pw.Widget _kpi(
    String label,
    String value,
    pw.Font bold, {
    PdfColor color = _tealDark,
  }) =>
      pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          ),
          child: pw.Column(
            children: [
              pw.Text(
                value,
                style: pw.TextStyle(font: bold, fontSize: 14, color: color),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                label,
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
      );

  /// Basit yatay ilerleme çubuğu (0..1).
  static pw.Widget _bar(double v, {bool highlight = false}) {
    final value = v.clamp(0.0, 1.0);
    final color = value < 0.4
        ? PdfColors.red600
        : (value < 0.6 ? PdfColors.orange600 : PdfColors.green600);
    return pw.LayoutBuilder(
      builder: (ctx, c) {
        final w = c?.maxWidth ?? 200;
        return pw.Stack(
          children: [
            pw.Container(
              height: 7,
              width: w,
              decoration: pw.BoxDecoration(
                color: PdfColors.grey200,
                borderRadius: pw.BorderRadius.circular(4),
              ),
            ),
            pw.Container(
              height: 7,
              width: w * value,
              decoration: pw.BoxDecoration(
                color: highlight ? _teal : color,
                borderRadius: pw.BorderRadius.circular(4),
              ),
            ),
          ],
        );
      },
    );
  }

  static pw.Widget _h(String text, pw.Font bold, {double top = 14}) => pw.Padding(
        padding: pw.EdgeInsets.only(top: top, bottom: 5),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              text,
              style: pw.TextStyle(font: bold, fontSize: 11.5, color: PdfColors.teal800),
            ),
            pw.Container(height: 1, width: 40, color: _teal),
          ],
        ),
      );

  static pw.Widget _p(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.5)),
      );
}
