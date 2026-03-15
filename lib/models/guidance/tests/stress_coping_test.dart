import '../../../models/survey_model.dart';
import 'guidance_test_definition.dart';

class StressCopingTest extends GuidanceTestDefinition {
  @override
  String get id => 'stress_coping_v1';

  @override
  String get title => 'Stresle Baş Etme Ölçeği (SBEÖ)';

  @override
  String get description =>
      'Bu ölçek; bireylerin stres yaratan durumlar karşısındaki bilişsel, duygusal, davranışsal ve sosyal baş etme stratejilerini değerlendirmek amacıyla geliştirilmiştir. Ölçek tarama amaçlıdır, tanı koymaz.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'sbo_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<Map<String, dynamic>> items = [
      // A) Bilişsel Baş Etme
      {
        'text': 'Stresli durumlarda olaya farklı açılardan bakmaya çalışırım.',
        'isReverse': false,
      },
      {
        'text': 'Stres altındayken düşüncelerim daha da karmaşıklaşır.',
        'isReverse': false,
      },
      {
        'text': 'Yaşadığım sorunları büyütme eğiliminde olurum.',
        'isReverse': false,
      },
      {
        'text': 'Stresli bir durumun geçici olduğunu kendime hatırlatırım.',
        'isReverse': false,
      },
      {
        'text': 'Zor durumlarda en kötü ihtimallere odaklanırım.',
        'isReverse': false,
      },
      {
        'text': 'Mantıklı düşünmekte zorlandığım anlar olur.',
        'isReverse': false,
      },
      {'text': 'Sorunları zihnimde çözmeye çalışırım.', 'isReverse': false},
      {
        'text':
            'Stresli anlarda düşüncelerimi kontrol etmek benim için kolaydır.',
        'isReverse': true,
      },

      // B) Duygusal Düzenleme
      {'text': 'Stresliyken duygularımı bastırırım.', 'isReverse': false},
      {'text': 'Stres yaşadığımda çabuk öfkelenirim.', 'isReverse': false},
      {
        'text': 'Duygularımı sakinleştirecek yollar bulabilirim.',
        'isReverse': true,
      },
      {
        'text': 'Stresli durumlarda kendimi çaresiz hissederim.',
        'isReverse': false,
      },
      {'text': 'Üzüntü ve kaygı uzun süre üzerimde kalır.', 'isReverse': false},
      {'text': 'Duygularımı ifade etmek beni rahatlatır.', 'isReverse': true},

      // C) Davranışsal Baş Etme
      {
        'text': 'Stresle başa çıkmak için aktif bir şeyler yaparım.',
        'isReverse': true,
      },
      {'text': 'Stresliyken hiçbir şey yapmadan beklerim.', 'isReverse': false},
      {'text': 'Sorunu çözmek için adım atarım.', 'isReverse': true},
      {
        'text': 'Stresli durumlarda günlük düzenim bozulur.',
        'isReverse': false,
      },
      {'text': 'Yapmam gereken işleri ertelerim.', 'isReverse': false},
      {
        'text': 'Stresli anlarda hareket etmek bana iyi gelir.',
        'isReverse': true,
      },

      // D) Kaçınma ve Bastırma
      {'text': 'Stresli konuları düşünmemeye çalışırım.', 'isReverse': false},
      {'text': 'Sorun yokmuş gibi davranırım.', 'isReverse': false},
      {'text': 'Stresli durumlardan uzak dururum.', 'isReverse': false},
      {'text': 'Yaşadığım stresi başkalarından gizlerim.', 'isReverse': false},
      {
        'text': 'Zamanla sorunların kendiliğinden geçeceğini düşünürüm.',
        'isReverse': false,
      },
      {'text': 'Stresle yüzleşmekten kaçınırım.', 'isReverse': false},

      // E) Sosyal Destek Kullanımı
      {'text': 'Stresli olduğumda birileriyle konuşurum.', 'isReverse': true},
      {'text': 'Sorunlarımı başkalarına anlatmak istemem.', 'isReverse': false},
      {
        'text': 'Yardım istemek beni zayıf gösterir diye düşünürüm.',
        'isReverse': false,
      },
      {
        'text': 'Stresli anlarda destek almak beni rahatlatır.',
        'isReverse': true,
      },
      {'text': 'Kimseye güvenemeyeceğimi hissederim.', 'isReverse': false},

      // F) Kontrol ve Problem Çözme
      {
        'text': 'Stres yaratan durumları kontrol edebileceğime inanırım.',
        'isReverse': true,
      },
      {
        'text': 'Kontrolüm dışındaki şeyler beni fazlasıyla yıpratır.',
        'isReverse': false,
      },
      {
        'text': 'Sorunları küçük parçalara ayırarak çözmeye çalışırım.',
        'isReverse': true,
      },
      {
        'text': 'Stresli durumlarda kontrolü kaybettiğimi hissederim.',
        'isReverse': false,
      },
      {'text': 'Elimde olmayan şeyleri kabullenebilirim.', 'isReverse': true},

      // G) İşlevsel Olmayan Tepkiler
      {'text': 'Stresliyken yeme düzenim bozulur.', 'isReverse': false},
      {
        'text': 'Stresle baş etmek için sağlıksız alışkanlıklara yönelirim.',
        'isReverse': false,
      },
      {'text': 'Stresli olduğumda kendime yüklenirim.', 'isReverse': false},
      {'text': 'Uykum stres yüzünden bozulur.', 'isReverse': false},
      {
        'text': 'Stresli anlarda kendimden memnuniyetsizlik artar.',
        'isReverse': false,
      },
      {'text': 'Stres beni tamamen kilitler.', 'isReverse': false},
    ];

    final options = [
      'Hiç katılmıyorum',
      'Katılmıyorum',
      'Kararsızım',
      'Katılıyorum',
      'Tamamen katılıyorum',
    ];

    return List.generate(items.length, (i) {
      return SurveyQuestion(
        id: 'q${i + 1}',
        text: items[i]['text'] as String,
        type: SurveyQuestionType.singleChoice,
        isRequired: true,
        options: options,
      );
    });
  }
}
