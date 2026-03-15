import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class SchoolAdaptationTest extends GuidanceTestDefinition {
  @override
  String get id => 'school_adaptation_v1';

  @override
  String get title => 'Okula Uyum Göstergeleri Ölçeği (OUGÖ)';

  @override
  String get description =>
      'Bu ölçek öğrencinin okula duygusal, davranışsal, akademik, sosyal ve motivasyonel düzeyde uyumunu değerlendirmeyi amaçlar. Tanı koyma amacı taşımaz, uyum örüntülerini ortaya çıkarır.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'ougo_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Duygusal Uyum (1-6)
      'Okula giderken genelde kendimi iyi hissederim.', // 1 (Ters)
      'Okul düşüncesi bende huzursuzluk yaratır.', // 2
      'Okulda bulunmak bana güven verir.', // 3 (Ters)
      'Okuldayken kendimi sık sık gergin hissederim.', // 4
      'Okul ortamında duygularımı kontrol etmekte zorlanırım.', // 5
      'Okulda olmak benim için nötr bir durumdur.', // 6 (Çeldirici)
      // B) Davranışsal Uyum (7-12)
      'Okul kurallarına uymakta zorlanırım.', // 7
      'Okulda davranışlarımı kontrol edebilirim.', // 8 (Ters)
      'Ders sırasında sık sık uyarı alırım.', // 9
      'Okulda benden beklenen davranışları bilirim.', // 10 (Ters)
      'Kurallar bana anlamsız gelir.', // 11 (Çeldirici)
      'Okulda nasıl davranmam gerektiğini çoğu zaman kestiremem.', // 12
      // C) Akademik Uyum (13-18)
      'Derslerin temposuna ayak uydurabilirim.', // 13 (Ters)
      'Derslerde geride kaldığımı hissederim.', // 14
      'Okuldaki akademik beklentiler bana ağır gelir.', // 15
      'Derslere hazırlanmak benim için zorlayıcıdır.', // 16
      'Okulda başarılı olabileceğime inanırım.', // 17 (Ters)
      'Bazı derslerde uyum sağlasam da çoğunda zorlanırım.', // 18 (Çeldirici)
      // D) Sosyal Uyum (19-24)
      'Arkadaş ilişkilerimde genelde rahatım.', // 19 (Ters)
      'Okulda kendimi yalnız hissederim.', // 20
      'Akranlarımla iletişim kurmakta zorlanırım.', // 21
      'Okulda kendim gibi davranabilirim.', // 22 (Ters)
      'Sosyal ortamlarda geri dururum.', // 23
      'Kimlerle iyi anlaştığım duruma göre değişir.', // 24 (Çeldirici)
      // E) Okula Aidiyet (25-30)
      'Okuluma ait hissederim.', // 25 (Ters)
      'Okulda yabancı biri gibi hissederim.', // 26
      'Okul benim için sadece gelinip gidilen bir yerdir.', // 27
      'Okulumun bir parçası olduğumu düşünürüm.', // 28 (Ters)
      'Okulla ilgili konularda kendimi dışarıda hissederim.', // 29
      'Okula bağlılık benim için önemli değildir.', // 30 (Çeldirici)
      // F) Okul Motivasyonu (31-36)
      'Okula gitmek için içsel bir isteğim vardır.', // 31 (Ters)
      'Okula sadece mecbur olduğum için giderim.', // 32
      'Okulda yaptıklarımın anlamlı olduğunu düşünürüm.', // 33 (Ters)
      'Okul benim için zaman kaybı gibi gelir.', // 34
      'Okul hedeflerime katkı sağlar.', // 35 (Ters)
      'Bazı günler istekliyim, bazı günler tamamen isteksizim.', // 36 (Çeldirici)
      // G) Genel & Çapraz Maddeler (37-43)
      'Okula uyumum derslere göre değişir.', // 37 (Ters)
      'Okulda kendimi ne iyi ne kötü hissederim.', // 38
      'Uyum sorunu yaşadığımı düşünmüyorum.', // 39 (Çeldirici)
      'Okulda zorlandığım alanlar net değildir.', // 40
      'Okul ortamına alışmam zaman alır.', // 41
      'Uyumum öğretmenlere göre değişir.', // 42 (Ters)
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
