import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class ExamAnxietyCopingTest extends GuidanceTestDefinition {
  @override
  String get id => 'exam_anxiety_coping_v1';

  @override
  String get title => 'Sınav Kaygısı ile Baş Etme Ölçeği (SKBÖ)';

  @override
  String get description =>
      'Bu ölçek bireylerin sınav sürecinde yaşadıkları kaygıyı nasıl yönettiklerini, hangi stratejileri kullandıklarını ve hangi alanlarda zorlandıklarını değerlendirmek amacıyla geliştirilmiştir. Ölçek tanı koymaz, tarama amaçlıdır.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'skb_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Kaygıyı Tanıma ve Kabul (1-6)
      'Sınav kaygımı fark ederim.', // 1 (Reverse)
      'Kaygımı yok saymaya çalışırım.', // 2
      'Kaygının beni etkilediğini kabul ederim.', // 3 (Reverse)
      'Kaygı hissettiğimde paniklerim.', // 4
      'Kaygımı bastırmak çözüm gibi gelir.', // 5
      'Kaygının sınav sürecinin bir parçası olduğunu bilirim.', // 6 (Reverse)
      // B) Bilişsel Baş Etme (7-12)
      'Olumsuz düşüncelerimi durdurabilirim.', // 7 (Reverse)
      '“Ya yapamazsam” düşüncesi zihnimi ele geçirir.', // 8
      'Kendime sakinleştirici iç konuşmalar yaparım.', // 9 (Reverse)
      'Düşüncelerim kontrolden çıkıyormuş gibi olur.', // 10
      'Gerçekçi düşünmeye çalışırım.', // 11 (Reverse)
      'Zihnimi toparlamakta zorlanırım.', // 12
      // C) Bedensel Baş Etme (13-18)
      'Nefesimi sakinleştirebilirim.', // 13 (Reverse)
      'Sınav öncesi bedensel belirtilerim artar.', // 14
      'Vücudumun verdiği tepkileri yönetebilirim.', // 15 (Reverse)
      'Kalp çarpıntısı ve gerginlik beni bozar.', // 16
      'Rahatlama tekniklerini kullanırım.', // 17 (Reverse)
      'Bedensel tepkilerim kontrolümden çıkar.', // 18
      // D) Çalışma ve Planlama (19-24)
      'Çalışma planı yaparım.', // 19 (Reverse)
      'Kaygı yüzünden çalışmayı ertelerim.', // 20
      'Düzenli çalışmak beni rahatlatır.', // 21 (Reverse)
      'Son ana bırakırım.', // 22
      'Hazırlık sürecini kontrol edebilirim.', // 23 (Reverse)
      'Çalışma düzenim kaygıya göre bozulur.', // 24
      // E) Kaçınma ve Erteleme (25-30)
      'Sınavla ilgili konulardan uzak dururum.', // 25
      'Kaygı hissettiğimde başka şeylere yönelirim.', // 26
      'Kaçınmak beni geçici olarak rahatlatır.', // 27
      'Zor konuları görmezden gelirim.', // 28
      'Kaygıyla yüzleşirim.', // 29 (Reverse)
      'Sınavdan kaçma isteği duyarım.', // 30
      // F) Duygusal Düzenleme (31-36)
      'Duygularımı sakinleştirebilirim.', // 31 (Reverse)
      'Sınav yaklaştıkça duygusal olarak dağılırım.', // 32
      'Kendime anlayış gösteririm.', // 33 (Reverse)
      'Kaygı beni tamamen ele geçirir.', // 34
      'Kendimi duygusal olarak toparlayabilirim.', // 35 (Reverse)
      'Duygularım kontrolden çıkmış gibidir.', // 36
      // G) Kendini Sabotaj & Aşırı Kontrol (37-42)
      'Mükemmel yapamazsam hiç yapmam.', // 37
      'Kendime aşırı yüklenirim.', // 38
      'Küçük hatalar beni tamamen bozar.', // 39
      'Kendimi sürekli eleştiririm.', // 40
      'Elimden geleni yapmanın yeterli olduğunu düşünürüm.', // 41 (Reverse)
      'Kendime tolerans göstermekte zorlanırım.', // 42
      // H) Genel Baş Etme Algısı (Çeldirici Alan) (43-52)
      'Sınav kaygısını çok iyi yönetirim.', // 43
      'Sınavlar beni hiç etkilemez.', // 44
      'Sınav sürecinde zorlanmam.', // 45
      'Kaygı benim için problem değildir.', // 46
      'Sınavlarda her zaman sakinim.', // 47
      'Kaygıyla baş etme konusunda kararsızım.', // 48
      'Ne yaptığımın farkında değilim.', // 49
      'Bazı zamanlar baş ediyorum, bazı zamanlar edemiyorum.', // 50
      'Sınav süreci beni düşündüğümden fazla etkiliyor.', // 51
      'Kaygıyla baş etmeyi öğrenmem gerektiğini hissediyorum.', // 52
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
