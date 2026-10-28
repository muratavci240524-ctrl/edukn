import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/assessment/assessment_action_plan_model.dart';
import '../models/assessment/trial_exam_model.dart';
import '../models/school/dynamic_course_group_model.dart';
import 'course_track_resolver.dart';
import 'user_permission_service.dart';

/// Rapor kapsamı.
enum ActionPlanReportMode { full, classOnly, studentOnly }

/// Eylem planı için sınıf (şube) ve öğrenci bazlı takip raporu (PDF) üretir.
///
/// Rapor; planın kriterlerini (sınavlar, baraj yüzdeleri), şube bazlı kazanım
/// eylem planlarını (problem kaynağı, eylem, durum, güncelleyen öğretmen) ve
/// öğrenci bazlı takibi (verilen görevler, veli bilgilendirmesi) içerir.
class ActionPlanReportPdfService {
  static const PdfColor _primary = PdfColor.fromInt(0xFF283593);
  static const PdfColor _primaryDark = PdfColor.fromInt(0xFF1A237E);
  static const PdfColor _primaryLight = PdfColor.fromInt(0xFFE8EAF6);
  static const PdfColor _grey = PdfColor.fromInt(0xFF6B7280);
  static const PdfColor _line = PdfColor.fromInt(0xFFE5E7EB);
  static const PdfColor _red = PdfColor.fromInt(0xFFC62828);
  static const PdfColor _redBg = PdfColor.fromInt(0xFFFDECEA);
  static const PdfColor _green = PdfColor.fromInt(0xFF2E7D32);
  static const PdfColor _greenBg = PdfColor.fromInt(0xFFE8F5E9);
  static const PdfColor _orange = PdfColor.fromInt(0xFFEF6C00);
  static const PdfColor _orangeBg = PdfColor.fromInt(0xFFFFF3E0);

  static bool _isEnglishLesson(String normLesson) {
    final s = normLesson.toLowerCase();
    return s.contains('ingilizce') || s.contains('i̇ngilizce') || s.contains('english');
  }

