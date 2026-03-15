import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class AcademicAnxietyPerformanceTest extends GuidanceTestDefinition {
  @override
  String get id => 'academic_anxiety_performance_v1';

  @override
  String get title => 'Akademik Kaygı – Performans Dengesi Ölçeği (AK-PDÖ)';

  @override
  String get description =>
      'Kaygının akademik performansı nasıl etkilediğini; bilişsel, duygusal ve fizyolojik boyutlarda analiz eder.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'anxiety_perf_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Bilişsel Kaygı (1-12)
      'Sınavda bildiklerimi hatırlamakta zorlanırım.', // 1 (T) - Scoring handled in report
      'Zihnim sınav anında donar.', // 2 (T)
      'Kaygı düşünme hızımı düşürür.', // 3 (T)
      'Sınavda aklıma gereksiz düşünceler gelir.', // 4 (T)
      'Düşüncelerimi toparlayabilirim.', // 5
      'Kaygı dikkatimi dağıtır.', // 6 (T)
      'Sorulara odaklanmakta zorlanırım.', // 7 (T)
      'Zihinsel kontrolümü koruyabilirim.', // 8
      'Bildiklerim kayboluyormuş gibi hissederim.', // 9 (T)
      'Zihnimi yönetebilirim.', // 10
      'Kaygı karar vermemi zorlaştırır.', // 11 (T)
      'Zihinsel olarak netimdir.', // 12
      // B) Duygusal Kaygı (13-24)
      'Sınav öncesi yoğun endişe yaşarım.', // 13 (T)
      'Kaygı beni duygusal olarak zorlar.', // 14 (T)
      'Kendime güvenimi kaybederim.', // 15 (T)
      'Sınavlar beni aşırı gerer.', // 16 (T)
      'Heyecanımı kontrol edebilirim.', // 17
      'Kaygı özgüvenimi azaltır.', // 18 (T)
      'Sınavlarda içsel huzurumu korurum.', // 19
      'Başarısızlık korkusu beni sarar.', // 20 (T)
      'Duygularımı yönetebilirim.', // 21
      'Sınav kelimesi bile beni tedirgin eder.', // 22 (T)
      'Kendimi sakinleştirebilirim.', // 23
      'Kaygı beni duygusal olarak kilitler.', // 24 (T)
      // C) Fizyolojik Tepkiler (25-36)
      'Sınav öncesi kalp çarpıntısı yaşarım.', // 25 (T)
      'Midem bulanır.', // 26 (T)
      'Ellerim titrer.', // 27 (T)
      'Nefesim hızlanır.', // 28 (T)
      'Bedensel tepkilerimi kontrol edebilirim.', // 29
      'Kaygı bedenimi etkiler.', // 30 (T)
      'Fiziksel belirtiler performansımı düşürür.', // 31 (T)
      'Bedensel olarak sakin kalabilirim.', // 32
      'Terleme yaşarım.', // 33 (T)
      'Vücudum gerilir.', // 34 (T)
      'Bedensel farkındalığım yüksektir.', // 35
      'Fiziksel belirtiler beni durdurmaz.', // 36
      // D) Kaygının Performansa Etkisi (37-52)
      'Kaygı performansımı düşürür.', // 37 (T)
      'Kaygı beni motive eder.', // 38
      'Kaygı sayesinde daha dikkatliyim.', // 39
      'Aşırı kaygı beni kilitler.', // 40 (T)
      'Kaygı odaklanmamı artırır.', // 41
      'Kaygı yüzünden süreyi yönetemem.', // 42 (T)
      'Orta düzey kaygı bana iyi gelir.', // 43
      'Kaygı yüzünden bildiğimi yapamam.', // 44 (T)
      'Kaygı beni hızlandırır.', // 45
      'Kaygı hatalarımı artırır.', // 46 (T)
      'Kaygıyı performansa çevirebilirim.', // 47
      'Kaygı beni tamamen bloke eder.', // 48 (T)
      'Kaygı beni disipline eder.', // 49
      'Kaygı başarımı sabote eder.', // 50 (T)
      'Kaygı ile performans arasında denge kurabilirim.', // 51
      'Kaygı kontrolümden çıkar.', // 52 (T)
    ];

    final options = [
      'Hiç Uygun Değil',
      'Az Uygun',
      'Kısmen Uygun',
      'Oldukça Uygun',
      'Tamamen Uygun',
    ];

    return List.generate(questions.length, (i) {
      return SurveyQuestion(
        id: 'q${i + 1}',
        text: questions[i],
        type: SurveyQuestionType.singleChoice,
        isRequired: true,
        options: options,
      );
    });
  }
}
