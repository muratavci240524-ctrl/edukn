import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class TestTakingSkillsTest extends GuidanceTestDefinition {
  @override
  String get id => 'test_taking_skills_v1';

  @override
  String get title => 'Test Çözme Becerileri Ölçeği (TÇBÖ)';

  @override
  String get description =>
      'Bu ölçek akademik başarıyı değil, bireyin test ve sınav ortamlarında soruyu anlama, zaman yönetimi, strateji kullanma ve dikkatini sürdürme gibi becerilerini değerlendirmek amacıyla geliştirilmiştir. Ölçek tanı koymaz, tarama amaçlıdır.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'tcb_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Soru Anlama ve Yorumlama (1-6)
      'Soru kökünü ilk okumada anlayabilirim.', // 1
      'Uzun sorularda ne istendiğini kaçırırım.', // 2
      'Soruyu tam anlamadan işlem yapmaya başlarım.', // 3
      'Anahtar kelimelere dikkat ederim.', // 4 (Ters - Puanlama mantığına göre normal puanlanırsa terslenmeli mi? Kullanıcı listesinde 4 no'lu madde ters maddeler arasında)
      'Sorunun benden ne istediğini ayırt etmekte zorlanırım.', // 5
      'Aynı soruyu tekrar okuma ihtiyacı duyarım.', // 6
      // B) Zaman Yönetimi (7-12)
      'Testte zamanı yetiştirmekte zorlanırım.', // 7
      'Zor sorulara fazla vakit harcarım.', // 8
      'Hangi soruya ne kadar süre ayıracağımı bilirim.', // 9 (Ters)
      'Süre bitmeden teste dönüp kontrol yapabilirim.', // 10 (Ters)
      'Zaman baskısı hata yapmama neden olur.', // 11
      'Testin ortalarında zaman kontrolünü kaybederim.', // 12
      // C) Strateji Kullanımı (13-18)
      'Yapamadığım soruyu geçip sonra dönebilirim.', // 13 (Ters)
      'Şıkları eleyerek çözüm yaparım.', // 14 (Ters)
      'Tüm soruları sırayla çözmek zorunda hissederim.', // 15
      'Tahmin stratejilerini bilinçli kullanırım.', // 16 (Ters)
      'Strateji kullanmadan çözerim.', // 17
      'Deneme sınavlarında strateji değiştiririm.', // 18 (Ters olarak listelenmiş)
      // D) Dikkat ve Odaklanma (19-24)
      'Test sırasında dikkatim kolay dağılır.', // 19
      'Uzun süre aynı dikkati sürdürebilirim.', // 20 (Ters)
      'Küçük bir dikkat hatası zincirleme yanlışlara yol açar.', // 21
      'Testın sonlarına doğru dikkatim azalır.', // 22
      'Ortamda olan biten dikkatimi bozmaz.', // 23 (Ters)
      'Aynı soruda gereksiz tekrarlar yaparım.', // 24
      // E) Yanlışlarla Baş Etme (25-30)
      'Yanlış yaptığımı fark edince moralim bozulur.', // 25
      'Bir yanlış diğer sorularımı etkiler.', // 26
      'Yanlışı fark edip yoluma devam edebilirim.', // 27 (Ters)
      'Yanlışlar yüzünden hızım düşer.', // 28
      'Yanlış yaptığım soruya takılı kalırım.', // 29
      'Yanlışları sınavın doğal parçası olarak görürüm.', // 30 (Ters)
      // F) Sınav İçi Duygusal Kontrol (31-36)
      'Test sırasında heyecanımı yönetebilirim.', // 31 (Ters)
      'Sınav anında panik olurum.', // 32
      'Zor sorularla karşılaşınca içsel baskı yaşarım.', // 33
      'Duygularım düşünme hızımı etkiler.', // 34
      'Kendimi sakinleştirerek devam edebilirim.', // 35 (Ters)
      'Test çözerken iç konuşmalarım dikkatimi dağıtır.', // 36
      // G) Genel Test Çözme & Çeldirici Maddeler (37-48)
      'Test çözme konusunda kendime güvenirim.', // 37 (Çeldirici)
      'Genelde testlerde başarılıyımdır.', // 38 (Çeldirici)
      'Test çözme becerim gelişmeye açıktır.', // 39
      'Bazen bildiğim soruları bile yanlış yaparım.', // 40
      'Test çözme sürecini kontrol edemediğimi hissederim.', // 41
      'Deneme sınavlarında performansım dalgalıdır.', // 42
      'Test çözerken yaptığım hataların farkındayım.', // 43 (Ters)
      'Test çözme becerim bilgi düzeyimle örtüşmez.', // 44
      'Test çözme süreci beni zihinsel olarak yorar.', // 45
      'Test çözmeyi öğrenilmesi gereken bir beceri olarak görürüm.', // 46 (Ters)
      'Test çözerken kararsız kaldığım çok an olur.', // 47
      'Test çözme performansım sınavdan sınava değişir.', // 48
    ];

    final options = [
      'Hiç katılmıyorum',
      'Katılmıyorum',
      'Kararsızım',
      'Katılıyorum',
      'Tamamen katılıyorum',
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