  static Future<Uint8List> generate(AssessmentActionPlan plan,
      {ActionPlanReportMode mode = ActionPlanReportMode.full}) async {
    final tracks = await CourseTrackResolver.load(
      institutionId: plan.institutionId,
      schoolTypeId: plan.schoolTypeId,
    );
    final teachers = await _loadTeachers(plan.institutionId, plan.schoolTypeId, tracks);
    final comp = await _computeStudentInfoFromExams(plan, tracks);
    final font = await PdfGoogleFonts.openSansRegular();
    final bold = await PdfGoogleFonts.openSansBold();

    // Kullanıcının gerçek Ad Soyad bilgisini çözümle
    String creatorFullName = plan.creatorName;
    if (creatorFullName.isEmpty ||
        creatorFullName == 'Kullanıcı' ||
        creatorFullName == 'Sistem Yöneticisi' ||
        creatorFullName == 'anon') {
      creatorFullName = await UserPermissionService.resolveUserFullName(
        plan.createdBy,
        institutionId: plan.institutionId,
        fallback: '',
      );
    }
    if (creatorFullName.isEmpty || creatorFullName == 'Kullanıcı' || creatorFullName == 'Sistem Yöneticisi') {
      final curUser = FirebaseAuth.instance.currentUser;
      if (curUser != null) {
        creatorFullName = await UserPermissionService.resolveUserFullName(
          curUser.uid,
          institutionId: plan.institutionId,
          fallback: '',
        );
        if (creatorFullName.isEmpty) {
          final ud = await UserPermissionService.loadUserData();
          creatorFullName = (ud?['fullName'] ?? ud?['adminFullName'] ?? ud?['displayName'] ?? curUser.displayName ?? '').toString().trim();
        }
      }
    }
    if (creatorFullName.isEmpty || creatorFullName == 'Kullanıcı' || creatorFullName == 'Sistem Yöneticisi') {
      try {
        final sQuery = await FirebaseFirestore.instance
            .collection('schools')
            .where('institutionId', isEqualTo: plan.institutionId)
            .limit(1)
            .get();
        if (sQuery.docs.isNotEmpty) {
          final sData = sQuery.docs.first.data();
          creatorFullName = (sData['adminFullName'] ?? sData['schoolName'] ?? '').toString().trim();
        }
      } catch (_) {}
    }
    if (creatorFullName.isEmpty || creatorFullName == 'Kullanıcı' || creatorFullName == 'Sistem Yöneticisi') {
      creatorFullName = 'Yönetici';
    } else if (plan.creatorName.isEmpty || plan.creatorName == 'Kullanıcı' || plan.creatorName == 'Sistem Yöneticisi') {
      FirebaseFirestore.instance
          .collection('assessment_action_plans')
          .doc(plan.id)
          .update({'creatorName': creatorFullName})
          .catchError((_) {});
    }

    final data = _ReportData(
      plan,
      teachers,
      comp.studentInfo,
      comp.studentRealBranches,
      tracks,
      creatorFullName,
      comp.outcomeStats,
      comp.allStudentRecords,
    );

    final doc = pw.Document(title: plan.title, author: 'eduKN');
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 36),
          theme: pw.ThemeData.withFont(base: font, bold: bold),
        ),
        header: (ctx) => ctx.pageNumber == 1 ? pw.SizedBox() : _pageHeader(plan),
        footer: (ctx) => _footer(ctx),
        build: (ctx) => [
          ..._cover(plan, data, mode),
          ..._branchSections(plan, data, mode),
        ],
      ),
    );
    return doc.save();
  }

  /// Sınav sonuçlarından kazanım istatistiklerini (outcomeStats), riskli öğrencileri (studentInfo)
  /// ve öğrencilerin gerçek normal şubelerini hesaplar.
  static Future<_ExamStudentComputation> _computeStudentInfoFromExams(
    AssessmentActionPlan plan,
    CourseTrackResolver tracks,
  ) async {
    final Map<String, dynamic> out = {};
    final Map<String, String> realBranches = {};
    final Map<String, Map<String, Map<String, Map<String, dynamic>>>> branchStats = {};
    try {
      // branch -> subject -> studentKey -> {correct,total,net,netTotal,name,no}
      final Map<String, Map<String, Map<String, Map<String, dynamic>>>> agg = {};
      for (final id in plan.selectedExamIds) {
        final doc = await FirebaseFirestore.instance.collection('trial_exams').doc(id).get();
        if (!doc.exists) continue;
        final exam = TrialExam.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        if (exam.resultsJson == null || exam.resultsJson!.isEmpty) continue;
        final List<dynamic> results = jsonDecode(exam.resultsJson!);
        for (final r in results) {
          if (r is! Map) continue;
          final rawBranch = (r['branch'] ?? r['className'] ?? 'Belirsiz').toString().trim();
          final no = (r['studentNo'] ?? r['studentNumber'] ?? r['number'] ?? '').toString().trim();
          final name = (r['name'] ?? r['studentName'] ?? '').toString().trim();
          final sid = (r['systemStudentId'] ?? r['studentId'] ?? '').toString().trim();
          final tc = (r['tcNo'] ?? '').toString().trim();
          if (rawBranch.isNotEmpty && rawBranch != 'Belirsiz') {
            if (no.isNotEmpty) realBranches[no] = rawBranch;
            if (name.isNotEmpty) realBranches[name.toLowerCase()] = rawBranch;
            if (sid.isNotEmpty) realBranches[sid] = rawBranch;
          }

          final subjects = r['subjects'];
          if (subjects is! Map) continue;
          subjects.forEach((subjNameRaw, subjData) {
            final subjName = subjNameRaw.toString();
            String booklet = (r['booklet'] ?? r['kitapçık'] ?? 'A').toString().toUpperCase().trim();
            if (booklet.isEmpty) booklet = 'A';
            if (!exam.outcomes.containsKey(booklet) && exam.outcomes.isNotEmpty) {
              booklet = exam.outcomes.keys.first;
            }
            String norm = subjName;
            final outcomeSearchMap = exam.outcomes[booklet] ??
                (exam.outcomes.isNotEmpty ? exam.outcomes.values.first : null);
            if (outcomeSearchMap != null && !outcomeSearchMap.containsKey(subjName)) {
              final found = outcomeSearchMap.keys.firstWhere(
                (k) =>
                    k.toLowerCase().trim() == subjName.toLowerCase().trim() ||
                    k.toLowerCase().contains(subjName.toLowerCase().trim()) ||
                    subjName.toLowerCase().trim().contains(k.toLowerCase().trim()),
                orElse: () => '',
              );
              if (found.isNotEmpty) norm = found;
            }

            // Çok oturumlu sınavlarda ders bazlı kitapçığı correctAnswers üzerinden eşleştir
            dynamic studentCorrectRaw;
            if (subjData is Map) {
              studentCorrectRaw = subjData['correctAnswers'] ?? subjData['cevapAnahtari'];
            }
            if (studentCorrectRaw == null && r['correctAnswers'] is Map) {
              studentCorrectRaw = r['correctAnswers'][subjName] ?? r['correctAnswers'][norm];
            }
            if (studentCorrectRaw != null) {
              final targetStr = studentCorrectRaw.toString().toUpperCase().trim();
              if (targetStr.isNotEmpty && exam.answerKeys.isNotEmpty) {
                final currentKeyStr = (exam.answerKeys[booklet]?[norm] ?? '').toString().toUpperCase().trim();
                if (currentKeyStr != targetStr) {
                  for (final bk in exam.answerKeys.keys) {
                    final bkKeyStr = (exam.answerKeys[bk]?[norm] ?? '').toString().toUpperCase().trim();
                    if (bkKeyStr == targetStr && exam.outcomes.containsKey(bk)) {
                      booklet = bk;
                      break;
                    }
                  }
                }
              }
            }

            final examOutcomes = exam.outcomes[booklet]?[norm];
            final examAnswers = exam.answerKeys[booklet]?[norm];
            if (examOutcomes == null || examAnswers == null) return;

            dynamic studentRaw;
            if (subjData is Map) {
              studentRaw = subjData['answers'] ?? subjData['cevaplar'] ?? subjData['cevap_anahtari'];
            }
            if (studentRaw == null && r['answers'] is Map) {
              studentRaw = r['answers'][subjName] ?? r['answers'][norm];
            }
            if (studentRaw == null && r['cevaplar'] is Map) {
              studentRaw = r['cevaplar'][subjName] ?? r['cevaplar'][norm];
            }
            if (studentRaw == null && (subjData is String || subjData is List)) studentRaw = subjData;
            if (studentRaw == null) return;

            final len = examOutcomes.length;
            final sAns = _parseAnswers(studentRaw, len);
            final cAns = _parseAnswers(studentCorrectRaw ?? examAnswers, len);

            String evalBranch = rawBranch;
            final String rClassLevel = (r['classLevel'] ?? exam.classLevel).toString();
            if (tracks.hasTrackForBranchOrLevel(norm, rawBranch: rawBranch, classLevel: rClassLevel)) {
              final slot = tracks.slotForStudent(
                studentId: sid,
                studentNo: no,
                tcNo: tc,
                studentName: name,
                subject: norm,
                rawBranch: rawBranch,
                classLevel: rClassLevel,
              );
              if (slot == null) return;
              final sub = slot.subGroupName.replaceAll(RegExp(r'\s+'), ' ').trim();
              evalBranch = sub.endsWith(' Kur') ? sub.substring(0, sub.length - 4).trim() : sub;
            }
            if (evalBranch.isEmpty) return;

            branchStats.putIfAbsent(evalBranch, () => {});
            branchStats[evalBranch]!.putIfAbsent(norm, () => {});

            final studentKey = (no.isNotEmpty ? no : (name.isNotEmpty ? name : 'İsimsiz')).toString();
            final entry = agg
                .putIfAbsent(evalBranch, () => {})
                .putIfAbsent(norm, () => {})
                .putIfAbsent(studentKey, () => {
                      'correct': 0,
                      'total': 0,
                      'net': 0.0,
                      'netTotal': 0,
                      'name': (r['name'] ?? r['studentName'] ?? 'İsimsiz').toString(),
                      'no': (r['studentNo'] ?? r['studentNumber'] ?? r['number'] ?? '').toString(),
                    });
            int localCorrect = 0;
            int localTotal = 0;
            for (int i = 0; i < len; i++) {
              String outcome = examOutcomes[i].toString().trim();
              if (outcome.isEmpty || outcome == 'null') outcome = 'Genel';
              final oMap = branchStats[evalBranch]![norm]!.putIfAbsent(outcome, () => {
                'correct': 0,
                'total': 0,
                'students': <Map<String, dynamic>>[],
              });
              oMap['total'] = (oMap['total'] as int) + 1;
              entry['total'] = (entry['total'] as int) + 1;
              localTotal++;
              final isCorrect = i < sAns.length &&
                  i < cAns.length &&
                  sAns[i].trim().isNotEmpty &&
                  sAns[i].trim() == cAns[i].trim();
              if (isCorrect) {
                oMap['correct'] = (oMap['correct'] as int) + 1;
                entry['correct'] = (entry['correct'] as int) + 1;
                localCorrect++;
              } else {
                (oMap['students'] as List).add({
                  'name': (r['name'] ?? r['studentName'] ?? 'İsimsiz').toString(),
                  'no': (r['studentNo'] ?? r['studentNumber'] ?? r['number'] ?? '').toString(),
                  'isWrong': i < sAns.length && sAns[i].trim().isNotEmpty,
                  'isEmpty': i >= sAns.length || sAns[i].trim().isEmpty,
                });
              }
            }
            if (subjData is Map && subjData['net'] != null) {
              final c = (subjData['correct'] ?? 0) as num;
              final w = (subjData['wrong'] ?? 0) as num;
              final e = (subjData['empty'] ?? 0) as num;
              entry['net'] = (entry['net'] as num).toDouble() + (subjData['net'] as num).toDouble();
              entry['netTotal'] = (entry['netTotal'] as num).toInt() + (c + w + e).toInt();
            } else {
              entry['net'] = (entry['net'] as num).toDouble() + localCorrect;
              entry['netTotal'] = (entry['netTotal'] as num).toInt() + localTotal;
            }
          });
        }
      }
      double studentRate(Map e) {
        final netTotal = (e['netTotal'] ?? 0) as num;
        if (netTotal <= 0) return 0.0;
        final net = (e['net'] ?? 0) as num;
        return ((net / netTotal).clamp(0.0, 1.0).toDouble()) * 100.0;
      }

      final Map<String, Map<String, List<Map<String, dynamic>>>> allRecords = {};
      agg.forEach((branch, subjects) {
        subjects.forEach((subject, students) {
          if (students.isEmpty) return;
          double sum = 0.0;
          int count = 0;
          students.forEach((_, e) {
            sum += studentRate(e);
            count++;
          });
          if (count == 0) return;
          final avg = sum / count;
          final cutoff = avg > 0 ? avg * 0.8 : -1.0;
          final list = allRecords.putIfAbsent(branch, () => {}).putIfAbsent(subject, () => []);
          students.forEach((key, e) {
            final s = studentRate(e);
            final rounded = double.parse(s.toStringAsFixed(1));
            final rec = <String, dynamic>{
              'name': e['name'],
              'no': e['no'],
              'branch': branch,
              'subject': subject,
              'success': rounded,
            };
            list.add(rec);
            if (cutoff >= 0 && s <= cutoff) {
              out['${branch}_${subject}_$key'] = rec;
            }
          });
        });
      });
      // plan.studentInfo içerisindeki normal şube bilgilerinden de faydalan
      plan.studentInfo.forEach((k, v) {
        if (v is Map) {
          final b = (v['branch'] ?? '').toString().trim();
          final no = (v['no'] ?? '').toString().trim();
          final name = (v['name'] ?? '').toString().trim();
          final bNorm = b.toLowerCase();
          final isKur = bNorm.contains('kur') || bNorm.contains('maincourse') || bNorm.contains('track');
          if (b.isNotEmpty && !isKur) {
            if (no.isNotEmpty) realBranches.putIfAbsent(no, () => b);
            if (name.isNotEmpty) realBranches.putIfAbsent(name.toLowerCase(), () => b);
          }
        }
      });
      return _ExamStudentComputation(out, realBranches, branchStats, allRecords);
    } catch (_) {}
    return _ExamStudentComputation(out, realBranches, branchStats, const {});
  }

  static List<String> _parseAnswers(dynamic raw, int length) {
    List<String> res = [];
    if (raw is List) {
      res = raw.map((e) => e.toString().toUpperCase().trim()).toList();
    } else {
      final s = raw.toString().toUpperCase().trim();
      if (s.contains(' ') || s.contains(',') || s.contains('|')) {
        res = s.split(RegExp(r'[\s,|]')).where((e) => e.isNotEmpty).toList();
        if (res.length != length) {
          res = s.replaceAll(RegExp(r'[,|.]'), '').split('');
          if (res.length > length) res = res.where((e) => e != ' ').toList();
        }
      } else {
        res = s.split('');
      }
    }
    if (res.length > length) {
      res = res.sublist(0, length);
    } else if (res.length < length) {
      res.addAll(List.filled(length - res.length, ' '));
    }
    return res.map((e) => e.isEmpty ? ' ' : e).toList();
  }

  // ─────────────────────────── DATA ───────────────────────────

  static Future<Map<String, Map<String, String>>> _loadTeachers(
    String institutionId,
    String schoolTypeId,
    CourseTrackResolver tracks,
  ) async {
    // className -> lessonName -> teachers ; '*' -> lessonName -> teachers (fallback)
    final Map<String, Map<String, String>> result = {};
    try {
      final snap = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: institutionId)
          .get();
      // İlk geçiş: schoolTypeId eşleşen aktif kayıtlar (veya schoolTypeId boşsa tüm aktifler)
      for (final d in snap.docs) {
        final m = d.data();
        if (m['isActive'] == false) continue;
        if (schoolTypeId.isNotEmpty) {
          final stId = (m['schoolTypeId'] ?? '').toString();
          if (stId.isNotEmpty && stId != schoolTypeId) continue;
        }
        final cls = (m['className'] ?? '').toString().trim();
        final lesson = (m['lessonName'] ?? '').toString().trim();
        final names = List<dynamic>.from(m['teacherNames'] ?? []);
        if (lesson.isEmpty || names.isEmpty) continue;
        final t = names.join(', ');
        if (cls.isNotEmpty) result.putIfAbsent(cls, () => {})[lesson] = t;
        result.putIfAbsent('*', () => {}).putIfAbsent(lesson, () => t);
      }
      // İkinci geçiş: farklı schoolTypeId altında kalmış şube ders atamalarını da eksik kalan yerlere tamamla
      if (schoolTypeId.isNotEmpty) {
        for (final d in snap.docs) {
          final m = d.data();
          if (m['isActive'] == false) continue;
          final cls = (m['className'] ?? '').toString().trim();
          final lesson = (m['lessonName'] ?? '').toString().trim();
          final names = List<dynamic>.from(m['teacherNames'] ?? []);
          if (lesson.isEmpty || names.isEmpty) continue;
          final t = names.join(', ');
          if (cls.isNotEmpty) result.putIfAbsent(cls, () => {}).putIfAbsent(lesson, () => t);
          result.putIfAbsent('*', () => {}).putIfAbsent(lesson, () => t);
        }
      }
    } catch (_) {}

    // Kurs / Kur öğretmenlerini ekle
    for (final g in tracks.groups) {
      for (final sg in g.subGroups) {
        if (sg.teacherNames.isNotEmpty) {
          final t = sg.teacherNames.join(', ');
          final shortName = sg.name.replaceAll(RegExp(r'\s+'), ' ').trim();
          result.putIfAbsent(shortName, () => {})[g.lessonName] = t;
          result.putIfAbsent(sg.name, () => {})[g.lessonName] = t;
          final slotLabel = '${g.name.isNotEmpty ? '${g.name} • ' : ''}${sg.name}'.replaceAll('_', ' ');
          result.putIfAbsent(slotLabel, () => {})[g.lessonName] = t;
        }
      }
    }
    return result;
  }

  // ─────────────────────────── LAYOUT ───────────────────────────

  static pw.Widget _pageHeader(AssessmentActionPlan plan) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 1))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('eduKN', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _primary)),
          pw.Text(plan.title, style: const pw.TextStyle(fontSize: 8, color: _grey)),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context ctx) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Eylem Planı Takip Raporu  •  ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 7, color: _grey)),
          pw.Text('Sayfa ${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: _grey)),
        ],
      ),
    );
  }

  static List<pw.Widget> _cover(AssessmentActionPlan plan, _ReportData d, ActionPlanReportMode mode) {
    final thresholds = plan.subjectThresholds.entries.toList();
    return [
      pw.Container(
        padding: const pw.EdgeInsets.all(18),
        decoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(12),
          gradient: const pw.LinearGradient(colors: [_primaryDark, _primary]),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('EYLEM PLANI TAKİP RAPORU',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.indigo100, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2)),
            pw.SizedBox(height: 6),
            pw.Text(plan.title, style: pw.TextStyle(fontSize: 17, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Row(children: [
              _metaChip('Tarih', DateFormat('dd.MM.yyyy').format(plan.date)),
              pw.SizedBox(width: 14),
              _metaChip('Oluşturan', d.creatorFullName.isNotEmpty && d.creatorFullName != 'Sistem Yöneticisi' ? d.creatorFullName : (plan.creatorName.isNotEmpty && plan.creatorName != 'Kullanıcı' && plan.creatorName != 'Sistem Yöneticisi' ? plan.creatorName : 'Yönetici')),
              pw.SizedBox(width: 14),
              _metaChip('Sınıf Düzeyi', plan.classLevel),
            ]),
          ],
        ),
      ),
      pw.SizedBox(height: 14),
      pw.Row(children: [
        _statBox('Planlanan Eylem', '${d.plannedActions}', _primary, _primaryLight),
        pw.SizedBox(width: 8),
        _statBox('Tamamlanan', '${d.completedActions}', _green, _greenBg),
        pw.SizedBox(width: 8),
        _statBox('barajın Altındaki Öğrenci', '${d.trackedStudents}', _orange, _orangeBg),
        pw.SizedBox(width: 8),
        _statBox('Atanan Görev', '${d.totalTasks}', _primary, _primaryLight),
        pw.SizedBox(width: 8),
        _statBox('Veli Bilgilendirilen', '${d.notifiedStudents}/${d.trackedStudents}', _green, _greenBg),
      ]),
      pw.SizedBox(height: 14),
      _sectionTitle('Rapor Kriterleri'),
      pw.SizedBox(height: 6),
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Kapsanan Sınavlar', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _grey)),
          pw.SizedBox(height: 2),
          pw.Text(plan.selectedExamNames.isEmpty ? '-' : plan.selectedExamNames.join(', '), style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 8),
          pw.Text('Ders Bazlı Başarı Barajı (altındaki kazanım/öğrenci kritik sayılır)',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _grey)),
          pw.SizedBox(height: 4),
          pw.Wrap(
            spacing: 6,
            runSpacing: 4,
            children: thresholds
                .map((e) => pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: pw.BoxDecoration(color: _primaryLight, borderRadius: pw.BorderRadius.circular(10)),
                      child: pw.Text('${e.key}: %${e.value.round()}', style: const pw.TextStyle(fontSize: 8, color: _primaryDark)),
                    ))
                .toList(),
          ),
          if (plan.realizationNotes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('İzleme Notu', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _grey)),
            pw.SizedBox(height: 2),
            pw.Text(plan.realizationNotes, style: const pw.TextStyle(fontSize: 9)),
          ],
        ]),
      ),
      pw.SizedBox(height: 14),
      ..._coverNarrative(plan, d, mode),
    ];
  }

  static pw.Widget _para(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Text(t, style: const pw.TextStyle(fontSize: 8.5, lineSpacing: 2, color: PdfColors.grey800)),
      );

  static pw.Widget _bullet(String t, {PdfColor color = _primary}) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 3, right: 6),
            width: 4,
            height: 4,
            decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
          ),
          pw.Expanded(child: pw.Text(t, style: const pw.TextStyle(fontSize: 8.5, lineSpacing: 1.5, color: PdfColors.grey800))),
        ]),
      );

  static List<pw.Widget> _coverNarrative(AssessmentActionPlan plan, _ReportData d, ActionPlanReportMode mode) {
    final modeText = mode == ActionPlanReportMode.classOnly
        ? 'Bu rapor yalnızca sınıf (şube) bazlı kısmı içerir: her şube için ders ders kritik kazanımlar ve bunlara yapılan müdahaleler listelenir.'
        : mode == ActionPlanReportMode.studentOnly
            ? 'Bu rapor yalnızca öğrenci bazlı kısmı içerir: her şubede barajın altında kalan öğrenciler, bu öğrencilere verilen görevler ve veli bilgilendirme durumları gösterilir.'
            : 'Bu rapor hem sınıf (şube) bazlı hem de öğrenci bazlı bölümleri içerir. Her şube yeni bir sayfadan başlar; şubeler birbirine karışmaz.';

    final lowest = d.lowestOutcomes(5);
    final normalSummaries = d.normalBranches.map((b) => MapEntry(b, d.normalBranchSummary(b))).toList();
    final courseSummaries = d.courseBranches.map((b) => MapEntry(b, d.courseBranchSummary(b))).toList();

    return [
      _sectionTitle('Raporun Amacı'),
      pw.SizedBox(height: 6),
      _para('Bu belge, seçilen deneme sınavı sonuçlarına göre öğrenme eksikliklerinin tespit edilmesi, bu eksiklikler için '
          'alınan önlemlerin (eylem planlarının) belgelenmesi ve uygulama sürecinin izlenmesi amacıyla hazırlanmıştır. '
          'Sınav sonuçları kazanım bazında incelenmiş; belirlenen başarı barajının altında kalan kazanımlar ve öğrenciler "kritik" kabul edilmiştir.'),
      _para(modeText),
      pw.SizedBox(height: 8),
      _sectionTitle('Bu Eylem Planında Neler Yapıldı?'),
      pw.SizedBox(height: 6),
      _bullet('${plan.selectedExamNames.length} sınav kapsamında ${d.normalBranches.length} normal şube'
          '${d.courseBranches.isNotEmpty ? ' ve ${d.courseBranches.length} kurs/kur grubu' : ''} '
          'ile ${d.subjectCount} ders için sonuçlar kazanım bazında analiz edildi.'),
      _bullet('Başarı barajının altında kalan ${d.criticalOutcomeCount} kazanım kritik olarak belirlendi.', color: _red),
      _bullet('${d.problemDefined} kazanım için problem kaynağı belirlendi, ${d.plannedActions} kazanım için eylem planı girildi; ${d.completedActions} eylem tamamlandı.'),
      _bullet('${d.trackedStudents} öğrenci başarı barajının altında kaldı; bunlardan ${d.studentsWithTasks} öğrenciye toplam ${d.totalTasks} görev '
          '(soru çözümü, konu özeti, video, etüt vb.) atandı.', color: _orange),
      _bullet('${d.notifiedStudents} öğrenci için veli bilgilendirmesi yapıldı; ${d.trackedStudents - d.notifiedStudents} öğrenci için veli bilgilendirmesi henüz yapılmadı.', color: _green),
      pw.SizedBox(height: 8),

      // ── Tablo 1: Normal Şubeler Özeti (Başlık ve tablo birlikte yeni sayfaya geçer) ──
      pw.NewPage(freeSpace: (60.0 + normalSummaries.length * 22.0).clamp(140.0, 540.0)),
      _sectionTitle('Şube Özeti'),
      pw.SizedBox(height: 6),
      pw.Table(
        border: pw.TableBorder.all(color: _line, width: 0.6),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.4),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1),
          3: const pw.FlexColumnWidth(1),
          4: const pw.FlexColumnWidth(1),
          5: const pw.FlexColumnWidth(1),
          6: const pw.FlexColumnWidth(1),
        },
        children: [
          pw.TableRow(
            repeat: true,
            decoration: const pw.BoxDecoration(color: _primaryLight),
            children: [
              _cell('Şube', bold: true, color: _primaryDark),
              _cell('Kritik Kazanım', bold: true, color: _primaryDark, align: pw.TextAlign.center, size: 7),
              _cell('Eylem Girilen', bold: true, color: _primaryDark, align: pw.TextAlign.center, size: 7),
              _cell('Tamamlanan', bold: true, color: _primaryDark, align: pw.TextAlign.center, size: 7),
              _cell('Baraj Altı Öğrenci', bold: true, color: _primaryDark, align: pw.TextAlign.center, size: 7),
              _cell('Görev Atanan', bold: true, color: _primaryDark, align: pw.TextAlign.center, size: 7),
              _cell('Veli Bilgilendirilen', bold: true, color: _primaryDark, align: pw.TextAlign.center, size: 7),
            ],
          ),
          ...normalSummaries.map((e) => pw.TableRow(children: [
                _cell(e.key, bold: true),
                _cell('${e.value.critical}', align: pw.TextAlign.center, color: e.value.critical > 0 ? _red : _green, bold: true),
                _cell('${e.value.planned}', align: pw.TextAlign.center),
                _cell('${e.value.completed}', align: pw.TextAlign.center),
                _cell('${e.value.students}', align: pw.TextAlign.center),
                _cell('${e.value.withTasks}', align: pw.TextAlign.center),
                _cell('${e.value.notified}', align: pw.TextAlign.center),
              ])),
        ],
      ),

      // ── Tablo 2: Kurs Sınıfları / İngilizce Main Course Şube Özeti ──
      if (courseSummaries.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        pw.NewPage(freeSpace: (60.0 + courseSummaries.length * 22.0).clamp(140.0, 540.0)),
        _sectionTitle('${d.courseGroupTitle} Şube Özeti'),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: _line, width: 0.6),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.4),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1),
            4: const pw.FlexColumnWidth(1),
            5: const pw.FlexColumnWidth(1),
            6: const pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              repeat: true,
              decoration: const pw.BoxDecoration(color: _primaryLight),
              children: [
                _cell('Kur / Kurs Adı', bold: true, color: _primaryDark),
                _cell('Kritik Kazanım', bold: true, color: _primaryDark, align: pw.TextAlign.center, size: 7),
                _cell('Eylem Girilen', bold: true, color: _primaryDark, align: pw.TextAlign.center, size: 7),
                _cell('Tamamlanan', bold: true, color: _primaryDark, align: pw.TextAlign.center, size: 7),
                _cell('Baraj Altı Öğrenci', bold: true, color: _primaryDark, align: pw.TextAlign.center, size: 7),
                _cell('Görev Atanan', bold: true, color: _primaryDark, align: pw.TextAlign.center, size: 7),
                _cell('Veli Bilgilendirilen', bold: true, color: _primaryDark, align: pw.TextAlign.center, size: 7),
              ],
            ),
            ...courseSummaries.map((e) {
              final kurLabel = e.key.contains('•') ? e.key.split('•').last.trim() : e.key;
              return pw.TableRow(children: [
                _cell(kurLabel, bold: true),
                _cell('${e.value.critical}', align: pw.TextAlign.center, color: e.value.critical > 0 ? _red : _green, bold: true),
                _cell('${e.value.planned}', align: pw.TextAlign.center),
                _cell('${e.value.completed}', align: pw.TextAlign.center),
                _cell('${e.value.students}', align: pw.TextAlign.center),
                _cell('${e.value.withTasks}', align: pw.TextAlign.center),
                _cell('${e.value.notified}', align: pw.TextAlign.center),
              ]);
            }),
          ],
        ),
      ],

      if (lowest.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        pw.NewPage(freeSpace: (45.0 + lowest.length * 18.0).clamp(95.0, 260.0)),
        _sectionTitle('Dikkat Gerektiren En Düşük Başarılı Kazanımlar'),
        pw.SizedBox(height: 6),
        ...lowest.map((o) => _bullet('${o.branch} • ${o.subject}: ${o.outcome} (%${o.success.toStringAsFixed(0)})', color: _red)),
      ],
      pw.SizedBox(height: 10),
      pw.NewPage(freeSpace: 95),
      _sectionTitle('Raporu Nasıl Okumalı?'),
      pw.SizedBox(height: 6),
      _bullet('Başarı sütunu kırmızı ise kazanım/öğrenci barajın altındadır; yeşil ise yeterlidir.'),
      _bullet('Durum: "Belirlenmedi" henüz işlem yapılmadığını, "Problem Belirlendi" sorunun kaynağının bulunduğunu, '
          '"Uygulanıyor" eylem planının sürdüğünü, "Tamamlandı" eylemin bittiğini gösterir.'),
      _bullet('Güncelleyen sütunu, kaydı son giren/değiştiren kişidir. Eski kayıtlarda bu bilgi yoksa dersin öğretmeni yazılır.'),
    ];
  }

  static pw.Widget _metaChip(String label, String value) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 7, color: PdfColors.indigo100)),
          pw.Text(value, style: pw.TextStyle(fontSize: 9, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
        ],
      );

  static pw.Widget _statBox(String label, String value, PdfColor color, PdfColor bg) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 9, horizontal: 6),
          decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Column(children: [
            pw.Text(value, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: color)),
            pw.SizedBox(height: 2),
            pw.Text(label, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7, color: _grey)),
          ]),
        ),
      );

  static pw.Widget _sectionTitle(String t) => pw.Row(children: [
        pw.Container(width: 3, height: 12, color: _primary),
        pw.SizedBox(width: 6),
        pw.Text(t, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _primaryDark)),
      ]);

  static pw.Widget _cell(String t,
      {bool bold = false, PdfColor? color, double size = 8, pw.TextAlign align = pw.TextAlign.left, PdfColor? bg}) {
    return pw.Container(
      color: bg,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(t,
          textAlign: align,
          style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color)),
    );
  }

  static PdfColor _statusColor(String s) {
    switch (s) {
      case 'Tamamlandı':
        return _green;
      case 'Uygulanıyor':
        return _primary;
      case 'Eylem Planı Hazır':
        return PdfColors.blue700;
      case 'Problem Belirlendi':
        return _orange;
      default:
        return _grey;
    }
  }

  static List<pw.Widget> _branchSections(AssessmentActionPlan plan, _ReportData d, ActionPlanReportMode mode) {
    final List<pw.Widget> out = [];
    final showClass = mode != ActionPlanReportMode.studentOnly;
    final showStudent = mode != ActionPlanReportMode.classOnly;

    // ──────────────── 1. NORMAL ŞUBELER (İNGİLİZCE / KURS DERSLERİ ÇIKARILDI) ────────────────
    for (final branch in d.normalBranches) {
      final subjectRowsMap = <String, List<_OutcomeRow>>{};
      if (showClass) {
        for (final subject in d.normalSubjectsOf(branch)) {
          final rows = d.outcomeRows(branch, subject);
          if (rows.isNotEmpty) subjectRowsMap[subject] = rows;
        }
      }
      final students = showStudent ? d.normalStudentsOf(branch) : <_StudentReport>[];

      // Eylem planı / kritik kazanımı ve öğrencisi olmayan şubeyi rapora ekleme
      final hasClassContent = subjectRowsMap.isNotEmpty;
      final hasStudentContent = students.isNotEmpty;
      if (!hasClassContent && !hasStudentContent) {
        continue;
      }
      if (mode == ActionPlanReportMode.classOnly && !hasClassContent) {
        continue;
      }
      if (mode == ActionPlanReportMode.studentOnly && !hasStudentContent) {
        continue;
      }

      // ── 1. Sınıf bazlı kazanım eylem planları (SADECE NORMAL DERSLER) ──
      if (showClass && hasClassContent) {
        out.add(pw.NewPage());
        out.add(pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: pw.BoxDecoration(color: _primaryDark, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Text('$branch ŞUBESİ  •  SINIF RAPORU',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.white, letterSpacing: 0.6)),
        ));
        out.add(pw.SizedBox(height: 8));

        final entries = subjectRowsMap.entries.toList();
        for (int i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final subject = entry.key;
          final rows = entry.value;
          final teacher = d.teacher(branch, subject);

          if (i > 0) {
            // Tablo başlığı ve tablonun kendisi mevcut sayfaya sığmıyorsa başlıkla birlikte yeni sayfadan başlat
            final neededSpace = (65.0 + (rows.length * 42.0)).clamp(130.0, 540.0);
            out.add(pw.NewPage(freeSpace: neededSpace));
          }

          out.add(pw.Row(children: [
            pw.Text(subject, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _primary)),
            pw.SizedBox(width: 8),
            pw.Text('Öğretmen: $teacher', style: const pw.TextStyle(fontSize: 8, color: _grey)),
            pw.Spacer(),
            pw.Text('Baraj: %${(plan.subjectThresholds[subject] ?? 0).round()}', style: const pw.TextStyle(fontSize: 8, color: _grey)),
          ]));
          out.add(pw.SizedBox(height: 4));
          out.add(_buildOutcomeTable(rows, teacher, d.creatorFullName));
          out.add(pw.SizedBox(height: 10));
        }
      }

      // ── 2. Öğrenci bazlı takip (Şube bazlı rapordan öğrenci bazlı rapora geçerken yeni sayfaya geçilir) ──
      if (showStudent) {
        if (hasStudentContent) {
          out.add(pw.NewPage());
          out.add(pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(color: _primaryDark, borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Text('$branch ŞUBESİ  •  ÖĞRENCİ BAZLI TAKİP RAPORU (${students.length} ÖĞRENCİ)',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.white, letterSpacing: 0.6)),
          ));
          out.add(pw.SizedBox(height: 8));
          for (int i = 0; i < students.length; i++) {
            final s = students[i];
            if (i > 0) {
              final cardHeight = (50.0 + (s.rows.length * 24.0)).clamp(90.0, 320.0);
              out.add(pw.NewPage(freeSpace: cardHeight));
            }
            out.add(_studentCard(s, d.creatorFullName));
          }
        } else if (mode == ActionPlanReportMode.full && !hasClassContent) {
          out.add(pw.NewPage());
          out.add(_sectionTitle('$branch  •  Öğrenci Bazlı Takip'));
          out.add(pw.SizedBox(height: 6));
          out.add(pw.Text('Bu şubede başarı barajının altında kalan öğrenci bulunmuyor.',
              style: const pw.TextStyle(fontSize: 8, color: _grey)));
        }
      }
    }

    // ──────────────── 2. KURS DERSLERİ (İNGİLİZCE vb. - RAPORUN EN ARKASINDA AYRICA) ────────────────
    if (showClass && d.courseBranches.isNotEmpty) {
      for (final branch in d.courseBranches) {
        final courseSubjectRowsMap = <String, List<_OutcomeRow>>{};
        for (final subject in d.courseSubjectsOf(branch)) {
          final rows = d.outcomeRows(branch, subject);
          if (rows.isNotEmpty) courseSubjectRowsMap[subject] = rows;
        }

        // Eğer bu kurs şubesi için girilmiş bir eylem planı veya kritik kazanım yoksa rapora EKLEME
        if (courseSubjectRowsMap.isEmpty) {
          continue;
        }

        out.add(pw.NewPage());
        final kurLabel = branch.contains('•') ? branch.split('•').last.trim() : branch;
        final bannerTitle = branch.contains('•')
            ? '$branch  •  KURS GENEL RAPORU'
            : '${d.courseGroupTitle} • $kurLabel  •  KURS GENEL RAPORU';

        out.add(pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: pw.BoxDecoration(color: _primaryDark, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(bannerTitle,
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white, letterSpacing: 0.6)),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: pw.BoxDecoration(color: PdfColors.indigo400, borderRadius: pw.BorderRadius.circular(4)),
                child: pw.Text('KURS ŞUBESİ',
                    style: pw.TextStyle(fontSize: 7.5, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
        ));
        out.add(pw.SizedBox(height: 8));

        final courseEntries = courseSubjectRowsMap.entries.toList();
        for (int i = 0; i < courseEntries.length; i++) {
          final entry = courseEntries[i];
          final subject = entry.key;
          final rows = entry.value;
          final teacher = d.teacher(branch, subject);

          if (i > 0) {
            // Tablo başlığı ve tablonun kendisi mevcut sayfaya sığmıyorsa başlıkla birlikte yeni sayfadan başlat
            final neededSpace = (65.0 + (rows.length * 42.0)).clamp(130.0, 540.0);
            out.add(pw.NewPage(freeSpace: neededSpace));
          }

          out.add(pw.Row(children: [
            pw.Text(subject, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _primary)),
            pw.SizedBox(width: 8),
            pw.Text('Öğretmen: $teacher', style: const pw.TextStyle(fontSize: 8, color: _grey)),
            pw.Spacer(),
            pw.Text('Baraj: %${(plan.subjectThresholds[subject] ?? 0).round()}', style: const pw.TextStyle(fontSize: 8, color: _grey)),
          ]));
          out.add(pw.SizedBox(height: 4));
          out.add(_buildOutcomeTable(rows, teacher, d.creatorFullName));
          out.add(pw.SizedBox(height: 10));
        }

        // ── 2. Kurs Şubesi Öğrenci Bazlı Takip Raporu ──
        if (showStudent) {
          final courseStudents = d.courseStudentsOf(branch);
          if (courseStudents.isNotEmpty) {
            final firstCardHeight = (50.0 + (courseStudents.first.rows.length * 24.0)).clamp(90.0, 320.0);
            out.add(pw.NewPage(freeSpace: firstCardHeight + 48.0));
            out.add(pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: pw.BoxDecoration(color: _primaryDark, borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Text('$branch  •  ÖĞRENCİ BAZLI TAKİP RAPORU (${courseStudents.length} ÖĞRENCİ)',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.white, letterSpacing: 0.6)),
            ));
            out.add(pw.SizedBox(height: 8));
            for (int i = 0; i < courseStudents.length; i++) {
              final s = courseStudents[i];
              if (i > 0) {
                final h = (50.0 + (s.rows.length * 24.0)).clamp(90.0, 320.0);
                out.add(pw.NewPage(freeSpace: h));
              }
              out.add(_studentCard(s, d.creatorFullName));
            }
          }
        }
      }
    }

    if (out.isEmpty) {
      out.add(pw.SizedBox(height: 20));
      out.add(pw.Center(child: pw.Text('Raporlanacak eylem planı verisi bulunamadı.', style: const pw.TextStyle(color: _grey))));
    }
    return out;
  }

  static pw.Widget _buildOutcomeTable(List<_OutcomeRow> rows, String teacher, [String creatorFullName = '']) {
    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.6),
      columnWidths: {
        0: const pw.FlexColumnWidth(3.2),
        1: const pw.FixedColumnWidth(36),
        2: const pw.FlexColumnWidth(3),
        3: const pw.FlexColumnWidth(2.2),
        4: const pw.FixedColumnWidth(54),
        5: const pw.FixedColumnWidth(62),
      },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: _primaryLight),
          children: [
            _cell('Kazanım', bold: true, color: _primaryDark),
            _cell('Başarı', bold: true, color: _primaryDark, align: pw.TextAlign.center),
            _cell('Problem Kaynağı', bold: true, color: _primaryDark),
            _cell('Eylem Planı', bold: true, color: _primaryDark),
            _cell('Durum', bold: true, color: _primaryDark, align: pw.TextAlign.center),
            _cell('Güncelleyen', bold: true, color: _primaryDark, align: pw.TextAlign.center),
          ],
        ),
        ...rows.map((r) {
          final isProblemOrActionSet = r.problem.isNotEmpty || r.action.isNotEmpty;
          String resolvedUpdatedBy = '-';
          if (isProblemOrActionSet) {
            // İŞLEMİ YAPAN: Dersin atanan öğretmeni varsa işlem yapan dersin öğretmenidir
            if (teacher.isNotEmpty && teacher != 'Atanmamış') {
              resolvedUpdatedBy = teacher;
            } else if (r.updatedBy.isNotEmpty &&
                r.updatedBy != 'Kullanıcı' &&
                r.updatedBy != 'Sistem Yöneticisi' &&
                r.updatedBy != 'Yönetici') {
              resolvedUpdatedBy = r.updatedBy;
            } else if (creatorFullName.isNotEmpty &&
                creatorFullName != 'Kullanıcı' &&
                creatorFullName != 'Sistem Yöneticisi' &&
                creatorFullName != 'Yönetici') {
              resolvedUpdatedBy = creatorFullName;
            } else {
              resolvedUpdatedBy = teacher.isNotEmpty ? teacher : '-';
            }
          }
          return pw.TableRow(children: [
            _cell(r.outcome, size: 7.5),
            _cell('%${r.success.toStringAsFixed(0)}',
                bold: true,
                align: pw.TextAlign.center,
                color: r.critical ? _red : _green,
                bg: r.critical ? _redBg : _greenBg),
            _cell(r.problem.isEmpty ? '-' : r.problem, size: 7),
            _cell(r.action.isEmpty ? '-' : r.action, size: 7.5),
            _cell(r.status, size: 7, bold: true, align: pw.TextAlign.center, color: _statusColor(r.status)),
            _cell(resolvedUpdatedBy, size: 7, align: pw.TextAlign.center),
          ]);
        }),
      ],
    );
  }

  static pw.Widget _studentCard(_StudentReport s, [String fallbackUser = '']) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Column(children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: pw.BoxDecoration(
            color: _primaryLight,
            borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(8)),
          ),
          child: pw.Row(children: [
            pw.Text(s.name, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _primaryDark)),
            if (s.no.isNotEmpty) ...[
              pw.SizedBox(width: 6),
              pw.Text('No: ${s.no}', style: const pw.TextStyle(fontSize: 8, color: _grey)),
            ],
            pw.Spacer(),
            _pill(s.allNotified ? 'Veli Bilgilendirildi' : (s.anyNotified ? 'Veli Kısmen Bilgilendirildi' : 'Veli Bilgilendirilmedi'),
                s.allNotified ? _green : (s.anyNotified ? _orange : _red),
                s.allNotified ? _greenBg : (s.anyNotified ? _orangeBg : _redBg)),
          ]),
        ),
        pw.Table(
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FixedColumnWidth(38),
            2: const pw.FlexColumnWidth(4),
            3: const pw.FixedColumnWidth(62),
            4: const pw.FixedColumnWidth(60),
          },
          border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5)),
          children: [
            pw.TableRow(
              repeat: true,
              children: [
              _cell('Ders', bold: true, color: _grey, size: 7),
              _cell('Başarı', bold: true, color: _grey, size: 7, align: pw.TextAlign.center),
              _cell('Yapılan Çalışmalar / Görevler', bold: true, color: _grey, size: 7),
              _cell('Veli', bold: true, color: _grey, size: 7, align: pw.TextAlign.center),
              _cell('Durum', bold: true, color: _grey, size: 7, align: pw.TextAlign.center),
            ]),
            ...s.rows.map((r) {
              final done = r.tasks.where((t) => t['done'] == true).length;
              final status = r.tasks.isEmpty ? 'Beklemede' : (done == r.tasks.length ? 'Tamamlandı' : 'Planlandı');
              return pw.TableRow(children: [
                _cell(r.subject, size: 8, bold: true),
                _cell(r.success == null ? '-' : '%${r.success!.toStringAsFixed(0)}',
                    size: 8, align: pw.TextAlign.center, bold: true, color: _red),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: r.tasks.isEmpty
                      ? pw.Text('Görev atanmadı', style: const pw.TextStyle(fontSize: 7.5, color: _grey))
                      : pw.Wrap(
                          spacing: 4,
                          runSpacing: 3,
                          children: r.tasks.map((t) {
                            final ok = t['done'] == true;
                            return pw.Container(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: pw.BoxDecoration(
                                color: ok ? _greenBg : _redBg,
                                borderRadius: pw.BorderRadius.circular(6),
                              ),
                              child: pw.Text('${t['label'] ?? ''}${ok ? ' (Yapıldı)' : ''}',
                                  style: pw.TextStyle(fontSize: 7, color: ok ? _green : _red)),
                            );
                          }).toList(),
                        ),
                ),
                _cell(r.notified ? 'Bilgilendirildi' : 'Yapılmadı',
                    size: 7, bold: true, align: pw.TextAlign.center, color: r.notified ? _green : _red),
                _cell(status,
                    size: 7,
                    bold: true,
                    align: pw.TextAlign.center,
                    color: status == 'Tamamlandı' ? _green : (status == 'Planlandı' ? _primary : _grey)),
              ]);
            }),
          ],
        ),
      ]),
    );
  }

  static pw.Widget _pill(String t, PdfColor color, PdfColor bg) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: color)),
      );

  /// Opens the system print / share preview for the report.
  static Future<void> preview(AssessmentActionPlan plan) async {
    final bytes = await generate(plan);
    await Printing.layoutPdf(
      name: 'Eylem_Plani_Raporu_${plan.title.replaceAll(RegExp(r'[^\w\-]+'), '_')}.pdf',
      onLayout: (_) async => bytes,
    );
  }
}

