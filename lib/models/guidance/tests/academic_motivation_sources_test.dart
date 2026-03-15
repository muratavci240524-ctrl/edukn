import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class AcademicMotivationSourcesTest extends GuidanceTestDefinition {
  @override
  String get id => 'academic_motivation_sources_v1';

  @override
  String get title => 'Motivasyon Kaynakları Ölçeği (MKÖ)';

  @override
  String get description =>
      'Bireyin içsel ve dışsal motivasyon kaynaklarını, amaç-anlam ilişkisini ve motivasyon kırılganlığını analiz eder.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'motivation_sources_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<Map<String, dynamic>> items = [
      // A) İçsel Motivasyon (1-13)
      {'text': 'Öğrenmek bana keyif verir.'},
      {'text': 'Yeni bir şey öğrendiğimde içsel bir tatmin yaşarım.'},
      {'text': 'Sadece not için çalışırım.', 'reverse': true}, // 3
      {'text': 'Bir konuyu merak ettiğim için çalışırım.'},
      {'text': 'Anlamadığım konular ilgimi çeker.'},
      {'text': 'Öğrenme süreci benim için değerlidir.'},
      {'text': 'Çalışmak bana anlamsız gelir.', 'reverse': true}, // 7
      {'text': 'Başkası söylemese de çalışabilirim.'},
      {'text': 'Kendimi geliştirmek hoşuma gider.'},
      {'text': 'Dersler bana sıkıcı gelir.', 'reverse': true}, // 10
      {'text': 'Bilgi edinmek beni motive eder.'},
      {'text': 'Öğrenmenin kendisi benim için ödüldür.'},
      {'text': 'Çalışma isteğim içimden gelir.'},

      // B) Dışsal Motivasyon (Ödül–Ceza) (14-25)
      {'text': 'Not alacağımı bilirsem daha çok çalışırım.'},
      {'text': 'Ödül yoksa motive olamam.', 'reverse': true}, // 15
      {'text': 'Ailem memnun olsun diye çalışırım.'},
      {'text': 'Ceza ihtimali beni harekete geçirir.'},
      {'text': 'Takdir edilmek benim için önemlidir.'},
      {'text': 'Kimse kontrol etmese çalışmam.', 'reverse': true}, // 19
      {'text': 'Övgü aldığımda daha çok çaba gösteririm.'},
      {'text': 'Başkalarının beklentileri beni yönlendirir.'},
      {'text': 'Ödül olmazsa isteğim düşer.', 'reverse': true}, // 22
      {'text': 'Ceza korkusu beni çalıştırır.'},
      {'text': 'Dış baskı olmadan çalışmak zordur.', 'reverse': true}, // 24
      {'text': 'Notlarım başkaları için önemlidir.'},

      // C) Amaç ve Anlam Bağlantısı (26-37)
      {'text': 'Çalıştıklarımın geleceğimle bağlantısını görürüm.'},
      {'text': 'Derslerin hayatımla ilgisi yoktur.', 'reverse': true}, // 27
      {'text': 'Yaptığım çalışmaların bir amacı vardır.'},
      {'text': 'Neden çalıştığımı bilirim.'},
      {'text': 'Gelecek hedeflerim beni motive eder.'},
      {'text': 'Çalışmanın anlamını sorgularım.', 'reverse': true}, // 31
      {'text': 'Akademik hedeflerim nettir.'},
      {'text': 'Derslerin beni nereye götürdüğünü görürüm.'},
      {
        'text': 'Amaçsız çalışıyormuşum gibi hissederim.',
        'reverse': true,
      }, // 34
      {'text': 'Hedeflerim motivasyonumu artırır.'},
      {'text': 'Uzun vadeli düşünürüm.'},
      {
        'text': 'Çalışmalarımın boşa gittiğini düşünürüm.',
        'reverse': true,
      }, // 37
      // D) Motivasyon Sürekliliği (38-48)
      {'text': 'Başladıktan sonra devam edebilirim.'},
      {'text': 'Motivasyonum çabuk düşer.', 'reverse': true}, // 39
      {'text': 'Uzun süreli çalışmalarda istikrar sağlayabilirim.'},
      {'text': 'İlk hevesim çabuk söner.', 'reverse': true}, // 41
      {'text': 'Zorluklara rağmen motivasyonumu korurum.'},
      {'text': 'Kısa sürede sıkılırım.', 'reverse': true}, // 43
      {'text': 'Motivasyonumun kendim yeniden yükseltebilirim.'},
      {'text': 'Süreklilik benim için zordur.', 'reverse': true}, // 45
      {'text': 'Düzenli çalışmayı sürdürebilirim.'},
      {'text': 'Motivasyonum dalgalıdır.', 'reverse': true}, // 47
      {'text': 'Uzun vadede istikrarlı olabilirim.'},

      // E) Motivasyon Kırılganlığı (49-65) - Normal scoring (Higher = more fragile)
      {'text': 'Küçük bir olumsuzluk motivasyonumu düşürür.'},
      {'text': 'Eleştiri beni çalışmaktan soğutur.'},
      {'text': 'Başarısızlık isteğimi kırar.'},
      {'text': 'Moral bozukluğu motivasyonumu bitirir.'},
      {'text': 'Zorlanınca hevesim kaçar.'},
      {'text': 'Dış etkenler motivasyonumu çok etkiler.'},
      {'text': 'Motivasyonum kolay sarsılır.'},
      {'text': 'Küçük engeller beni durdurur.'},
      {'text': 'Olumsuzluklar beni uzun süre etkiler.'},
      {'text': 'Hata yapmak beni geri çeker.'},
      {'text': 'Başkalarının tutumu isteğimi belirler.'},
      {'text': 'Motivasyonum kırılgandır.'},
      {'text': 'Başarısızlık sonrası toparlanmakta zorlanırım.'},
      {'text': 'Çevresel etkilere çok bağlıyımdır.'},
      {'text': 'Moral bozulunca çalışamam.'},
      {'text': 'Küçük başarılar bile motivasyonumu etkiler.'},
      {'text': 'Motivasyonum dış faktörlere bağlıdır.'},
    ];

    final options = [
      'Hiç Uygun Değil',
      'Az Uygun',
      'Kısmen Uygun',
      'Oldukça Uygun',
      'Tamamen Uygun',
    ];

    return List.generate(items.length, (i) {
      final item = items[i];
      return SurveyQuestion(
        id: 'q${i + 1}',
        text: item['text'],
        type: SurveyQuestionType.singleChoice,
        isRequired: true,
        options: options,
      );
    });
  }
}
