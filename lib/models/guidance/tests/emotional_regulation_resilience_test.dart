import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class EmotionalRegulationResilienceTest extends GuidanceTestDefinition {
  @override
  String get id => 'emotional_regulation_resilience_v1';

  @override
  String get title =>
      'Duygusal Düzenleme ve Akademik Dayanıklılık Ölçeği (DD-ADÖ)';

  @override
  String get description =>
      'Bireyin duygusal farkındalığını, stres sonrası toparlanma gücünü ve akademik dayanıklılığını analiz eder.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'emotion_resilience_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<Map<String, dynamic>> items = [
      // A) Duygusal Farkındalık (1-12)
      {'text': 'Ders çalışırken duygusal olarak zorlandığımı fark ederim.'},
      {'text': 'Streslendiğimde bunun nedenini anlayabilirim.'},
      {'text': 'Olumsuz duygularımın farkındayım.'},
      {'text': 'Duygularımın performansımı etkilediğini hissederim.'},
      {'text': 'Ne zaman gerildiğimi ayırt edebilirim.'},
      {'text': 'Ruh hâlimin derslerime yansıdığını fark ederim.'},
      {'text': 'Duygularımı bastırmak yerine tanımaya çalışırım.'},
      {'text': 'Zorlandığımda bunu kendime itiraf edebilirim.'},
      {'text': 'Duygusal iniş çıkışlarımı gözlemleyebilirim.'},
      {'text': 'Duygularımı anlamakta zorlanırım.', 'reverse': true}, // 10
      {'text': 'Ne hissettiğimi çoğu zaman fark etmem.', 'reverse': true}, // 11
      {'text': 'Duygularımın davranışlarımı yönlendirdiğini görürüm.'},

      // B) Duygusal Kontrol ve Düzenleme (13-24)
      {'text': 'Gergin olduğumda kendimi sakinleştirebilirim.'},
      {'text': 'Olumsuz duygularla baş etme yollarım vardır.'},
      {'text': 'Stresli anlarda kontrolü kaybederim.', 'reverse': true}, // 15
      {
        'text': 'Duygularım ders çalışmamı tamamen durdurur.',
        'reverse': true,
      }, // 16
      {'text': 'Zorlandığımda mola verip devam edebilirim.'},
      {'text': 'Kaygılandığımda düşüncelerimi toparlayabilirim.'},
      {'text': 'Duygusal olarak dağıldığımda geri dönebilirim.'},
      {
        'text': 'Öfke veya hayal kırıklığı beni uzun süre etkiler.',
        'reverse': true,
      }, // 20
      {
        'text': 'Duygularımı yönetmekte genelde zorlanırım.',
        'reverse': true,
      }, // 21
      {'text': 'Olumsuz duygular geçicidir diye düşünürüm.'},
      {'text': 'Kendimi yatıştırma yöntemlerim vardır.'},
      {'text': 'Duygusal kontrolüm zayıftır.', 'reverse': true}, // 24
      // C) Stres Sonrası Toparlanma (25-36)
      {'text': 'Kötü bir sınavdan sonra tekrar çalışabilirim.'},
      {'text': 'Başarısızlık beni uzun süre durdurur.', 'reverse': true}, // 26
      {'text': 'Moral bozukluğundan çıkmam zaman alır.', 'reverse': true}, // 27
      {'text': 'Olumsuz bir olaydan sonra toparlanabilirim.'},
      {
        'text': 'Hata yaptıktan sonra devam etmekte zorlanırım.',
        'reverse': true,
      }, // 29
      {'text': 'Stres yaşasam da yeniden odaklanabilirim.'},
      {'text': 'Düşüşlerden sonra kendimi toparlayabilirim.'},
      {'text': 'Moral kaybı beni uzun süre etkiler.', 'reverse': true}, // 32
      {'text': 'Zor bir dönemden sonra yeniden güçlenirim.'},
      {
        'text': 'Tek bir başarısızlık motivasyonumu bitirir.',
        'reverse': true,
      }, // 34
      {'text': 'Yaşadığım stres geçtikten sonra ilerlerim.'},
      {
        'text': 'Olumsuzlukları geride bırakmakta zorlanırım.',
        'reverse': true,
      }, // 36
      // D) Akademik Dayanıklılık (37-48)
      {'text': 'Zor derslerden kaçmak yerine üstüne giderim.'},
      {'text': 'Kolay vazgeçerim.', 'reverse': true}, // 38
      {'text': 'Zorlanınca bırakmak aklıma gelir.', 'reverse': true}, // 39
      {'text': 'Uzun süreli çaba gerektiren işleri sürdürebilirim.'},
      {'text': 'Engeller beni yıldırır.', 'reverse': true}, // 41
      {'text': 'Hedeflerime ulaşmak için sabırlıyımdır.'},
      {'text': 'Zorlandığımda alternatif yollar denerim.'},
      {'text': 'Direncim çabuk kırılır.', 'reverse': true}, // 44
      {'text': 'Mücadele etmeyi sürdürürüm.'},
      {'text': 'Engeller karşısında dayanıklıyımdır.'},
      {'text': 'Zorluklar beni tamamen durdurur.', 'reverse': true}, // 47
      {'text': 'Akademik süreçte direnç gösterebilirim.'},

      // E) Pes Etme – Devam Etme Dengesi (49-64)
      {'text': 'Zorlandığımda devam etmeyi seçerim.'},
      {'text': 'İlk aksilikte vazgeçerim.', 'reverse': true}, // 50
      {'text': 'Devam etmek için kendimi motive edebilirim.'},
      {'text': 'Bırakmak çoğu zaman daha cazip gelir.', 'reverse': true}, // 52
      {'text': 'Küçük ilerlemeler beni motive eder.'},
      {'text': 'Süreç zorlaşınca geri çekilirim.', 'reverse': true}, // 54
      {'text': 'Pes etmek yerine uyum sağlamayı denerim.'},
      {'text': 'Dayanmak benim için zordur.', 'reverse': true}, // 56
      {'text': 'Devam edebilme gücüm vardır.'},
      {'text': 'Zorluklar karşısında çabuk yorulurum.', 'reverse': true}, // 58
      {'text': 'Kendimi toparlayıp devam edebilirim.'},
      {'text': 'Devam etmek için içsel gücüm vardır.'},
      {'text': 'Zor anlarda kendime destek olabilirim.'},
      {'text': 'Pes etmek sık başvurduğum bir yoldur.', 'reverse': true}, // 62
      {'text': 'Direnmek bana güç verir.'},
      {
        'text': 'Vazgeçmem gerektiğini sık sık düşünürüm.',
        'reverse': true,
      }, // 64
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
