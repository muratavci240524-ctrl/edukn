import '../../../models/survey_model.dart';
import 'guidance_test_definition.dart';

class TechnologyAddictionTest extends GuidanceTestDefinition {
  @override
  String get id => 'technology_addiction_v1';

  @override
  String get title => 'Teknoloji Bağımlılığı Ölçeği (TBÖ)';

  @override
  String get description =>
      'Bu ölçek; bireylerin teknoloji kullanım davranışlarını, kontrol mekanizmalarını, bilişsel ve duygusal bağlanma düzeylerini, sosyal ve akademik etkilerini doğrudan ve dolaylı maddelerle değerlendirmek amacıyla geliştirilmiştir. Ölçek, sorunlu ve bağımlılık düzeyine yaklaşan teknoloji kullanımını ayırt etmeyi hedefler.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'tbo_g_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<Map<String, dynamic>> items = [
      // A) Kontrol Kaybı
      {
        'text': 'Teknoloji kullanımımı planladığım noktada durdurabilirim.',
        'isReverse': true,
      },
      {
        'text': '“Biraz daha” diyerek kullanım süresini uzattığım olur.',
        'isReverse': false,
      },
      {
        'text': 'Teknolojiyi bıraktığımda zihnim hâlâ onunla meşgul olur.',
        'isReverse': false,
      },
      {
        'text': 'Teknoloji kullanımı bazen kontrolümden çıkar.',
        'isReverse': false,
      },
      {
        'text': 'İstesem teknoloji kullanımımı kolayca azaltabilirim.',
        'isReverse': true,
      },

      // B) Zaman ve Öncelik Sorunları
      {
        'text': 'Teknoloji yüzünden önemli işlerimi geciktirdiğim olur.',
        'isReverse': false,
      },
      {
        'text': 'Günlük planlarım teknoloji kullanımına göre şekillenir.',
        'isReverse': false,
      },
      {
        'text': 'Teknoloji kullanımım yaşamımdaki öncelikleri etkilemez.',
        'isReverse': true,
      },
      {
        'text': 'Gece geç saatlere kadar ekranda kalmam olağandır.',
        'isReverse': false,
      },
      {
        'text': 'Teknolojiye ayırdığım zaman makul düzeydedir.',
        'isReverse': true,
      },

      // C) Duygusal Bağlanma
      {
        'text': 'Teknoloji kullanırken kendimi daha güvende hissederim.',
        'isReverse': false,
      },
      {
        'text': 'Ruh halim teknoloji kullanımına bağlı olarak değişir.',
        'isReverse': false,
      },
      {'text': 'Teknoloji benim için yalnızca bir araçtır.', 'isReverse': true},
      {
        'text': 'Canım sıkkın olduğunda teknolojiye yönelirim.',
        'isReverse': false,
      },
      {
        'text': 'Teknoloji kullanımı beni duygusal olarak rahatlatır.',
        'isReverse': false,
      },

      // D) Kaçış ve Düzenleme Davranışları
      {
        'text': 'Sorunlardan uzaklaşmak için teknolojiye sığındığım olur.',
        'isReverse': false,
      },
      {
        'text': 'Gerçek hayattaki sıkıntıları teknolojiyle unuturum.',
        'isReverse': false,
      },
      {
        'text': 'Teknoloji, stresle baş etmemin en etkili yoludur.',
        'isReverse': false,
      },
      {
        'text': 'Teknoloji olmadan da sorunlarla baş edebilirim.',
        'isReverse': true,
      },
      {
        'text': 'Teknoloji kullanımı olumsuz duygularımı bastırır.',
        'isReverse': false,
      },

      // E) Sosyal ve Akademik / İşlevsel Etkiler
      {
        'text': 'Teknoloji yüzünden yüz yüze ilişkilerim zayıfladı.',
        'isReverse': false,
      },
      {
        'text': 'Ders/iş performansım teknoloji kullanımından etkilendi.',
        'isReverse': false,
      },
      {
        'text': 'Çevrem teknoloji kullanımım konusunda beni uyarır.',
        'isReverse': false,
      },
      {
        'text': 'Teknoloji, sorumluluklarımı yerine getirmemi zorlaştırır.',
        'isReverse': false,
      },
      {
        'text': 'Teknoloji kullanımım günlük işleyişimi bozmaz.',
        'isReverse': true,
      },

      // F) Yoksunluk ve Tolerans
      {
        'text': 'Teknolojiye erişemediğimde huzursuzluk hissederim.',
        'isReverse': false,
      },
      {
        'text': 'Aynı doyumu sağlamak için daha uzun süre kullanırım.',
        'isReverse': false,
      },
      {'text': 'Teknoloji kısıtlandığında sinirlenirim.', 'isReverse': false},
      {
        'text': 'Teknolojiden uzak kalmak benim için kolaydır.',
        'isReverse': true,
      },
      {
        'text': 'Teknoloji olmadan kendimi eksik hissederim.',
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