// ─────────────────────────── REPORT MODEL ───────────────────────────

class _ExamStudentComputation {
  final Map<String, dynamic> studentInfo;
  final Map<String, String> studentRealBranches;
  final Map<String, Map<String, Map<String, Map<String, dynamic>>>> outcomeStats;
  final Map<String, Map<String, List<Map<String, dynamic>>>> allStudentRecords;
  _ExamStudentComputation(
    this.studentInfo,
    this.studentRealBranches,
    this.outcomeStats, [
    this.allStudentRecords = const {},
  ]);
}

class _OutcomeRow {
  final String outcome;
  final double success;
  final bool critical;
  final String problem;
  final String action;
  final String status;
  final String updatedBy;
  _OutcomeRow(this.outcome, this.success, this.critical, this.problem, this.action, this.status, this.updatedBy);
}

class _StudentSubjectRow {
  final String subject;
  final double? success;
  final List<Map<String, dynamic>> tasks;
  final bool notified;
  final String updatedBy;
  _StudentSubjectRow(this.subject, this.success, this.tasks, this.notified, [this.updatedBy = '']);
}

class _StudentReport {
  String name;
  String no;
  final List<_StudentSubjectRow> rows = [];
  String updatedBy = '';
  _StudentReport(this.name, this.no);

  bool get allNotified => rows.isNotEmpty && rows.every((r) => r.notified);
  bool get anyNotified => rows.any((r) => r.notified);
}

