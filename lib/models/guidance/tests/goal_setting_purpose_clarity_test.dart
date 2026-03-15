import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class GoalSettingPurposeClarityTest extends GuidanceTestDefinition {
  @override
  String get id => 'goal_setting_purpose_clarity_v1';

  @override
  String get title => 'Hedef Belirleme ve Amaç Netliği Ölçeği (HB-ANÖ)';

  @override
  String get description =>
      'Bireyin hedef belirleme becerisini, hedeflerinin gerçekçiliğini ve hedefe bağlılığını analiz eder.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'goal_clarity_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<Map<String, dynamic>> items = [
      // A) Hedef Netliği (1-12)
      {'text': 'Akademik hedeflerim nettir.'},
      {'text': 'Ne istediğimi açıkça biliyorum.'},
      {'text': 'Hedeflerim belirsizdir.', 'reverse': true}, // 3
      {'text': 'Geleceğimle ilgili net bir yönüm var.'},
      {'text': 'Ne için çalıştığımı bilirim.'},
      {'text': 'Amaçlarım kafamda karışıktır.', 'reverse': true}, // 6
      {'text': 'Hedeflerimi açıkça ifade edebilirim.'},
      {'text': 'Çoğu zaman neye odaklanacağımı bilemem.', 'reverse': true}, // 8
      {'text': 'Akademik olarak ulaşmak istediğim nokta bellidir.'},
      {'text': 'Hedeflerim sık sık değişir.', 'reverse': true}, // 10
      {'text': 'Önceliklerim nettir.'},
      {
        'text': 'Ne yapmam gerektiği konusunda kararsız kalırım.',
        'reverse': true,
      }, // 12
      // B) Hedef Gerçekçiliği (13-22)
      {'text': 'Hedeflerim ulaşılabilir düzeydedir.'},
      {'text': 'Kendime uygun hedefler koyarım.'},
      {
        'text': 'Hedeflerim çoğu zaman gerçekçi değildir.',
        'reverse': true,
      }, // 15
      {'text': 'Kapasitemi dikkate alırım.'},
      {'text': 'Aşırı yüksek hedefler koyarım.', 'reverse': true}, // 17
      {'text': 'Şartları göz önünde bulundururum.'},
      {'text': 'Hedeflerimi imkanlarıma göre belirlerim.'},
      {'text': 'Gerçeklerden kopuk hedeflerim vardır.', 'reverse': true}, // 20
      {'text': 'Hedeflerim beni zorlar ama ulaşılabilirdir.'},
      {
        'text': 'Kendime uygun olmayan hedefler seçerim.',
        'reverse': true,
      }, // 22
      // C) Kısa–Uzun Vadeli Planlama (23-33)
      {'text': 'Kısa vadeli hedeflerim vardır.'},
      {'text': 'Uzun vadeli hedeflerim nettir.'},
      {'text': 'Sadece anı düşünürüm.', 'reverse': true}, // 25
      {'text': 'Geleceği planlamayı önemserim.'},
      {'text': 'Günlük hedefler koyarım.'},
      {'text': 'Uzun vadeli düşünmek bana zor gelir.', 'reverse': true}, // 28
      {'text': 'Hedeflerimi zamana yayabilirim.'},
      {'text': 'Hep son ana bırakırım.', 'reverse': true}, // 30
      {'text': 'Planlı ilerlerim.'},
      {'text': 'Hedeflerimi parçalara ayırırım.'},
      {'text': 'Geleceğe dair düşünmekten kaçınırım.', 'reverse': true}, // 33
      // D) Hedef–Eylem Bağlantısı (34-43)
      {'text': 'Hedeflerim için ne yapmam gerektiğini bilirim.'},
      {'text': 'Hedef koyarım ama adım atmam.', 'reverse': true}, // 35
      {'text': 'Hedeflerimi davranışa dönüştürebilirim.'},
      {'text': 'Söylediklerimle yaptıklarım örtüşür.'},
      {'text': 'Hedeflerim sadece düşüncede kalır.', 'reverse': true}, // 38
      {'text': 'Günlük çalışmalarım hedeflerimle ilişkilidir.'},
      {'text': 'Hedeflerim eylemlerimi yönlendirir.'},
      {
        'text': 'Hedefle davranış arasında kopukluk vardır.',
        'reverse': true,
      }, // 41
      {'text': 'Ne yapacağımı planlarım.'},
      {'text': 'Hedeflerim kararlarımı etkiler.'},

      // E) Hedefe Bağlılık ve Sürdürme (44-62)
      {'text': 'Hedeflerime bağlı kalırım.'},
      {'text': 'Zorlanınca hedeflerimden vazgeçerim.', 'reverse': true}, // 45
      {'text': 'Hedeflerim için çaba göstermeyi sürdürürüm.'},
      {'text': 'İlk engelde geri çekilirim.', 'reverse': true}, // 47
      {'text': 'Hedeflerim beni motive eder.'},
      {'text': 'Süreklilik sağlamakta zorlanırım.', 'reverse': true}, // 49
      {'text': 'Başladığım hedefi bitirmeye çalışırım.'},
      {'text': 'Hedeflerimi sık sık yarıda bırakırım.', 'reverse': true}, // 51
      {'text': 'Kararlıyımdır.'},
      {
        'text': 'Zorluklar beni hedefimden uzaklaştırır.',
        'reverse': true,
      }, // 53
      {'text': 'Hedefime ulaşmak için sabırlıyım.'},
      {'text': 'Vazgeçme eğilimim yüksektir.', 'reverse': true}, // 55
      {'text': 'Hedeflerimle aramda güçlü bir bağ vardır.'},
      {'text': 'Uzun vadede hedefimi korurum.'},
      {'text': 'Hedefe bağlılığım çabuk zayıflar.', 'reverse': true}, // 58
      {'text': 'Hedeflerime sahip çıkarım.'},
      {'text': 'Başladığım işi tamamlamaya önem veririm.'},
      {'text': 'Hedeflerim beni yönlendirir.'},
      {'text': 'Vazgeçmek benim için kolaydır.', 'reverse': true}, // 62
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
