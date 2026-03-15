import '../../../models/survey_model.dart';
import 'guidance_test_definition.dart';

class SleepDeprivationTest extends GuidanceTestDefinition {
  @override
  String get id => 'sleep_deprivation_v1';

  @override
  String get title => 'Uyku Yoksunluğu Ölçeği (UYÖ)';

  @override
  String get description =>
      'Bu ölçek; bireylerin uyku süresi, uyku kalitesi, gündüz işlevselliği, bilişsel ve duygusal etkiler ile uykuya bağlı davranışsal düzenlemeleri doğrudan ve dolaylı maddelerle değerlendirmek amacıyla geliştirilmiştir. Ölçek, kronik uyku yoksunluğu riskini ayırt etmeyi hedefler.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'uyo_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<Map<String, dynamic>> items = [
      // A) Uyku Süresi Yetersizliği
      {
        'text': 'Hafta içi çoğu gün yeterince uyuduğumu hissederim.',
        'isReverse': true,
      },
      {'text': 'Geceleri planladığımdan daha geç uyurum.', 'isReverse': false},
      {'text': 'Uyandığımda kendimi dinlenmiş hissetmem.', 'isReverse': false},
      {
        'text': 'Günlük uyku sürem ihtiyaçlarım için yeterlidir.',
        'isReverse': true,
      },
      {'text': 'Hafta içi ciddi uyku açığı yaşarım.', 'isReverse': false},

      // B) Uyku Kalitesi Sorunları
      {'text': 'Gece sık sık uyanırım.', 'isReverse': false},
      {'text': 'Uykuya dalmakta zorlanırım.', 'isReverse': false},
      {'text': 'Uykum derin ve kesintisizdir.', 'isReverse': true},
      {
        'text': 'Sabah erken uyanmam gerektiğini düşünmek bile uykumu bozar.',
        'isReverse': false,
      },
      {'text': 'Uykudan kolayca uyanırım.', 'isReverse': false},

      // C) Gündüz Uykululuk ve Yorgunluk
      {
        'text': 'Gün içinde gözlerimi açık tutmakta zorlanırım.',
        'isReverse': false,
      },
      {
        'text': 'Ders/iş sırasında dalıp gittiğimi fark ederim.',
        'isReverse': false,
      },
      {
        'text': 'Günlük işlerim için yeterli enerjim vardır.',
        'isReverse': true,
      },
      {'text': 'Gün içinde kestirme ihtiyacı hissederim.', 'isReverse': false},
      {'text': 'Sabaharı kendime gelmem uzun sürer.', 'isReverse': false},

      // D) Bilişsel Etkiler
      {'text': 'Dikkatimi toplamakta zorlanırım.', 'isReverse': false},
      {'text': 'Unutkanlığım arttı.', 'isReverse': false},
      {'text': 'Uykusuzluk düşünme hızımı düşürüyor.', 'isReverse': false},
      {
        'text': 'Uykum yeterliyken zihinsel olarak daha verimli olurum.',
        'isReverse': true,
      },
      {'text': 'Basit hatalar yapmaya başladım.', 'isReverse': false},

      // E) Duygusal ve Davranışsal Etkiler
      {'text': 'Uykusuz olduğumda daha sinirli olurum.', 'isReverse': false},
      {'text': 'Küçük şeylere tahammülüm azalır.', 'isReverse': false},
      {'text': 'Ruh halim uykuma bağlı olarak değişir.', 'isReverse': false},
      {'text': 'Uykusuzluk sosyal ilişkilerimi etkilemez.', 'isReverse': true},
      {
        'text': 'Kendimi duygusal olarak çabuk tükenmiş hissederim.',
        'isReverse': false,
      },

      // F) Uyku Alışkanlıkları ve Telafi Davranışları
      {
        'text': 'Hafta sonları aşırı uyuyarak açığımı kapatırım.',
        'isReverse': false,
      },
      {
        'text':
            'Uyanık kalmak için kafein (çay, kahve, enerji içeceği) kullanırım.',
        'isReverse': false,
      },
      {
        'text': 'Geç yatmama rağmen erken kalkmak zorunda kalırım.',
        'isReverse': false,
      },
      {'text': 'Düzenli bir uyku saatim vardır.', 'isReverse': true},
      {
        'text': 'Uykusuzluğun sonuçlarını gün içinde telafi etmeye çalışırım.',
        'isReverse': false,
      },
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
