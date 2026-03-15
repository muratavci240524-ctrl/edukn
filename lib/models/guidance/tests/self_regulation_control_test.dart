import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class SelfRegulationControlTest extends GuidanceTestDefinition {
  @override
  String get id => 'self_regulation_control_v1';

  @override
  String get title => 'Öz Düzenleme ve Öz Kontrol Becerileri Ölçeği (ÖD-ÖKÖ)';

  @override
  String get description =>
      'Bireyin irade gücünü, dürtü kontrolünü ve duygusal öz düzenleme kapasitesini analiz eder.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'self_reg_control_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<Map<String, dynamic>> items = [
      // A) Hedefe Yönelik Davranış Kontrolü (1-12)
      {'text': 'Belirlediğim hedefe uygun davranırım.'},
      {'text': 'Hedeflerimi çabuk unuturum.', 'reverse': true}, // 2
      {'text': 'Yapmam gerekenle yaptıklarım uyumludur.'},
      {
        'text': 'Hedefim olsa bile farklı şeylere yönelirim.',
        'reverse': true,
      }, // 4
      {'text': 'Davranışlarımı hedefime göre ayarlarım.'},
      {'text': 'Hedefim varken bile dağılırım.', 'reverse': true}, // 6
      {'text': 'Hedefe ulaşmak için kendimi yönlendirebilirim.'},
      {'text': 'Hedeflerim davranışlarımı etkilemez.', 'reverse': true}, // 8
      {'text': 'Uzun vadeli hedefleri dikkate alırım.'},
      {
        'text': 'Kısa vadeli isteklerim hedeflerimin önüne geçer.',
        'reverse': true,
      }, // 10
      {'text': 'Hedefime uygun olmayan davranışı durdurabilirim.'},
      {
        'text': 'Hedef belirlemek davranışımı değiştirmez.',
        'reverse': true,
      }, // 12
      // B) Dürtü ve Anlık İstek Yönetimi (13-24)
      {'text': 'Anlık isteklerimi kontrol edebilirim.'},
      {'text': 'Canım ne isterse onu yaparım.', 'reverse': true}, // 14
      {'text': 'Dürtülerimi fark ederim.'},
      {'text': 'Kendimi tutmakta zorlanırım.', 'reverse': true}, // 16
      {'text': 'İsteklerim davranışımı yönetmez.'},
      {'text': 'Dürtülerime karşı koyamam.', 'reverse': true}, // 18
      {'text': 'Hemen haz veren şeyi seçmem.'},
      {'text': 'Sabretmek benim için zordur.', 'reverse': true}, // 20
      {'text': 'Anlık kararlar almam.'},
      {'text': 'Düşünmeden hareket ederim.', 'reverse': true}, // 22
      {'text': 'Kendimi frenleyebilirim.'},
      {'text': 'İsteklerime karşı dirençliyim.'},

      // C) Duygusal Öz Düzenleme (25-36)
      {'text': 'Duygularımı kontrol edebilirim.'},
      {'text': 'Duygularım beni yönetir.', 'reverse': true}, // 26
      {'text': 'Olumsuz duygularla baş edebilirim.'},
      {'text': 'Sinirlendiğimde kontrolümü kaybederim.', 'reverse': true}, // 28
      {'text': 'Duygularım davranışımı belirlemez.'},
      {'text': 'Duygusal tepkilerim ani olur.', 'reverse': true}, // 30
      {'text': 'Sakin kalabilirim.'},
      {'text': 'Duygularım yüzünden planımı bozarım.', 'reverse': true}, // 32
      {'text': 'Stresliyken kendimi düzenleyebilirim.'},
      {'text': 'Duygusal dalgalanmalar beni zorlar.', 'reverse': true}, // 34
      {'text': 'Duygularımı fark ederim.'},
      {'text': 'Duygularımı yönetmekte zorlanmam.'},

      // D) Sürdürülebilirlik ve İstikrar (37-48)
      {'text': 'Başladığım işi sürdürürüm.'},
      {'text': 'Çabuk vazgeçerim.', 'reverse': true}, // 38
      {'text': 'Alışkanlık oluşturabilirim.'},
      {'text': 'Süreklilik sağlamakta zorlanırım.', 'reverse': true}, // 40
      {'text': 'Uzun süre aynı hedefe odaklanabilirim.'},
      {'text': 'Hevesim çabuk söner.', 'reverse': true}, // 42
      {'text': 'Devamlılık benim güçlü yönümdür.'},
      {'text': 'Disiplinli olamam.', 'reverse': true}, // 44
      {'text': 'Rutinlere uyabilirim.'},
      {'text': 'Başladığımı bitiririm.'},
      {'text': 'Zorlandığımda bırakırım.', 'reverse': true}, // 47
      {'text': 'Süreklilik benim için mümkündür.'},

      // E) Kendini İzleme ve Farkındalık (49-60)
      {'text': 'Davranışlarımı gözlemlerim.'},
      {'text': 'Ne yaptığımın farkında olmam.', 'reverse': true}, // 50
      {'text': 'Kendimi değerlendiririm.'},
      {'text': 'Hatalarımı fark etmem.', 'reverse': true}, // 52
      {'text': 'Gelişimimi takip ederim.'},
      {'text': 'Davranışlarımı sorgulamam.', 'reverse': true}, // 54
      {'text': 'Kendime geri bildirim veririm.'},
      {'text': 'Neden böyle davrandığımı bilirim.'},
      {'text': 'Kendi tepkilerimi tanırım.'},
      {'text': 'Kendimi gözlemlemek bana zor gelir.', 'reverse': true}, // 58
      {'text': 'Güçlü ve zayıf yönlerimi bilirim.'},
      {'text': 'Kendimi izlemeyi önemserim.'},

      // F) Öz Disiplin ve Kararlılık (61-72)
      {'text': 'Kendime koyduğum kurallara uyarım.'},
      {'text': 'Kuralları çabuk bozarım.', 'reverse': true}, // 62
      {'text': 'Disiplinli çalışabilirim.'},
      {'text': 'Kendimi zorlayamam.', 'reverse': true}, // 64
      {'text': 'Kararlı biriyim.'},
      {'text': 'Vazgeçmeye meyilliyim.', 'reverse': true}, // 66
      {'text': 'Uzun vadede kendimi kontrol edebilirim.'},
      {'text': 'Disiplini sürdüremem.', 'reverse': true}, // 68
      {'text': 'Kendime söz verdiğimde tutarım.'},
      {
        'text': 'Kendimi kontrol etmekte güçlük çekerim.',
        'reverse': true,
      }, // 70
      {'text': 'Kararlılık benim için mümkündür.'},
      {'text': 'Öz kontrolüm güçlüdür.'},
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
