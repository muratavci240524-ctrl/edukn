import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class FailureFearPerformanceObstacleTest extends GuidanceTestDefinition {
  @override
  String get id => 'failure_fear_performance_obstacle_v1';

  @override
  String get title =>
      'Başarısızlık Korkusu ve Performans Engelleri Ölçeği (BK-PEÖ)';

  @override
  String get description =>
      'Bireyin başarısızlık korkusunu, performans anksiyetesini, kendini sabotaj ve kaçınma eğilimlerini analiz eder.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'fear_obstacle_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<Map<String, dynamic>> items = [
      // A) Başarısızlık Beklentisi (1-12)
      {'text': 'Başlamadan önce başarısız olacağımı düşünürüm.', 'type': 'L'},
      {'text': 'Çoğu denemenin kötü biteceğini varsayarım.', 'type': 'L'},
      {'text': 'Sonucun olumsuz olmasını beklerim.', 'type': 'L'},
      {'text': 'Hata yapma ihtimali beni çok rahatsız eder.', 'type': 'L'},
      {'text': 'Başarısızlık aklıma sık sık gelir.', 'type': 'L'},
      {'text': 'Sonuçlar genelde beklentilerimi karşılamaz.', 'type': 'L'},
      {'text': 'Olumsuz senaryolar zihnimi meşgul eder.', 'type': 'L'},
      {'text': 'Başarı ihtimalini düşük görürüm.', 'type': 'L'},
      {'text': 'İyi gidecek diye düşünmekte zorlanırım.', 'type': 'L'},
      {'text': 'Başarısızlık neredeyse kaçınılmaz gibi gelir.', 'type': 'L'},
      {'text': 'Sonucu düşünmek motivasyonumu düşürür.', 'type': 'L'},
      {'text': 'Olumsuzluğu önceden kabullenirim.', 'type': 'L'},

      // B) Performans Anksiyetesi (13-24)
      {'text': 'Sınav veya sunum anında zihnim donar.', 'type': 'L'},
      {'text': 'Bildiklerimi o an hatırlamakta zorlanırım.', 'type': 'L'},
      {'text': 'Performans gerektiren anlar beni gerer.', 'type': 'L'},
      {'text': 'Heyecanım kontrolümü zorlaştırır.', 'type': 'L'},
      {'text': 'Başkaların varlığı performansımı düşürür.', 'type': 'L'},
      {'text': 'Değerlendirilmek beni huzursuz eder.', 'type': 'L'},
      {'text': 'Performans anında bedensel gerginlik yaşarım.', 'type': 'L'},
      {'text': 'O anki stres düşünmemi engeller.', 'type': 'L'},
      {'text': 'Kendimi izleniyormuş gibi hissederim.', 'type': 'L'},
      {'text': 'Performans sırasında hata yapmaktan korkarım.', 'type': 'L'},
      {'text': 'Baskı altında verimim düşer.', 'type': 'L'},
      {'text': 'Performans anları beni kaçınmaya iter.', 'type': 'L'},

      // C) Kendini Sabotaj Eğilimi (25-36)
      {'text': 'Tam hazırlanmak yerine yarım bırakırım.', 'type': 'B'},
      {'text': 'Başarısızlığı önceden kabullenirim.', 'type': 'B'},
      {'text': 'Son anda çalışmayı bırakırım.', 'type': 'B'},
      {'text': '“Zaten olmayacak” diye düşünürüm.', 'type': 'B'},
      {'text': 'Elimden geleni yapmam.', 'type': 'B'},
      {'text': 'Başarı ihtimali arttıkça geri çekilirim.', 'type': 'B'},
      {'text': 'Kendime engel koyduğumu fark ederim.', 'type': 'B'},
      {'text': 'Bilinçli olmasa da kendimi durdururum.', 'type': 'B'},
      {'text': 'Potansiyelimi tam kullanmam.', 'type': 'B'},
      {'text': 'Bahaneler üretirim.', 'type': 'B'},
      {'text': 'Sonucu riske atarım.', 'type': 'B'},
      {'text': 'Kendi yoluma taş koyarım.', 'type': 'B'},

      // D) Kaçınma ve Erteleme Davranışları (37-46)
      {'text': 'Zor görevleri ertelerim.', 'type': 'B'},
      {'text': 'Başlamakta gecikirim.', 'type': 'B'},
      {'text': 'Yapmam gerekenlerden uzak dururum.', 'type': 'B'},
      {'text': 'Son ana bırakırım.', 'type': 'B'},
      {'text': 'Çalışmayı sürekli ötelerim.', 'type': 'B'},
      {'text': 'Zor konuları geçiştiririm.', 'type': 'B'},
      {'text': 'Kaçınmak rahatlatır gibi gelir.', 'type': 'B'},
      {'text': 'Sorumluluk almaktan kaçınırım.', 'type': 'B'},
      {'text': 'Yüzleşmek istemem.', 'type': 'B'},
      {'text': 'Başlamamak beni korur gibi hissettirir.', 'type': 'B'},

      // E) Potansiyeli Sınırlama Algısı (47-62)
      {
        'text': 'Gerçek kapasitemi göstermemek daha güvenli gelir.',
        'type': 'L',
      },
      {
        'text': 'Elimden geleni yaparsam beklenti artar diye düşünürüm.',
        'type': 'L',
      },
      {'text': 'Başarı beni zor durumda bırakabilir.', 'type': 'L'},
      {'text': 'Düşük performans beni korur.', 'type': 'L'},
      {'text': 'Yüksek başarı baskı yaratır.', 'type': 'L'},
      {'text': 'Beklentilerin artmasından çekinirim.', 'type': 'L'},
      {'text': 'Kendimi bilinçli olarak sınırlarım.', 'type': 'L'},
      {'text': 'Potansiyelimi saklamak daha rahat hissettirir.', 'type': 'L'},
      {'text': 'Başarı sorumluluk getirir.', 'type': 'L'},
      {'text': 'Düşük beklentiyle devam etmeyi tercih ederim.', 'type': 'L'},
      {'text': 'Yüksek performans risklidir.', 'type': 'L'},
      {'text': 'Kendimi geri çekmek güven verir.', 'type': 'L'},
      {'text': 'Parlamak istemem.', 'type': 'L'},
      {'text': 'Görünür olmak beni gerer.', 'type': 'L'},
      {'text': 'Başarıdan çok başarısızlıktan korkarım.', 'type': 'L'},
      {'text': 'Potansiyelimi kullanmak beni endişelendirir.', 'type': 'L'},
    ];

    final likertOptions = [
      'Hiç Uygun Değil',
      'Az Uygun',
      'Kısmen Uygun',
      'Oldukça Uygun',
      'Tamamen Uygun',
    ];

    final behaviorOptions = ['Hayır', 'Bazen', 'Evet'];

    return List.generate(items.length, (i) {
      final item = items[i];
      return SurveyQuestion(
        id: 'q${i + 1}',
        text: item['text'],
        type: SurveyQuestionType.singleChoice,
        isRequired: true,
        options: item['type'] == 'L' ? likertOptions : behaviorOptions,
      );
    });
  }
}
