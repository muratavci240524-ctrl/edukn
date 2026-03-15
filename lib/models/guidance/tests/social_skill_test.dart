import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class SocialSkillTest extends GuidanceTestDefinition {
  @override
  String get id => 'social_skill_v1';

  @override
  String get title => 'Sosyal Beceri Ölçeği (SBÖ)';

  @override
  String get description =>
      'Bu ölçek; bireylerin günlük sosyal yaşamdaki iletişim, etkileşim, empati, girişkenlik, sınır koyma ve sosyal uyum becerilerini değerlendirmek amacıyla geliştirilmiştir. Ölçek tanı koymaz, gelişim amaçlıdır.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'sb_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<Map<String, dynamic>> items = [
      // A) İletişim Başlatma (6 questions)
      {
        'text': 'Yeni biriyle konuşmaya başlamakta zorlanmam.',
        'isReverse': false,
      },
      {
        'text': 'Tanımadığım kişilerle iletişim kurmaktan kaçınırım.',
        'isReverse': false,
      },
      {
        'text': 'Ortama girdiğimde konuşmayı başlatabilirim.',
        'isReverse': false,
      },
      {
        'text': 'İlk adımı karşımdakinin atmasını beklerim.',
        'isReverse': false,
      },
      {
        'text': 'Sosyal ortamlarda sessiz kalmayı tercih ederim.',
        'isReverse': false,
      },
      {'text': 'Sohbete girmek benim için doğaldır.', 'isReverse': true}, // #6
      // B) İletişimi Sürdürme (6 questions)
      {'text': 'Sohbeti devam ettirecek şeyler bulurum.', 'isReverse': false},
      {'text': 'Konuşma sırasında ne diyeceğimi bilemem.', 'isReverse': false},
      {'text': 'Diyalog kurarken rahat hissederim.', 'isReverse': true}, // #9
      {'text': 'Konuşma uzadıkça gerilirim.', 'isReverse': false},
      {'text': 'Karşılıklı iletişimi sürdürebilirim.', 'isReverse': false},
      {
        'text': 'Sohbetler bana çabuk sıkıcı gelir.',
        'isReverse': false,
      }, // Distractor
      // C) Sosyal Özgüven (6 questions)
      {'text': 'Topluluk içinde kendime güvenirim.', 'isReverse': true}, // #13
      {'text': 'İnsanların beni yargıladığını düşünürüm.', 'isReverse': false},
      {
        'text': 'Sosyal ortamlarda kendimi rahat hissederim.',
        'isReverse': true,
      }, // #15
      {'text': 'Yanlış bir şey söylemekten çok çekinirim.', 'isReverse': false},
      {
        'text': 'Düşüncelerimi ifade ederken özgürüm.',
        'isReverse': true,
      }, // #17
      {
        'text': 'Sosyal ortamlarda gerildiğimi fark ederim.',
        'isReverse': false,
      },

      // D) Empati ve Duyarlılık (6 questions)
      {
        'text': 'Karşımdakinin duygularını anlamaya çalışırım.',
        'isReverse': true,
      }, // #19
      {
        'text': 'İnsanların ne hissettiğini fark ederim.',
        'isReverse': true,
      }, // #20
      {
        'text': 'Başkalarının bakış açısını düşünürüm.',
        'isReverse': true,
      }, // #21
      {
        'text': 'Karşımdakinin duyguları beni çok etkilemez.',
        'isReverse': false,
      },
      {
        'text': 'İnsanları dinlerken gerçekten anlamaya çalışırım.',
        'isReverse': true,
      }, // #23
      {'text': 'Duygusal ipuçlarını kaçırırım.', 'isReverse': false},

      // E) Sınır Koyma ve Kendini Savunma (6 questions)
      {
        'text': 'İstemediğim durumlarda hayır diyebilirim.',
        'isReverse': true,
      }, // #25
      {
        'text': 'Başkalarını kırmamak için kendimden vazgeçerim.',
        'isReverse': false,
      },
      {'text': 'Haklarımı savunmakta zorlanırım.', 'isReverse': false},
      {
        'text': 'Rahatsız olduğumda bunu dile getiririm.',
        'isReverse': true,
      }, // #28
      {
        'text': 'İnsanların beni kullanmasına engel olurum.',
        'isReverse': true,
      }, // #29
      {'text': 'Sessiz kalmak daha kolay gelir.', 'isReverse': false},

      // F) Sosyal Kaçınma ve Çekingenlik (6 questions)
      {'text': 'Sosyal ortamlardan kaçınırım.', 'isReverse': false},
      {'text': 'Kalabalıklar beni rahatsız eder.', 'isReverse': false},
      {'text': 'Sosyal etkinliklerden uzak dururum.', 'isReverse': false},
      {'text': 'İnsanlarla birlikte olmak beni yorar.', 'isReverse': false},
      {
        'text': 'Sosyal ortamlarda bulunmak bana iyi gelir.',
        'isReverse': true,
      }, // #35
      {
        'text': 'Yalnız kalmayı tercih ederim.',
        'isReverse': false,
      }, // Distractor
      // G) Sosyal Farkındalık ve Uyum (6 questions)
      {
        'text': 'Ortama göre davranışımı ayarlayabilirim.',
        'isReverse': true,
      }, // #37
      {
        'text': 'Sosyal kuralları anlamakta zorlanmam.',
        'isReverse': true,
      }, // #38
      {
        'text': 'Uygunsuz davrandığımı sonradan fark ederim.',
        'isReverse': false,
      },
      {
        'text': 'İnsanların tepkilerini okuyabilirim.',
        'isReverse': true,
      }, // #40
      {'text': 'Sosyal ipuçlarını kaçırırım.', 'isReverse': false},
      {'text': 'Ortamlara uyum sağlamakta zorlanırım.', 'isReverse': false},

      // H) Sosyal Kendini Değerlendirme (8 Çeldirici questions)
      {'text': 'Sosyal becerilerim çok iyidir.', 'isReverse': false},
      {'text': 'Sosyal anlamda hiç zorlanmam.', 'isReverse': false},
      {'text': 'İnsan ilişkilerinde problem yaşamam.', 'isReverse': false},
      {'text': 'Sosyal ortamlarda her zaman rahatımdır.', 'isReverse': false},
      {
        'text': 'İnsanlarla iletişim kurmak benim için zahmetsizdir.',
        'isReverse': false,
      },
      {'text': 'Sosyal ilişkilerde hiç sorun yaşamam.', 'isReverse': false},
      {'text': 'Sosyal becerilerim konusunda kararsızım.', 'isReverse': false},
      {'text': 'Sosyal yönlerimi net tanımlayamıyorum.', 'isReverse': false},
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
