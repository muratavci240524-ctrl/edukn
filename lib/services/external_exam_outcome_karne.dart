import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../models/assessment/external_exam_model.dart';
import '../models/assessment/external_exam_result_model.dart';
import '../screens/school/assessment/evaluation_models.dart' as ev;
import '../screens/school/assessment/exam_report_card_service.dart';
import '../screens/school/assessment/student_report_card_dialog.dart';
import 'external_exam_karne_pdf_service.dart';

/// Dış katılımlı sınav sonuçları için Ölçme Değerlendirme tarzı "Kazanım Karnesi"
/// (ekranda görüntüleme + PDF) ve "Sonuç Karnesi / Kazanım Karnesi" seçimi.
///
/// Kazanım listesi sonuç kaydının içinde saklıdır; bu yüzden herkese açık sorgulama
/// sayfasında da (ek yetki gerekmeden) çalışır.
class ExternalExamOutcomeKarne {
  ExternalExamOutcomeKarne._();

  /// Kazanım karnesi için cevap + kazanım verisi var mı?
  static bool hasData(ExternalExamResult r) => r.subjects.any(
    (s) => s.answers.isNotEmpty && s.key.isNotEmpty && s.outcomes.isNotEmpty,
  );

  static ev.StudentResult toStudent(ExternalExamResult r) {
    final student = ev.StudentResult(
      tcNo: r.tcNo,
      studentNo: '',
      name: r.fullName,
      classLevel: r.gradeLevel,
      branch: '',
      booklet: r.subjects.map((s) => s.booklet).firstWhere((b) => b.isNotEmpty, orElse: () => ''),
      score: r.score,
      rankGeneral: r.rank,
      rankInstitution: r.rank,
      rankBranch: r.rank,
      isMatched: true,
    );
    for (final s in r.subjects) {
      student.subjects[s.name] = ev.SubjectStats(correct: s.correct, wrong: s.wrong, empty: s.empty, net: s.net);
      student.answers[s.name] = s.answers;
      student.correctAnswers[s.name] = s.key;
    }
    return student;
  }

  /// Kitapçık -> ders -> soru başına kazanım.
  static Map<String, Map<String, List<String>>> outcomesOf(Iterable<ExternalExamResult> results) {
    final out = <String, Map<String, List<String>>>{};
    for (final r in results) {
      for (final s in r.subjects) {
        if (s.outcomes.isEmpty) continue;
        final b = s.booklet.isEmpty ? 'A' : s.booklet;
        out.putIfAbsent(b, () => {})[s.name] = s.outcomes;
      }
    }
    return out;
  }

  static String scholarshipNote(ExternalExam exam, ExternalExamResult r) {
    if (!exam.scholarshipEnabled) return '';
    if (r.scholarshipRate > 0) {
      return 'Tebrikler! ${r.gradeLevel}. sınıf sıralamanız ${r.rank}. olduğu için %${r.scholarshipRate} burs hakkı kazandınız. '
          'Kayıt işlemleri için kurumumuzla iletişime geçiniz.';
    }
    return 'Bu sınavda burs kazanma sıralamasına girilemedi. Sınava katıldığınız için teşekkür ederiz.';
  }

