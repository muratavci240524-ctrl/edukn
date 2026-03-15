import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class AttentionFocusTest extends GuidanceTestDefinition {
  @override
  String get id => 'attention_focus_v1';

  @override
  String get title => 'Dikkat ve Odaklanma Becerisi Ölçeği (DOBÖ)';

  @override
  String get description =>
      'Bu ölçek bireyin dikkatini başlatma, sürdürme, zihinsel kontrol ve dikkat dağıtıcılarla baş etme becerilerini değerlendirir. Günlük ve akademik işlevsellikteki dikkat örüntülerini ortaya koyar.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'dobo_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Dikkati Başlatma (1-7)
      'Bir işe başlamam gerektiğinde zihinsel olarak hazırlanırım.', // 1 (Ters)
      'Yapmam gereken işe başlamakta zorlanırım.', // 2
      'Dikkatimi toplamam zaman alır.', // 3
      'Başlamak için uygun anı beklerim.', // 4
      'Göreve başlama konusunda isteksizlik yaşarım.', // 5
      'Başladığımda odaklanmam genelde kolay olur.', // 6 (Ters)
      'Başlama sürecim günlere göre değişir.', // 7 (Çeldirici)
      // B) Dikkati Sürdürme (8-14)
      'Bir işe başladıktan sonra dikkatimi uzun süre koruyabilirim.', // 8 (Ters)
      'Çalışırken zihnim sık sık başka şeylere kayar.', // 9
      'Uzun süren görevlerde çabuk yorulurum.', // 10
      'Dikkatimi dağıtan düşüncelerle baş etmekte zorlanırım.', // 11
      'Görev ilerledikçe dikkatim artar.', // 12 (Ters)
      'Dikkatim genellikle görevin ortasında düşer.', // 13
      'Bazı işlerde çok iyi odaklanırken bazılarında zorlanırım.', // 14 (Çeldirici)
      // C) Dikkat Dağıtıcılarla Baş Etme (15-21)
      'Ortam sesleri dikkatim kolayca dağıtır.', // 15
      'Telefon, mesaj veya bildirimler odaklanmamı bozar.', // 16
      'Dikkatimi dağıtan unsurları kontrol altına alabilirim.', // 17 (Ters)
      'Küçük uyaranlar bile odağımı böler.', // 18
      'Dikkat dağıtıcılar olsa bile görevime devam edebilirim.', // 19 (Ters)
      'Dikkatimi dağıtan şeyleri fark ederim ama engelleyemem.', // 20
      'Ortam değiştiğinde dikkat düzeyim belirgin şekilde değişir.', // 21 (Çeldirici)
      // D) Zihinsel Dayanıklılık (22-27)
      'Uzun süre zihinsel çaba gerektiren işlerde dayanıklıyımdır.', // 22 (Ters)
      'Zihinsel olarak çabuk yorulurum.', // 23
      'Yorulsam bile dikkatimi toplamaya devam edebilirim.', // 24 (Ters)
      'Zihinsel yorgunluk dikkatimi hızla düşürür.', // 25
      'Zor görevlerde odağım çabuk dağılır.', // 26
      'Zihinsel performansım gün içinde dalgalanır.', // 27 (Çeldirici)
      // E) Odaklanma Esnekliği (28-33)
      'Dikkatimi gerektiğinde farklı görevlere yönlendirebilirim.', // 28 (Ters)
      'Bir görevden diğerine geçerken zorlanırım.', // 29
      'Odaklandığım bir işi bırakmak benim için zordur.', // 30
      'Dikkatimi yeniden toparlamakta güçlük çekerim.', // 31
      'Kısa molalar odağımı artırır.', // 32 (Ters)
      'Odaklanma biçimim göreve göre değişir.', // 33 (Çeldirici)
      // F) Genel & Çeldirici Maddeler (34-45)
      'Dikkatimin güçlü olduğunu düşünürüm.', // 34 (Çeldirici)
      'Odaklanma sorunu yaşadığımı düşünmüyorum.', // 35 (Çeldirici)
      'Dikkat düzeyim ortam ve zamana göre değişir.', // 36
      'Bazen çok iyi odaklanır, bazen hiç odaklanamam.', // 37
      'Dikkatimi kontrol edebildiğimi hissederim.', // 38 (Ters)
      'Odaklanma becerilerim geliştirilebilir.', // 39 (Ters)
      'Dikkat sorunlarımın nedenleri benim için net değildir.', // 40
      'Odaklanma düzeyim yapılan işe göre değişir.', // 41 (Çeldirici)
      'Dikkat gerektiren işlerden kaçınırım.', // 42
      'Odaklanmak benim için çaba gerektirir.', // 43
      'Zaman baskısı dikkatimi artırır.', // 44 (Çeldirici)
      'Dikkatimi bilinçli olarak yönlendirebilirim.', // 45 (Ters)
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
