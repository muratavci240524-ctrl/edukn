import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class AcademicResilienceTest extends GuidanceTestDefinition {
  @override
  String get id => 'academic_resilience_v1';

  @override
  String get title => 'Akademik Dayanıklılık Ölçeği (ADÖ)';

  @override
  String get description =>
      'Bu ölçek; bireyin akademik zorluklar karşısında devam edebilme, hata sonrası toparlanma ve akademik süreçlerdeki psikolojik esneklik düzeyini değerlendirir. Zorluklarla karşılaşıldığında verilen tepki örüntülerini ortaya koymayı amaçlar.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'ado_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Zorluk Karşısında Devam Etme (1-8)
      'Zor bir dersle karşılaştığımda çalışmayı bırakırım.', // 1
      'Akademik olarak zorlandığımda devam etmekte güçlük çekerim.', // 2
      'Zor konular beni çalışmaktan soğutur.', // 3
      'Zorlandığımda başka derslere yönelirim.', // 4
      'Zor bir görev beni daha çok motive eder.', // 5 (Ters)
      'Akademik zorluklar karşısında çabuk vazgeçerim.', // 6
      'Zor bir sürecin geçici olabileceğini düşünürüm.', // 7 (Ters)
      'Zorlandığım derslerde genellikle geri çekilirim.', // 8
      // B) Hata Sonrası Toparlanma (9-16)
      'Hata yaptığımda çalışmaya devam etmek zorlaşır.', // 9
      'Aldığım düşük notlar uzun süre moralimi bozar.', // 10
      'Başarısızlıktan sonra kendimi toparlamam zaman alır.', // 11
      'Bir sınav kötü geçtiğinde sonraki sınavlara isteğim azalır.', // 12
      'Hata yaptıktan sonra neyi düzelteceğimi düşünürüm.', // 13 (Ters)
      'Başarısızlık beni uzun süre meşgul eder.', // 14
      'Hataları öğrenme fırsatı olarak görürüm.', // 15 (Ters)
      'Hata sonrası yeniden denemek bana zor gelir.', // 16
      // C) Çaba Sürekliliği (17-24)
      'Uzun süreli akademik hedeflere bağlı kalmakta zorlanırım.', // 17
      'Başlangıçta hevesli olsam da zamanla çabam azalır.', // 18
      'Çaba göstermenin sonuç vermediğini düşündüğüm anlar olur.', // 19
      'Çalışmaya devam etmek için dıştan zorlanmam gerekir.', // 20
      'Hedeflerim için düzenli çaba gösterebilirim.', // 21 (Ters)
      'Sonuca hemen ulaşamayınca motivasyonum düşer.', // 22
      'Emek verdikçe ilerlediğimi fark ederim.', // 23 (Ters)
      'Çabam genellikle kısa sürelidir.', // 24
      // D) Akademik Psikolojik Esneklik (25-32)
      'Planlarım bozulduğunda uyum sağlamakta zorlanırım.', // 25
      'Beklediğim gibi gitmeyen durumlar beni kolayca demoralize eder.', // 26
      'Yeni çalışma yolları denemekte zorlanırım.', // 27
      'Şartlar değiştiğinde akademik düzenim bozulur.', // 28
      'Farklı yollar deneyerek ilerleyebilirim.', // 29 (Ters)
      'Beklenmedik durumlara uyum sağlayabilirim.', // 30 (Ters)
      'Akademik süreçlerde esnek olabildiğimi düşünüyorum.', // 31 (Çeldirici)
      'Değişiklikler beni çalışmaktan uzaklaştırır.', // 32
      // E) Vazgeçme Eğilimi (33-40)
      'Zorlaştığında bırakmak benim için daha kolaydır.', // 33
      'Akademik mücadele bana gereksiz gelir.', // 34
      'Başarısız olacağımı düşündüğüm işleri ertelerim.', // 35
      'Uğraşmaya değmeyeceğini düşündüğüm anlar olur.', // 36
      'Bırakmak yerine çözüm aramayı tercih ederim.', // 37 (Ters)
      'Vazgeçme düşüncesi sık aklıma gelir.', // 38
      'Çaba göstermeden bırakmak beni rahatlatır.', // 39
      'Zorlandığımda pes etmemek için kendimi zorlarım.', // 40 (Ters)
      // F) Dayanıklılık Farkındalığı (41-48)
      'Kendimi akademik olarak dayanıklı biri olarak görürüm.', // 41 (Çeldirici)
      'Zorlanmanın öğrenmenin bir parçası olduğunu bilirim.', // 42 (Ters)
      'Akademik zorluklarla baş edebileceğime inanırım.', // 43 (Çeldirici)
      'Dayanıklılığım derslere göre değişir.', // 44 (Çeldirici)
      'Akademik dayanıklılığımın nedenlerini net olarak biliyorum.', // 45 (Çeldirici)
      'Bazı durumlarda çok dayanıklıyken bazen hiç değilim.', // 46
      'Dayanıklılığım dönemsel olarak değişir.', // 47
      'Dayanıklılığın geliştirilebileceğini düşünüyorum.', // 48 (Ters)
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