  static void _snack(BuildContext context, String m, {Color? color}) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m), backgroundColor: color));
  }

  /// Kazanım karnesini ekranda açar.
  static Future<void> open(BuildContext context, ExternalExam exam, ExternalExamResult r) async {
    if (!hasData(r)) {
      _snack(
        context,
        'Bu sonuç için kazanım verisi yok. Kurumunuzun optik dosyaları yeniden okutması gerekir.',
        color: Colors.orange,
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudentReportCardDialog(
          student: toStudent(r),
          examName: exam.title,
          subjects: r.orderedSubjects.map((s) => s.name).toList(),
          outcomes: outcomesOf([r]),
          totalStudents: r.totalInGrade,
          schoolStudents: r.totalInGrade,
          branchStudents: r.totalInGrade,
          scholarshipRate: exam.scholarshipEnabled ? r.scholarshipRate : null,
          scholarshipEnabled: exam.scholarshipEnabled,
        ),
      ),
    );
  }

  /// Kazanım karnesi PDF'i (tek ya da toplu) hazırlar. Hazırlanırken ilerleme animasyonu gösterilir;
  /// tek karne yazdırma penceresinde açılır, toplu karneler doğrudan PDF dosyası olarak indirilir
  /// (yüzlerce sayfayı yazdırma önizlemesinde çizmek ekranı dondurduğu için).
  static Future<void> printOutcome(
    BuildContext context,
    ExternalExam exam,
    List<ExternalExamResult> results,
  ) async {
    final usable = results.where(hasData).toList();
    if (usable.isEmpty) {
      _snack(
        context,
        'Kazanım karnesi için gerekli veri yok. Optik dosyaların yeniden okutulması gerekir.',
        color: Colors.orange,
      );
      return;
    }

    final progress = ValueNotifier<int>(0);
    final total = usable.length;
    var dialogOpen = true;
    // ignore: unawaited_futures
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (_, done, __) {
              final finishing = done >= total;
              return SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 6),
                    const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 4)),
                    const SizedBox(height: 18),
                    Text(
                      finishing ? 'PDF dosyası oluşturuluyor...' : 'Kazanım karneleri hazırlanıyor...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(minHeight: 8, value: total == 0 ? null : (done / total).clamp(0.0, 1.0)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${done > total ? total : done} / $total karne',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    void closeDialog() {
      if (dialogOpen && context.mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    try {
      // Dialog çizilsin diye bir kare bekle
      await Future.delayed(const Duration(milliseconds: 80));
      final notes = <String, String>{};
      final won = <String, bool>{};
      for (final r in usable) {
        final n = scholarshipNote(exam, r);
        if (n.isNotEmpty) {
          notes[r.tcNo] = n;
          won[r.tcNo] = r.scholarshipRate > 0;
        }
      }
      final subjects = <String>{for (final r in usable) ...r.orderedSubjects.map((s) => s.name)}.toList();
      final bytes = await ExamReportCardService().generateStudentReportCardsPdf(
        students: usable.map(toStudent).toList(),
        examName: exam.title,
        subjects: subjects,
        definedSubjectOrder: subjects,
        outcomes: outcomesOf(usable),
        totalStudents: usable.first.totalInGrade,
        schoolStudents: usable.first.totalInGrade,
        scholarshipNotes: notes,
        scholarshipWon: won,
        onProgress: (done, _) => progress.value = done,
      );
      closeDialog();
      if (usable.length < results.length && context.mounted) {
        _snack(context, '${results.length - usable.length} sonucun kazanım verisi olmadığı için atlandı.', color: Colors.orange);
      }
      final fileName = usable.length == 1
          ? 'kazanim_karnesi_${usable.first.fullName.replaceAll(' ', '_')}.pdf'
          : 'kazanim_karneleri_${exam.title.replaceAll(' ', '_')}.pdf';
      if (usable.length == 1) {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      }
    } catch (e) {
      closeDialog();
      if (context.mounted) _snack(context, 'Kazanım karnesi oluşturulamadı: $e', color: Colors.red);
    } finally {
      progress.dispose();
    }
  }
  /// "Yazdır": önce Sonuç Karnesi mi Kazanım Karnesi mi diye sorar.
  static Future<void> printWithChoice(
    BuildContext context,
    ExternalExam exam,
    List<ExternalExamResult> results, {
    String? schoolName,
  }) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(results.length > 1 ? 'Yazdır (${results.length} aday)' : 'Yazdır'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'exam'),
            child: const ListTile(
              leading: Icon(Icons.assignment_rounded),
              title: Text('Sonuç Karnesi'),
              subtitle: Text('Puan, sıralama, ders netleri ve burs durumu'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'outcome'),
            child: const ListTile(
              leading: Icon(Icons.track_changes_rounded),
              title: Text('Kazanım Karnesi'),
              subtitle: Text('Ders ve kazanım analizi, cevap anahtarı ve burs durumu'),
            ),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'exam') {
      await ExternalExamKarnePdfService.printKarneler(exam: exam, results: results, schoolName: schoolName);
    } else {
      await printOutcome(context, exam, results);
    }
  }
}