class _LowOutcome {
  final String branch;
  final String subject;
  final String outcome;
  final double success;
  _LowOutcome(this.branch, this.subject, this.outcome, this.success);
}

class _BranchSummary {
  int critical = 0;
  int planned = 0;
  int completed = 0;
  int students = 0;
  int withTasks = 0;
  int notified = 0;
}

class _ReportData {
  final AssessmentActionPlan plan;
  final Map<String, Map<String, String>> teachers;
  final Map<String, String> studentRealBranches;
  final CourseTrackResolver tracks;
  final String creatorFullName;
  final Map<String, Map<String, List<Map<String, dynamic>>>> allStudentRecords;
  late final Map<String, Map<String, Map<String, Map<String, dynamic>>>> stats;
  late final List<String> branches;
  late final List<String> normalBranches;
  late final List<String> courseBranches;
  late final String courseGroupTitle;

  int plannedActions = 0;
  int completedActions = 0;
  int problemDefined = 0;
  int totalTasks = 0;
  int trackedStudents = 0;
  int notifiedStudents = 0;
  int studentsWithTasks = 0;

  /// Stored student info merged with the one computed from exam results.
  late final Map<String, dynamic> _info;

  final Map<String, List<_StudentReport>> _studentsByBranch = {};
  final Map<String, ({int students, int withTasks, int notified})> _courseBranchStudentCounts = {};

