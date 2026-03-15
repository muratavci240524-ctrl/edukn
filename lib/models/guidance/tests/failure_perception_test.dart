import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class FailurePerceptionTest extends GuidanceTestDefinition {
  @override
  String get id => 'failure_perception_v1';

  @override
  String get title => 'Başarısızlık Algısı ve Hata Toleransı Ölçeği (BAHTÖ)';

  @override
  String get description =>
      'Bu ölçek; bireyin hata yapma, başarısız olma ve olumsuz sonuçlarla karşılaşma durumlarına verdiği tepkileri değerlendirir. Başarısızlığın bir tehdit mi yoksa öğrenme fırsatı mı olarak görüldüğünü analiz etmeyi amaçlar.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'fp_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Başarısızlığı Tehdit Olarak Algılama (1-12)
      'Başarısız olmak benim için çok yıkıcıdır.',
      'Hata yaptığımda kendimi değersiz hissederim.',
      'Başarısızlık benim kimliğimi etkiler.',
      'Yanlış yapınca uzun süre etkisinden çıkamam.',
      'Başarısızlık benim için utanç vericidir.',
      'Hata yaptığımda herkesin bunu fark ettiğini düşünürüm.',
      'Başarısız olursam insanlar beni küçümser.',
      'Hatalar kişiliğim hakkında çok şey söyler.',
      'Başarısızlık beni geri çeker.',
      'Yanlış yapmak beni durdurur.',
      'Başarısızlık benim için tehdittir.',
      'Küçük hatalar bile beni rahatsız eder.',

      // B) Hata Toleransı (13-24)
      'Hata yapmak öğrenmenin bir parçasıdır.',
      'Yanlışlarımı sakinlikle değerlendirebilirim.',
      'Hata yaptığımda kendime sert davranırım.',
      'Yanlışlarımı telafi edebileceğime inanırım.',
      'Başarısızlık beni yıldırmaz.',
      'Yanlış yapınca paniklerim.',
      'Hata yapma ihtimali beni gerer.',
      'Hata yapabilirim, bu normaldir.',
      'Yanlışlarımı kabullenmekte zorlanırım.',
      'Hatalardan ders çıkarmayı bilirim.',
      'Hata yapmak beni korkutmaz.',
      'Yanlış yaptığımda hemen vazgeçerim.',

      // C) Kaçınma ve Riskten Uzak Durma (25-36)
      'Hata yapma ihtimali varsa başlamam.',
      'Zor sorulardan kaçınırım.',
      'Yapamayacağımı düşündüğüm şeyleri ertelerim.',
      'Risk almak beni huzursuz eder.',
      'Başarısız olmaktansa denememeyi tercih ederim.',
      'Hata yapmamak için az şey yaparım.',
      'Yeni yöntemler denemekten kaçınırım.',
      'Yanlış yapabileceğim durumları ertelerim.',
      'Güvende hissetmezsem çalışmam.',
      'Başarısız olabileceğim işlerden uzak dururum.',
      'Hata ihtimali motivasyonumu düşürür.',
      'Kolay olanı seçerim.',

      // D) Toparlanma ve Psikolojik Dayanıklılık (37-52)
      'Başarısızlıktan sonra tekrar toparlanırım.',
      'Hata yapsam da yoluma devam ederim.',
      'Başarısızlık beni güçlendirir.',
      'Olumsuz sonuçlardan sonra yeniden denerim.',
      'Başarısızlık geçicidir.',
      'Yanlışlar beni geliştirebilir.',
      'Başarısızlıktan sonra kendime zaman tanırım.',
      'Bir hatadan sonra uzun süre kendime gelemezim.',
      'Başarısızlık beni kilitler.',
      'Hata yaptıktan sonra motive olmakta zorlanırım.',
      'Tekrar denemek bana zor gelir.',
      'Başarısızlık beni durdurmaz.',
      'Olumsuz sonuçları yönetebilirim.',
      'Hata sonrası soğukkanlı kalırım.',
      'Başarısızlık beni tanımlamaz.',
      'Hata yaptıktan sonra daha bilinçli olurum.',
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
