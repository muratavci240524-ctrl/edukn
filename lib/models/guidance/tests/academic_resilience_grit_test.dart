import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class AcademicResilienceGritTest extends GuidanceTestDefinition {
  @override
  String get id => 'academic_resilience_grit_v1';

  @override
  String get title => 'Akademik Dayanıklılık ve Vazgeçmeme Ölçeği (ADVÖ)';

  @override
  String get description =>
      'Bireyin zorluklara tepkisini, başarısızlık sonrası toparlanma hızını, ısrar ve sebat düzeyini değerlendirir.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'adv_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Zorluklara Psikolojik Tepki (1-14)
      'Zorlandığımda moralim çabuk bozulur.', // 1
      'Zor konular beni yıldırır.', // 2
      'Zorluklar beni motive eder.',
      'Baskı altında paniklerim.', // 4
      'Zorlandığımda sakin kalabilirim.',
      'Stres beni tamamen dağıtır.', // 6
      'Zor görevlerde kendime güvenirim.',
      'Zorlandığımda kontrolümü kaybederim.', // 8
      'Baskı altında düşünemez hale gelirim.', // 9
      'Zorluklarla başa çıkabileceğimi hissederim.',
      'Zorlanınca içsel gücümü kullanırım.',
      'Zorluk beni durdurur.', // 12
      'Baskı altında da işimi yapabilirim.',
      'Zor anlarda kendimi toparlayabilirim.',

      // B) Başarısızlık Sonrası Toparlanma (15-28)
      'Kötü not aldıktan sonra çalışmayı bırakırım.', // 15
      'Başarısızlık beni uzun süre etkiler.', // 16
      'Hatalarımdan ders çıkarırım.',
      'Başarısızlıktan sonra yeniden denerim.',
      'Kötü sonuçlar beni tamamen demoralize eder.', // 19
      'Başarısızlık beni geliştirir.',
      'Yanlışlarımı analiz ederim.',
      'Hata yapınca kendimi suçlarım.', // 22
      'Düşünce biçimimi değiştirebilirim.',
      'Başarısızlık sonrası hızla toparlanırım.',
      'Kötü sonuçtan sonra vazgeçerim.', // 25
      'Hatalar öğrenme fırsatıdır.',
      'Başarısızlıktan sonra çaba gösteririm.',
      'Bir hata her şeyi bitirir.', // 28
      // C) Israr ve Sebat Davranışı (29-42)
      'Zor da olsa devam ederim.',
      'Başladığım işi bitiririm.',
      'Kolay vazgeçmem.',
      'Uzun süre çaba gösterebilirim.',
      'Sabırlıyımdır.',
      'Tekrar tekrar denemekten kaçınmam.',
      'Zor görevlerde sebat ederim.',
      'Dirençliyimdir.',
      'Uzun vadeli hedeflerim için çalışırım.',
      'Çabamı sürdürebilirim.',
      'Israrcıyımdır.',
      'Zorlandıkça bırakırım.', // 40
      'Süreklilik göstermek zordur.', // 41
      'Dayanıklıyımdır.',

      // D) Pes Etme Eğilimi (43-56)
      'Zorlanınca bırakmayı düşünürüm.', // 43
      'Çabuk vazgeçerim.',
      'Mücadele etmek bana zor gelir.',
      'Pes etmeye yatkınımdır.',
      'Direnmektense bırakırım.',
      'İlk engelde vazgeçerim.',
      'Kolayı tercih ederim.',
      'Mücadele etmekten kaçınırım.', // 50
      'Sabırsızım.',
      'Dayanmakta zorlanırım.',
      'Zorluklar beni durdurur.',
      'Çabayı sürdüremem.',
      'Direnç göstermek bana göre değildir.',
      'Zorluklar karşısında geri çekilirim.', // 56
    ];

    final options = [
      'Hiç Uygun Değil',
      'Biraz Uygun',
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