  _ReportData(
    this.plan,
    this.teachers,
    Map<String, dynamic> computedStudents,
    this.studentRealBranches,
    this.tracks, [
    this.creatorFullName = '',
    Map<String, Map<String, Map<String, Map<String, dynamic>>>> computedStats = const {},
    this.allStudentRecords = const {},
  ]) {
    if (computedStudents.isNotEmpty) {
      _info = {...computedStudents};
      plan.studentInfo.forEach((k, v) {
        if (v is! Map) return;
        final prev = Map<String, dynamic>.from(v);
        if (_info[k] is Map) {
          final cur = Map<String, dynamic>.from(_info[k] as Map);
          if (prev['updatedBy'] != null) cur['updatedBy'] = prev['updatedBy'];
          if (prev['updatedAt'] != null) cur['updatedAt'] = prev['updatedAt'];
          _info[k] = cur;
        } else {
          _info[k] = prev;
        }
      });
    } else {
      _info = {...plan.studentInfo};
    }

    stats = {};
    final sourceStats = computedStats.isNotEmpty ? computedStats : plan.outcomeStats;
    sourceStats.forEach((b, subjects) {
      if (subjects is! Map) return;
      final normBranch = b.endsWith(' Kur') ? b.substring(0, b.length - 4).trim() : b;
      stats.putIfAbsent(normBranch, () => {});
      subjects.forEach((s, outcomes) {
        if (outcomes is! Map) return;
        final sKey = s.toString();
        stats[normBranch]!.putIfAbsent(sKey, () => {});
        outcomes.forEach((o, v) {
          if (v is Map) stats[normBranch]![sKey]![o.toString()] = Map<String, dynamic>.from(v);
        });
      });
    });

    branches = stats.keys.toList()..sort(_natural);

    // Kurs / Kur grubu başlığı belirle (örn: "7. Sınıflar İngilizce Main Course")
    String title = '';
    final lvlNorm = _norm(plan.classLevel);
    for (final g in tracks.groups) {
      if (g.type == DynamicCourseGroupType.track) {
        final n = g.name.trim();
        if (lvlNorm.isNotEmpty && _norm(n).contains(lvlNorm)) {
          title = n.toLowerCase().contains('ingilizce') ? n : 'İngilizce $n';
          break;
        }
      }
    }
    if (title.isEmpty) {
      for (final b in branches) {
        if (b.contains('•')) {
          final prefix = b.split('•').first.trim();
          if (prefix.isNotEmpty) {
            title = prefix;
            break;
          }
        }
      }
    }
    if (title.isEmpty) {
      for (final g in tracks.groups) {
        if (g.type == DynamicCourseGroupType.track) {
          final n = g.name.trim();
          if (n.isNotEmpty) {
            title = n.toLowerCase().contains('ingilizce') ? n : 'İngilizce $n';
            break;
          }
        }
      }
    }
    if (title.isEmpty) {
      final lvl = plan.classLevel.trim();
      title = lvl.isNotEmpty ? '$lvl İngilizce Main Course' : 'İngilizce Main Course';
    }
    courseGroupTitle = title;

    for (final b in branches) {
      for (final s in subjectsOf(b)) {
        for (final r in outcomeRows(b, s)) {
          if (r.problem.trim().isNotEmpty) problemDefined++;
          if (r.action.trim().isNotEmpty) plannedActions++;
          if (r.status == 'Tamamlandı') completedActions++;
        }
      }
    }

    _buildStudents();
  }

