import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class AcademicSelfEfficacyPerceptionTest extends GuidanceTestDefinition {
  @override
  String get id => 'academic_self_efficacy_perception_v1';

  @override
  String get title => 'Akademik Öz Yeterlik Algısı Ölçeği (AÖ-YAÖ)';

  @override
  String get description =>
      'Bireyin akademik görevleri yapabilme inancını, zorluklarla başa çıkma güvenini ve kontrol algısını analiz eder.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'self_efficacy_perception_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<Map<String, dynamic>> items = [
      // A) Akademik Görevleri Yapabilme İnancı (1-10)
      {'text': 'Derslerde verilen görevleri yapabileceğime inanırım.'},
      {'text': 'Çoğu akademik görev bana ağır gelir.', 'reverse': true}, // 2
      {'text': 'İstersem zor konuları anlayabilirim.'},
      {'text': 'Akademik işler bana göre değildir.', 'reverse': true}, // 4
      {'text': 'Çalışınca başarılı olabileceğimi bilirim.'},
      {
        'text': 'Derslerde genellikle yetersiz hissederim.',
        'reverse': true,
      }, // 6
      {'text': 'Kendime güvenim vardır.'},
      {'text': 'Yapamayacağımı düşünerek başlamam.', 'reverse': true}, // 8
      {'text': 'Akademik görevlerin altından kalkabilirim.'},
      {'text': 'Çoğu derste zorlanırım.', 'reverse': true}, // 10
      // B) Zorlanma Karşısında Kendine Güven (11-20)
      {'text': 'Zorlandığımda çözüm bulabilirim.'},
      {'text': 'Zorluklar beni durdurur.', 'reverse': true}, // 12
      {'text': 'Zor sorularla baş edebilirim.'},
      {'text': 'Zorlanınca kendime güvenim azalır.', 'reverse': true}, // 14
      {'text': 'Emek verirsem başarırım.'},
      {'text': 'Zorlanmak beni korkutur.', 'reverse': true}, // 16
      {'text': 'Sabırlı davranabilirim.'},
      {'text': 'Zor görevlerden kaçınırım.', 'reverse': true}, // 18
      {'text': 'Zorluk beni tamamen durdurmaz.'},
      {'text': 'Zorlanınca vazgeçerim.', 'reverse': true}, // 20
      // C) Başarısızlıkla Başa Çıkma Algısı (21-30)
      {'text': 'Başarısızlık beni geliştirir.'},
      {
        'text': 'Başarısız olunca kendimi yetersiz görürüm.',
        'reverse': true,
      }, // 22
      {'text': 'Hatalarımdan öğrenebilirim.'},
      {'text': 'Başarısızlık beni uzun süre etkiler.', 'reverse': true}, // 24
      {'text': 'Tekrar denemekten çekinmem.'},
      {
        'text': 'Başarısızlık beni tamamen demotive eder.',
        'reverse': true,
      }, // 26
      {'text': 'Hatalar sürecin parçasıdır.'},
      {'text': 'Yanlış yapmak beni korkutur.', 'reverse': true}, // 28
      {'text': 'Başarısızlıktan sonra toparlanabilirim.'},
      {'text': 'Başarısızlık özgüvenimi sarsar.', 'reverse': true}, // 30
      // D) Öğrenme Sürecine Güven (31-40)
      {'text': 'Öğrenebileceğime inanırım.'},
      {'text': 'Öğrenmek benim için zordur.', 'reverse': true}, // 32
      {'text': 'Anlamadığım konuları zamanla öğrenebilirim.'},
      {'text': 'Bazı şeyleri asla öğrenemem.', 'reverse': true}, // 34
      {'text': 'Öğrenme kapasiteme güvenirim.'},
      {'text': 'Konular kafamda karışır.', 'reverse': true}, // 36
      {'text': 'Öğrenme sürecinde ilerleyebilirim.'},
      {'text': 'Öğrenme bana göre değildir.', 'reverse': true}, // 38
      {'text': 'Zamanla gelişebileceğime inanırım.'},
      {'text': 'Öğrenmek beni zorlar.', 'reverse': true}, // 40
      // E) Kıyas ve Sosyal Karşılaştırma Etkisi (41-50)
      {'text': 'Kendimi başkalarıyla kıyaslarım.', 'reverse': true}, // 41
      {
        'text': 'Başkalarının başarısı beni olumsuz etkiler.',
        'reverse': true,
      }, // 42
      {'text': 'Kendi gelişimime odaklanırım.'},
      {'text': 'Başkaları benden daha yeteneklidir.', 'reverse': true}, // 44
      {'text': 'Kendi hızımda ilerleyebilirim.'},
      {'text': 'Başkalarının başarısı beni yıldırır.', 'reverse': true}, // 46
      {'text': 'Herkesin farklı olduğunu bilirim.'},
      {'text': 'Kendimi yetersiz hissederim.', 'reverse': true}, // 48
      {'text': 'Kıyaslamadan çalışabilirim.'},
      {'text': 'Sürekli kendimi geride hissederim.', 'reverse': true}, // 50
      // F) Akademik Kontrol Algısı (51-60)
      {'text': 'Başarım büyük ölçüde bana bağlıdır.'},
      {'text': 'Ne yaparsam yapayım sonuç değişmez.', 'reverse': true}, // 52
      {'text': 'Çabamın karşılığını alırım.'},
      {'text': 'Başarı şansa bağlıdır.', 'reverse': true}, // 54
      {'text': 'Kontrol bendedir.'},
      {'text': 'Sonuçları etkileyemem.', 'reverse': true}, // 56
      {'text': 'Çalışma biçimim sonucu belirler.'},
      {'text': 'Başarı dış etkenlere bağlıdır.', 'reverse': true}, // 58
      {'text': 'Kendi sürecimi yönetebilirim.'},
      {'text': 'Akademik kontrol bana ait değildir.', 'reverse': true}, // 60
    ];

    final options = [
      'Kesinlikle Katılmıyorum',
      'Katılmıyorum',
      'Kararsızım',
      'Katılıyorum',
      'Kesinlikle Katılıyorum',
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
