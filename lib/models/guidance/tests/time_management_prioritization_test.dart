import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class TimeManagementPrioritizationTest extends GuidanceTestDefinition {
  @override
  String get id => 'time_management_prioritization_v1';

  @override
  String get title =>
      'Zaman Yönetimi ve Önceliklendirme Becerileri Ölçeği (ZYÖ-PBÖ)';

  @override
  String get description =>
      'Bireyin zaman farkındalığını, planlama kapasitesini ve zaman baskısını yönetme becerilerini analiz eder.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'time_mgmt_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<Map<String, dynamic>> items = [
      // A) Zaman Farkındalığı (1-10)
      {'text': 'Zamanın nasıl geçtiğinin farkındayım.'},
      {'text': 'Gün içinde zamanımı neye harcadığımı bilirim.'},
      {'text': 'Zamanı fark etmeden harcarım.', 'reverse': true}, // 3
      {'text': 'Günlük süremi bilinçli kullanırım.'},
      {'text': 'Zamanımı boşa harcadığımı fark ederim.'},
      {'text': 'Zamanın değerini yeterince önemsemem.', 'reverse': true}, // 6
      {'text': 'Hangi işin ne kadar süreceğini tahmin edebilirim.'},
      {'text': 'Süreleri hep yanlış hesaplarım.', 'reverse': true}, // 8
      {'text': 'Zaman kaybı yaşadığımı erken fark ederim.'},
      {'text': 'Günün nasıl geçtiğini anlamam.', 'reverse': true}, // 10
      // B) Planlama ve Programlama (11-20)
      {'text': 'Günlük plan yaparım.'},
      {'text': 'Haftalık programım vardır.'},
      {'text': 'Plansız hareket ederim.', 'reverse': true}, // 13
      {'text': 'Yapacaklarımı önceden belirlerim.'},
      {'text': 'Program yapıp uygulamam.', 'reverse': true}, // 15
      {'text': 'Çalışma zamanımı planlarım.'},
      {'text': 'Plan yapmayı gereksiz bulurum.', 'reverse': true}, // 17
      {'text': 'Programım bana yol gösterir.'},
      {'text': 'Planlarımı sık sık değiştiririm.', 'reverse': true}, // 19
      {'text': 'Planlı olmak işimi kolaylaştırır.'},

      // C) Önceliklendirme Becerisi (21-30)
      {'text': 'Öncelikli işlerimi ayırt edebilirim.'},
      {'text': 'Önemli ile acili karıştırırım.', 'reverse': true}, // 22
      {'text': 'Önce yapılması gerekeni bilirim.'},
      {'text': 'Kolay işleri öne alırım.', 'reverse': true}, // 24
      {'text': 'Zor ama önemli işleri ertelemem.'},
      {'text': 'Öncelik sırası belirlerim.'},
      {'text': 'Her işi aynı anda yapmaya çalışırım.', 'reverse': true}, // 27
      {'text': 'Öncelik belirlemek beni rahatlatır.'},
      {'text': 'Neyin önce yapılacağını bilemem.', 'reverse': true}, // 29
      {'text': 'Önemli işleri sona bırakırım.', 'reverse': true}, // 30
      // D) Erteleme Davranışı (31-40) - Note: higher score usually means BETTER mgmt, so reverse high erteleme
      {'text': 'Yapmam gereken işleri ertelerim.', 'reverse': true}, // 31
      {'text': 'Başlamakta zorlanırım.', 'reverse': true}, // 32
      {'text': 'Son ana bırakma alışkanlığım vardır.', 'reverse': true}, // 33
      {'text': 'İşe başlamak benim için kolaydır.'},
      {'text': 'Ertelemenin bana zarar verdiğini bilirim.'},
      {'text': 'Erteleme davranışım sık görülür.', 'reverse': true}, // 36
      {'text': 'Başladığım işi devam ettiririm.'},
      {'text': 'Canım istemediğinde işi bırakırım.', 'reverse': true}, // 38
      {'text': 'Kendimi oyaladığımı fark ederim.'},
      {'text': 'Erteleme alışkanlığım yoktur.'},

      // E) Zamanı Koruma ve Bölünme (41-50)
      {'text': 'Dikkatimi dağıtan şeyleri sınırlandırırım.'},
      {'text': 'Kolayca bölünürüm.', 'reverse': true}, // 42
      {'text': 'Telefon zamanımı kontrol edebilirim.'},
      {'text': 'Dikkatim çabuk dağılır.', 'reverse': true}, // 44
      {'text': 'Çalışırken bölünmemeye dikkat ederim.'},
      {'text': 'Sosyal medya zamanımı yönetemem.', 'reverse': true}, // 46
      {'text': 'Çalışma süremi korurum.'},
      {'text': 'Dış etkenler beni kolay etkiler.', 'reverse': true}, // 48
      {'text': 'Dikkatimi toparlamakta zorlanmam.'},
      {'text': 'Çalışma ortamımı düzenlerim.'},

      // F) Zaman Baskısıyla Baş Etme (51-66)
      {'text': 'Zaman baskısı beni tamamen kilitler.', 'reverse': true}, // 51
      {'text': 'Süre kısıtlıyken performansım düşer.', 'reverse': true}, // 52
      {'text': 'Zaman azaldığında panik yaparım.', 'reverse': true}, // 53
      {'text': 'Süre baskısıyla başa çıkabilirim.'},
      {'text': 'Zaman daraldıkça daha verimli olurum.'},
      {
        'text': 'Yetişmeyeceğini düşündüğümde vazgeçerim.',
        'reverse': true,
      }, // 56
      {'text': 'Zaman baskısını yönetebilirim.'},
      {'text': 'Süre beni kontrol eder.', 'reverse': true}, // 58
      {'text': 'Zamanla yarışırken plan yaparım.'},
      {'text': 'Zaman baskısı motivasyonumu düşürür.', 'reverse': true}, // 60
      {'text': 'Sıkışık zamanda doğru karar veririm.'},
      {'text': 'Süre beni telaşlandırır.', 'reverse': true}, // 62
      {'text': 'Zaman baskısını lehime çevirebilirim.'},
      {'text': 'Zaman daralınca hata yaparım.', 'reverse': true}, // 64
      {'text': 'Süreyi iyi kullanırım.'},
      {'text': 'Zaman yönetimi güçlü bir yönümdür.'},
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