  static String _norm(String s) => s
      .replaceAll('İ', 'i')
      .replaceAll('I', 'i')
      .replaceAll('ı', 'i')
      .toLowerCase()
      .replaceAll('i̇', 'i')
      .replaceAll('ı', 'i')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ş', 's')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  static bool _isEnglishLesson(String normLesson) {
    final s = normLesson.toLowerCase();
    return s.contains('ingilizce') || s.contains('i̇ngilizce') || s.contains('english');
  }

  static int _getSubjectOrderIndex(String subject) {
    final s = subject.toLowerCase().trim();
    if (s.contains('türkçe') || s.contains('turkce')) return 1;
    if (s.contains('sosyal') || s.contains('tarih') || s.contains('inkılap') || s.contains('inkilap')) return 2;
    if (s.contains('din')) return 3;
    if (s.contains('ingilizce') || s.contains('i̇ngilizce') || s.contains('english') || s.contains('yabancı dil') || s.contains('yabanci dil')) return 4;
    if (s.contains('matematik')) return 5;
    if (s.contains('fen')) return 6;
    return 99;
  }

  bool isCourseSubject(String subject) {
    if (!tracks.isEmpty) {
      return tracks.hasTrackForBranchOrLevel(subject, classLevel: plan.classLevel);
    }
    return _isEnglishLesson(subject);
  }

  /// Bir şubenin münhasıran kurs / kur grubu olup olmadığını tespit eder.
  bool isCourseBranch(String branch) {
    if (branch.contains('•')) return true;
    final bNorm = _norm(branch);
    if (bNorm.contains('maincourse') ||
        bNorm.contains('track') ||
        bNorm.contains('kurs') ||
        bNorm.contains('kur')) {
      return true;
    }
    final branchSubjects = stats[branch]?.keys.toList() ?? [];
    if (branchSubjects.isNotEmpty && branchSubjects.every(isCourseSubject)) {
      return true;
    }
    return false;
  }

  List<String> subjectsOf(String branch) => (stats[branch]?.keys.toList() ?? [])..sort();

  List<String> normalSubjectsOf(String branch) =>
      (stats[branch]?.keys.where((s) => !isCourseSubject(s)).toList() ?? [])..sort();

  List<String> courseSubjectsOf(String branch) =>
      (stats[branch]?.keys.where(isCourseSubject).toList() ?? [])..sort();

  int get subjectCount => stats.values.expand((m) => m.keys).toSet().length;

  int get criticalOutcomeCount =>
      normalBranches.fold(0, (a, b) => a + normalBranchSummary(b).critical) +
      courseBranches.fold(0, (a, b) => a + courseBranchSummary(b).critical);

  dynamic _branchActionPlanEntry(String branch, String subject, String outcome) {
    final direct = plan.branchActionPlans['${branch}_${subject}_$outcome'];
    if (direct != null) return direct;
    final altBranch = branch.endsWith(' Kur')
        ? branch.substring(0, branch.length - 4).trim()
        : '$branch Kur';
    return plan.branchActionPlans['${altBranch}_${subject}_$outcome'];
  }

  _BranchSummary normalBranchSummary(String branch) {
    final s = _BranchSummary();
    for (final subject in normalSubjectsOf(branch)) {
      final threshold = plan.subjectThresholds[subject] ?? 70.0;
      (stats[branch]![subject] ?? {}).forEach((outcome, v) {
        final total = (v['total'] ?? 0) as num;
        final correct = (v['correct'] ?? 0) as num;
        final success = total > 0 ? correct / total * 100 : 0.0;
        if (success < threshold) {
          s.critical++;
          final entry = _branchActionPlanEntry(branch, subject, outcome);
          if (entry is Map) {
            if ((entry['actionPlan'] ?? '').toString().trim().isNotEmpty) s.planned++;
            if (entry['status'] == 'Tamamlandı') s.completed++;
          }
        }
      });
    }

    final normalStudents = normalStudentsOf(branch);
    s.students = normalStudents.length;
    s.withTasks = normalStudents.where((st) => st.rows.any((r) => r.tasks.isNotEmpty)).length;
    s.notified = normalStudents.where((st) => st.rows.any((r) => r.notified)).length;
    return s;
  }

  _BranchSummary courseBranchSummary(String branch) {
    final s = _BranchSummary();
    for (final subject in courseSubjectsOf(branch)) {
      final threshold = plan.subjectThresholds[subject] ?? 70.0;
      (stats[branch]![subject] ?? {}).forEach((outcome, v) {
        final total = (v['total'] ?? 0) as num;
        final correct = (v['correct'] ?? 0) as num;
        final success = total > 0 ? correct / total * 100 : 0.0;
        if (success < threshold) {
          s.critical++;
          final entry = _branchActionPlanEntry(branch, subject, outcome);
          if (entry is Map) {
            if ((entry['actionPlan'] ?? '').toString().trim().isNotEmpty) s.planned++;
            if (entry['status'] == 'Tamamlandı') s.completed++;
          }
        }
      });
    }

    final courseSts = courseStudentsOf(branch);
    s.students = courseSts.length;
    s.withTasks = courseSts.where((st) => st.rows.any((r) => r.tasks.isNotEmpty)).length;
    s.notified = courseSts.where((st) => st.rows.any((r) => r.notified)).length;
    return s;
  }

  _BranchSummary branchSummary(String branch) => isCourseBranch(branch)
      ? courseBranchSummary(branch)
      : normalBranchSummary(branch);

  List<_LowOutcome> lowestOutcomes(int n) {
    final list = <_LowOutcome>[];
    for (final b in branches) {
      for (final subject in subjectsOf(b)) {
        final threshold = plan.subjectThresholds[subject] ?? 70.0;
        (stats[b]![subject] ?? {}).forEach((outcome, v) {
          final total = (v['total'] ?? 0) as num;
          final correct = (v['correct'] ?? 0) as num;
          final success = total > 0 ? (correct / total * 100).toDouble() : 0.0;
          if (success < threshold) list.add(_LowOutcome(b, subject, outcome, success));
        });
      }
    }
    list.sort((a, b) => a.success.compareTo(b.success));
    return list.take(n).toList();
  }

  static int _natural(String a, String b) {
    final ra = RegExp(r'^(\d+)').firstMatch(a);
    final rb = RegExp(r'^(\d+)').firstMatch(b);
    if (ra != null && rb != null) {
      final c = int.parse(ra.group(1)!).compareTo(int.parse(rb.group(1)!));
      if (c != 0) return c;
    }
    return a.compareTo(b);
  }

  String teacher(String branch, String subject) {
    // 1. Exact branch + subject match
    final exact = teachers[branch]?[subject];
    if (exact != null && exact.isNotEmpty) return exact;

    // 2. Normalized branch + normalized/partial subject match
    final bNorm = _norm(branch);
    final sNorm = _norm(subject);
    for (final entry in teachers.entries) {
      if (entry.key == '*') continue;
      if (_norm(entry.key) == bNorm) {
        final directSubj = entry.value[subject];
        if (directSubj != null && directSubj.isNotEmpty) return directSubj;
        for (final subEntry in entry.value.entries) {
          final cl = _norm(subEntry.key);
          if (cl.isNotEmpty &&
              sNorm.isNotEmpty &&
              (cl == sNorm || cl.contains(sNorm) || sNorm.contains(cl) || CourseTrackResolver.lessonMatches(subEntry.key, subject))) {
            return subEntry.value;
          }
        }
      }
    }

    // 3. Subject-only fallback ('*') with exact or partial match
    final fallbackMap = teachers['*'] ?? const {};
    final exactFallback = fallbackMap[subject];
    if (exactFallback != null && exactFallback.isNotEmpty) return exactFallback;
    for (final subEntry in fallbackMap.entries) {
      final cl = _norm(subEntry.key);
      if (cl.isNotEmpty &&
          sNorm.isNotEmpty &&
          (cl == sNorm || cl.contains(sNorm) || sNorm.contains(cl) || CourseTrackResolver.lessonMatches(subEntry.key, subject))) {
        return subEntry.value;
      }
    }

    return 'Atanmamış';
  }

  List<_OutcomeRow> outcomeRows(String branch, String subject) {
    final threshold = plan.subjectThresholds[subject] ?? 70.0;
    final outcomes = stats[branch]?[subject] ?? {};
    final List<_OutcomeRow> rows = [];
    final bool isCourse = isCourseSubject(subject);
    outcomes.forEach((outcome, v) {
      final total = (v['total'] ?? 0) as num;
      final correct = (v['correct'] ?? 0) as num;
      final success = total > 0 ? correct / total * 100 : 0.0;
      final entry = _branchActionPlanEntry(branch, subject, outcome);
      final map = entry is Map ? Map<String, dynamic>.from(entry) : <String, dynamic>{};
      final problem = (map['problemSource'] ?? '').toString();
      final action = (map['actionPlan'] ?? '').toString().trim();
      final critical = success < threshold;
      // Kurs derslerinde kritik olmayan (ör. eski normal sınıf hesaplamasından kalan) kayıtları gösterme
      if (!critical && (isCourse || (problem.isEmpty && action.isEmpty))) return;

      final t = teacher(branch, subject);
      String by = (map['updatedBy'] ?? '').toString();
      if (problem.isNotEmpty || action.isNotEmpty) {
        if (t.isNotEmpty && t != 'Atanmamış') {
          by = t;
        } else if (by.isEmpty || by == 'Kullanıcı' || by == 'Sistem Yöneticisi') {
          if (creatorFullName.isNotEmpty &&
              creatorFullName != 'Kullanıcı' &&
              creatorFullName != 'Sistem Yöneticisi' &&
              creatorFullName != 'Yönetici') {
            by = creatorFullName;
          } else {
            by = t;
          }
        }
      }

      rows.add(_OutcomeRow(
        outcome,
        success.toDouble(),
        critical,
        problem,
        action,
        (map['status'] ?? 'Belirlenmedi').toString(),
        by,
      ));
    });
    rows.sort((a, b) => a.success.compareTo(b.success));
    return rows;
  }

  List<_StudentReport> studentsOf(String branch) => _studentsByBranch[branch] ?? [];

  List<_StudentReport> normalStudentsOf(String branch) {
    final list = <_StudentReport>[];
    for (final st in studentsOf(branch)) {
      final normalRows = st.rows.where((r) => !isCourseSubject(r.subject)).toList();
      if (normalRows.isEmpty) continue;
      final copy = _StudentReport(st.name, st.no)
        ..updatedBy = st.updatedBy
        ..rows.addAll(normalRows);
      list.add(copy);
    }
    return list;
  }

  List<_StudentReport> courseStudentsOf(String branch) {
    final list = <_StudentReport>[];
    for (final st in studentsOf(branch)) {
      final courseRows = st.rows.where((r) => isCourseSubject(r.subject)).toList();
      if (courseRows.isEmpty) continue;
      final copy = _StudentReport(st.name, st.no)
        ..updatedBy = st.updatedBy
        ..rows.addAll(courseRows);
      list.add(copy);
    }
    return list;
  }

  /// key format: branch_subject_studentKey
  ({String branch, String subject, String student})? _parseKey(String key) {
    final sortedBranches = [...branches]..sort((a, b) => b.length.compareTo(a.length));
    for (final b in sortedBranches) {
      final kurKey = '${b} Kur_';
      final bool isKur = key.startsWith(kurKey);
      if (!key.startsWith('${b}_') && !isKur) continue;
      final rest = isKur ? key.substring(kurKey.length) : key.substring(b.length + 1);
      final subs = (stats[b]?.keys.toList() ?? [])..sort((a, c) => c.length.compareTo(a.length));
      for (final s in subs) {
        if (rest.startsWith('${s}_')) {
          return (branch: b, subject: s, student: rest.substring(s.length + 1));
        }
      }
    }
    return null;
  }

  ({String name, String no, double? success}) _lookupStudentMeta(
    String branch,
    String subject,
    String studentKey,
  ) {
    final skNorm = _norm(studentKey);
    final bNorm = _norm(branch);
    final sNorm = _norm(subject);

    // 1. Check allStudentRecords from exam computation (exact or normalized branch + subject)
    for (final bEntry in allStudentRecords.entries) {
      if (bEntry.key != branch && _norm(bEntry.key) != bNorm) continue;
      for (final sEntry in bEntry.value.entries) {
        final sKeyNorm = _norm(sEntry.key);
        final subjMatches = sEntry.key == subject ||
            (sKeyNorm.isNotEmpty && sNorm.isNotEmpty && (sKeyNorm == sNorm || sKeyNorm.contains(sNorm) || sNorm.contains(sKeyNorm)));
        if (!subjMatches) continue;
        for (final rec in sEntry.value) {
          final rNo = (rec['no'] ?? '').toString().trim();
          final rName = (rec['name'] ?? '').toString().trim();
          if ((rNo.isNotEmpty && rNo == studentKey) ||
              (rName.isNotEmpty && _norm(rName) == skNorm)) {
            final s = rec['success'] is num ? (rec['success'] as num).toDouble() : null;
            return (name: rName, no: rNo, success: s);
          }
        }
      }
    }

    // 2. Check _info entries for the same branch & subject
    for (final v in _info.values) {
      if (v is! Map) continue;
      final vBranch = (v['branch'] ?? '').toString().replaceAll(RegExp(r'\s+Kur$'), '').trim();
      final vSubj = (v['subject'] ?? '').toString().trim();
      if ((vBranch == branch || _norm(vBranch) == bNorm) &&
          (vSubj == subject || _norm(vSubj) == sNorm)) {
        final vNo = (v['no'] ?? '').toString().trim();
        final vName = (v['name'] ?? '').toString().trim();
        if ((vNo.isNotEmpty && vNo == studentKey) ||
            (vName.isNotEmpty && _norm(vName) == skNorm)) {
          final s = v['success'] is num ? (v['success'] as num).toDouble() : null;
          return (name: vName, no: vNo, success: s);
        }
      }
    }

    // 3. Check outcomes student list (or any subject in the same branch to at least resolve student no & name)
    final outcomes = stats[branch]?[subject] ?? {};
    for (final v in outcomes.values) {
      final list = v['students'];
      if (list is List) {
        for (final st in list) {
          if (st is Map) {
            final stNo = (st['no'] ?? '').toString().trim();
            final stName = (st['name'] ?? '').toString().trim();
            if ((stNo.isNotEmpty && stNo == studentKey) ||
                (stName.isNotEmpty && _norm(stName) == skNorm)) {
              return (
                name: stName.isNotEmpty ? stName : studentKey,
                no: stNo,
                success: null,
              );
            }
          }
        }
      }
    }
    return (name: studentKey, no: '', success: null);
  }

  String _resolveRowUpdatedBy(
    String targetBranch,
    String rawBranch,
    String subject,
    String rawUpdatedBy,
    bool hasAction,
  ) {
    if (!hasAction) return '';
    // Öncelik: Bu şube ve dersin atanmış öğretmeni
    String t = teacher(targetBranch, subject);
    if (t.isEmpty || t == 'Atanmamış') {
      t = teacher(rawBranch, subject);
    }
    if (t.isNotEmpty && t != 'Atanmamış') {
      return t;
    }
    // Dersin atanmış öğretmeni yoksa ve kayıtta gerçek bir öğretmen adı varsa (planı oluşturan yönetici değilse)
    final by = rawUpdatedBy.trim();
    if (by.isNotEmpty &&
        by != 'Kullanıcı' &&
        by != 'Sistem Yöneticisi' &&
        by != 'Yönetici' &&
        by != 'Yükleniyor...' &&
        _norm(by) != _norm(creatorFullName) &&
        _norm(by) != _norm(plan.creatorName)) {
      return by;
    }
    return '';
  }

  void _buildStudents() {
    final keys = <String>{
      ..._info.keys,
      ...plan.studentTasks.keys,
      ...plan.parentNotified.keys,
    };
    // branch -> ident -> report
    final Map<String, Map<String, _StudentReport>> grouped = {};
    final Map<String, Map<String, ({bool hasTasks, bool notified})>> courseTracked = {};

    for (final key in keys) {
      final infoRaw = _info[key];
      final info = infoRaw is Map ? Map<String, dynamic>.from(infoRaw) : <String, dynamic>{};
      String branch = (info['branch'] ?? '').toString();
      if (branch.endsWith(' Kur')) {
        branch = branch.substring(0, branch.length - 4).trim();
      }
      String subject = (info['subject'] ?? '').toString();
      String studentKey = '';
      final parsed = _parseKey(key);
      if (parsed != null) {
        if (branch.isEmpty) branch = parsed.branch;
        if (subject.isEmpty) subject = parsed.subject;
        studentKey = parsed.student;
      }
      if (branch.isEmpty || subject.isEmpty) continue;

      final tasksRaw = plan.studentTasks[key];
      final tasks = tasksRaw is List
          ? tasksRaw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
          : <Map<String, dynamic>>[];
      final notified = plan.parentNotified[key] == true;
      if (!_info.containsKey(key) && (isCourseSubject(subject) || (tasks.isEmpty && !notified))) {
        continue;
      }

      String name = (info['name'] ?? '').toString().trim();
      String no = (info['no'] ?? '').toString().trim();
      double? success = info['success'] is num ? (info['success'] as num).toDouble() : null;

      if (name.isEmpty || no.isEmpty || success == null) {
        final meta = _lookupStudentMeta(branch, subject, studentKey.isNotEmpty ? studentKey : name);
        if (name.isEmpty && meta.name.isNotEmpty) name = meta.name;
        if (no.isEmpty && meta.no.isNotEmpty) no = meta.no;
        success ??= meta.success;
      }
      if (no.isEmpty && studentKey.isNotEmpty && studentKey != name && RegExp(r'^\d+$').hasMatch(studentKey)) {
        no = studentKey;
      }

      // Kurs derslerinde öğrenci kendi kurs şubesine (ör. 701) yerleştirilir.
      String targetBranch = branch;
      if (isCourseSubject(subject)) {
        final slot = tracks.slotForStudent(
          studentNo: no,
          studentName: name,
          subject: subject,
          rawBranch: branch,
          classLevel: plan.classLevel,
        );
        if (slot != null) {
          final sub = slot.subGroupName.replaceAll(RegExp(r'\s+'), ' ').trim();
          targetBranch = sub.endsWith(' Kur') ? sub.substring(0, sub.length - 4).trim() : sub;
        }
      }

      // Aynı şubede öğrenci daha önce numarasıyla veya ismiyle eklendiyse aynı kartta birleştir
      final branchMap = grouped.putIfAbsent(targetBranch, () => {});
      final normName = _norm(name);
      String? matchedIdent;
      if (no.isNotEmpty && branchMap.containsKey(no)) {
        matchedIdent = no;
      } else if (normName.isNotEmpty) {
        for (final entry in branchMap.entries) {
          if ((no.isNotEmpty && entry.value.no == no) ||
              (_norm(entry.value.name) == normName)) {
            matchedIdent = entry.key;
            break;
          }
        }
      }
      final ident = matchedIdent ?? (no.isNotEmpty ? no : name);
      final rep = branchMap.putIfAbsent(ident, () => _StudentReport(name, no));
      if (rep.no.isEmpty && no.isNotEmpty) rep.no = no;
      if (rep.name.isEmpty && name.isNotEmpty) rep.name = name;

      if (isCourseSubject(subject) || isCourseBranch(targetBranch)) {
        final map = courseTracked.putIfAbsent(targetBranch, () => {});
        final prev = map[ident];
        final hTasks = tasks.isNotEmpty || (prev?.hasTasks ?? false);
        final isNotif = notified || (prev?.notified ?? false);
        map[ident] = (hasTasks: hTasks, notified: isNotif);
      }

      final rawBy = (info['updatedBy'] ?? '').toString();
      final existingRowIndex = rep.rows.indexWhere((r) => r.subject == subject);
      if (existingRowIndex >= 0) {
        final existingRow = rep.rows[existingRowIndex];
        final combinedTasks = [...existingRow.tasks];
        for (final t in tasks) {
          if (!combinedTasks.any((ct) => ct['label'] == t['label'] && ct['type'] == t['type'])) {
            combinedTasks.add(t);
          }
        }
        final combinedNotified = existingRow.notified || notified;
        final hasAction = combinedTasks.isNotEmpty || combinedNotified;
        final resolvedBy = _resolveRowUpdatedBy(
          targetBranch,
          branch,
          subject,
          rawBy.isNotEmpty ? rawBy : existingRow.updatedBy,
          hasAction,
        );
        rep.rows[existingRowIndex] = _StudentSubjectRow(
          subject,
          existingRow.success ?? success,
          combinedTasks,
          combinedNotified,
          resolvedBy.isNotEmpty ? resolvedBy : existingRow.updatedBy,
        );
      } else {
        final hasAction = tasks.isNotEmpty || notified;
        final resolvedBy = _resolveRowUpdatedBy(targetBranch, branch, subject, rawBy, hasAction);
        rep.rows.add(_StudentSubjectRow(subject, success, tasks, notified, resolvedBy));
      }
    }

    courseTracked.forEach((cb, studentsMap) {
      _courseBranchStudentCounts[cb] = (
        students: studentsMap.length,
        withTasks: studentsMap.values.where((v) => v.hasTasks).length,
        notified: studentsMap.values.where((v) => v.notified).length,
      );
    });

    grouped.forEach((branch, map) {
      final list = map.values.toList()..sort((a, b) => a.name.compareTo(b.name));
      for (final r in list) {
        r.rows.sort((a, b) {
          final oa = _getSubjectOrderIndex(a.subject);
          final ob = _getSubjectOrderIndex(b.subject);
          if (oa != ob) return oa.compareTo(ob);
          return a.subject.compareTo(b.subject);
        });
        for (final row in r.rows) {
          totalTasks += row.tasks.length;
        }
        trackedStudents++;
        if (r.anyNotified) notifiedStudents++;
        if (r.rows.any((x) => x.tasks.isNotEmpty)) studentsWithTasks++;
      }
      _studentsByBranch[branch] = list;
      if (!branches.contains(branch)) branches.add(branch);
    });

    branches.sort(_natural);

    // Normal şubeler: Kurs şubesi olmayan ve en az bir normal dersi (veya öğrencisi) bulunan şubeler
    normalBranches = branches.where((b) {
      if (isCourseBranch(b)) return false;
      final subs = stats[b]?.keys.where((s) => !isCourseSubject(s)).toList() ?? [];
      return subs.isNotEmpty || normalStudentsOf(b).isNotEmpty;
    }).toList();

    // Kurs şubeleri: Ya doğrudan kur şubesidir (adı • içerir vb.) ya da bünyesinde kurs dersi (İngilizce) bulunan şubelerdir
    courseBranches = branches.where((b) {
      if (isCourseBranch(b)) return true;
      final subs = stats[b]?.keys.where(isCourseSubject).toList() ?? [];
      return subs.isNotEmpty || courseStudentsOf(b).isNotEmpty;
    }).toList();
  }
}
