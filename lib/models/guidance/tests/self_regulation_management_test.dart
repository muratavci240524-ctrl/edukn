import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class SelfRegulationManagementTest extends GuidanceTestDefinition {
  @override
  String get id => 'self_regulation_management_v1';

  @override
  String get title => 'Öz-Düzenleme ve Kendini Yönetme Ölçeği (ÖD-KYÖ)';

  @override
  String get description =>
      'Bireyin davranışlarını planlama, dürtü kontrolü, enerji yönetimi ve sürdürülebilir disiplin becerilerini analiz eder.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'self_reg_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Hedef Belirleme ve Planlama (1-12)
      'Çalışmaya başlamadan önce ne yapacağımı netleştiririm.', // 1
      'Hedef koyarım ama uygulayamam.', // 2
      'Günlük hedefler belirlerim.', // 3
      'Plan yapmayı ertelerim.', // 4
      'Uzun vadeli hedeflerim nettir.', // 5
      'Planlarım genelde yarım kalır.', // 6
      'Öncelik sıralaması yapabilirim.', // 7
      'Ne zaman ne yapacağımı karıştırırım.', // 8
      'Planım bozulsa da yeniden kurarım.', // 9
      'Plansız çalışırım.', // 10
      'Hedeflerimi yazıya dökerim.', // 11
      'Plan yapmanın bana faydası olmadığını düşünürüm.', // 12
      // B) Dürtü Kontrolü (13-24)
      'Çalışırken telefonumu kontrol ederim.', // 13
      'Anlık isteklerime direnebilirim.', // 14
      'Canım istemediğinde bırakırım.', // 15
      'Kendimi durdurabilirim.', // 16
      'Erteleme dürtüsüne kapılırım.', // 17
      'Kendimi kontrol etmekte zorlanırım.', // 18
      'Kısa süreli hazlar beni dağıtır.', // 19
      'Dikkat dağıtıcıları yönetebilirim.', // 20
      'Anlık kararlar alırım.', // 21
      'Davranışımı bilinçli seçerim.', // 22
      'Kendimi frenleyebilirim.', // 23
      'Dürtülerim beni yönetir.', // 24
      // C) Süre ve Enerji Yönetimi (25-36)
      'Zamanımı planlı kullanırım.', // 25
      'Zamanın nasıl geçtiğini fark etmem.', // 26
      'Çalışma sürelerimi ayarlayabilirim.', // 27
      'Çabuk yorulurum.', // 28
      'Enerjimi dengeli kullanırım.', // 29
      'Gün içinde verimim çok dalgalanır.', // 30
      'Molaları bilinçli veririm.', // 31
      'Zaman baskısı beni kilitler.', // 32
      'Süreyi kontrol edebilirim.', // 33
      'Son ana bırakırım.', // 34
      'Çalışma temposunu ayarlayabilirim.', // 35
      'Zaman yönetiminde zorlanırım.', // 36
      // D) Duygusal Öz-Düzenleme (37-48)
      'Zorlandığımda pes etmem.', // 37
      'Duygularım çalışmamı bozar.', // 38
      'Olumsuz duygularımı yönetebilirim.', // 39
      'Moral bozukluğu beni durdurur.', // 40
      'Kendimi sakinleştirebilirim.', // 41
      'Küçük başarısızlıklar beni dağıtır.', // 42
      'İç motivasyonumu koruyabilirim.', // 43
      'Duygusal iniş çıkışlar yaşarım.', // 44
      'Zorlanınca devam edebilirim.', // 45
      'Hatalar beni demotive eder.', // 46
      'Kendimle yapıcı konuşurum.', // 47
      'İçsel kontrolüm zayıftır.', // 48
      // E) Sürdürülebilir Davranış (49-60)
      'Başladığım işi bitiririm.', // 49
      'Süreklilik sağlamakta zorlanırım.', // 50
      'Alışkanlık oluşturabilirim.', // 51
      'Çabuk bırakırım.', // 52
      'Disiplinli davranırım.', // 53
      'Bir süre sonra koparım.', // 54
      'Davranışlarım tutarlıdır.', // 55
      'İstikrarsızım.', // 56
      'Rutinlerim vardır.', // 57
      'Rutinlere uymakta zorlanırım.', // 58
      'Kendimi uzun vadede yönetebilirim.', // 59
      'Kontrolü çabuk kaybederim.', // 60
    ];

    final options = [
      'Hiç Uygun Değil',
      'Az Uygun',
      'Kısmen Uygun',
      'Oldukça Uygun',
      'Tamamen Uygun',
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
