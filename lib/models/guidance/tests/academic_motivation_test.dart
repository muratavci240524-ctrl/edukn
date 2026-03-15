import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class AcademicMotivationTest extends GuidanceTestDefinition {
  @override
  String get id => 'academic_motivation_v1';

  @override
  String get title => 'Akademik Motivasyon Türleri Ölçeği (AMTÖ)';

  @override
  String get description =>
      'Bu ölçek; bireyin akademik çalışmalara yönelmesinin temel motivasyon kaynaklarını belirler. İçsel ilgi, dışsal baskı ve kaçınma stratejilerini analiz ederek çalışma davranışının sürdürülebilirliğini değerlendirmeyi amaçlar.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'amt_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) İçsel Motivasyon (1-10)
      'Öğrenmek bana kendimi iyi hissettirir.',
      'Bazı dersleri not olmasa bile çalışmak isterim.',
      'Yeni bir konuyu anlamak beni heyecanlandırır.',
      'Başardığımda sadece not değil, tatmin de hissederim.',
      'Merak ettiğim konular için ekstra araştırma yaparım.',
      'Öğrenmenin kendisi benim için değerlidir.',
      'Çalışırken zamanın nasıl geçtiğini fark etmem.',
      'Sınav için değil, anlamak için çalışırım.',
      'Bir konuyu başkalarına anlatabilmek beni mutlu eder.',
      'Öğrendiklerimin işe yarayacağını düşünürüm.',

      // B) Dışsal Motivasyon (Ödül - Ceza) (11-20)
      'Notlarım iyi olursa ailem mutlu olduğu için çalışırım.',
      'Ceza almamak için ders çalışırım.',
      'Takdir edilmek benim için güçlü bir motivasyondur.',
      'Başkalarının beni başarılı görmesini isterim.',
      'Ödül olmasa çalışma isteğim azalır.',
      'Ailem kızmasın diye çalışırım.',
      'Öğretmenlerin gözünde iyi görünmek benim için önemlidir.',
      'Başkaları fark etmeyecekse çalışmak anlamsız gelir.',
      'Çalışmamın nedeni çoğunlukla dış beklentilerdir.',
      'Takdir edilmezsem isteğim düşer.',

      // C) Kaçınma Motivasyonu (21-30)
      'Başarısız olmamak için çalışırım.',
      'Kötü not almamak benim için iyi not almaktan daha önemlidir.',
      'Eleştirilmemek için ders çalışırım.',
      'Çalışmazsam olacakları düşündüğüm için çalışırım.',
      'Utanacağım durumlardan kaçınmak için çaba gösteririm.',
      'Başarısızlık korkusu beni çalışmaya iter.',
      'Çalışmamın temelinde kaygı vardır.',
      'Genelde “kötü olmasın yeter” diye düşünürüm.',
      'Risk almaktansa garantiye oynamayı tercih ederim.',
      'Hata yapmamak için aşırı dikkatli olurum.',

      // D) Zorunluluk / Baskı Motivasyonu (31-40)
      'Ders çalışmak benim için bir zorunluluktur.',
      'Çalışmazsam kendimi suçlu hissederim.',
      'Ders çalışmayı görev gibi görürüm.',
      'İstemesem de yapmak zorunda olduğumu hissederim.',
      'Akademik çalışmalar beni yorar ama mecburum.',
      'Çalışmayı bırakmak içimi rahatlatırdı.',
      'Çalışmak benim seçimim gibi gelmez.',
      'Dersler hayatımda baskı kaynağıdır.',
      'Çalışmayı çoğunlukla isteksiz yaparım.',
      'Ders çalışmak beni tüketir.',

      // E) Motivasyon Farkındalığı (41-52)
      'Neden çalıştığımı net olarak biliyorum.',
      'Motivasyonumun zamanla değiştiğini fark ediyorum.',
      'Bazı dönemler isteyerek, bazı dönemler mecburen çalışırım.',
      'Hangi derslerde neden zorlandığımı biliyorum.',
      'Çalışma isteğimin arkasındaki duyguları ayırt edebilirim.',
      'Motivasyonum genellikle tek bir nedene dayanmaz.',
      'Bazen neden çalıştığımı sorgularım.',
      'Motivasyonum dış etkenlere çok bağlıdır.',
      'İçsel isteğimle dış baskıyı ayırt edebilirim.',
      'Motivasyonumun sürdürülebilir olup olmadığını düşünürüm.',
      'Çalışmamın altında yatan asıl nedeni netleştirmem gerekir.',
      'Motivasyonumun beni ne kadar ileri götüreceğini merak ederim.',
    ];

    final options = ['Evet', 'Hayır'];

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
