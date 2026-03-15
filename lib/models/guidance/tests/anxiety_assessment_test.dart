import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class AnxietyAssessmentTest extends GuidanceTestDefinition {
  @override
  String get id => 'anxiety_assessment_v1';

  @override
  String get title => 'Kaygı / Bunaltı Değerlendirme Ölçeği (KBDÖ)';

  @override
  String get description =>
      'Bu ölçek; bireylerin son birkaç hafta içindeki kaygı, bunaltı, gerginlik, kontrol ihtiyacı ve kaçınma eğilimlerini değerlendirmek amacıyla geliştirilmiştir. Ölçek tanı koymaz, tarama amaçlıdır.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'kbd_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<Map<String, dynamic>> items = [
      // A) Sürekli Kaygı (6 questions)
      {
        'text': 'Gün içinde sebepsiz yere endişelendiğim olur.',
        'isReverse': false,
      },
      {
        'text': 'Aklımda sürekli “ya olursa” düşünceleri dolaşır.',
        'isReverse': false,
      },
      {
        'text': 'Kendimi genel olarak sakin hissederim.',
        'isReverse': true,
      }, // #3
      {
        'text': 'Küçük şeyler bile beni fazlasıyla düşündürür.',
        'isReverse': false,
      },
      {
        'text': 'Endişelenmemek için kendimi zorladığımı fark ederim.',
        'isReverse': false,
      },
      {
        'text': 'Kaygı benim için alışılmış bir durum haline geldi.',
        'isReverse': false,
      },

      // B) Bedensel Gerginlik (6 questions)
      {
        'text': 'Vücudumda sürekli bir gerginlik hissi var.',
        'isReverse': false,
      },
      {
        'text': 'Kalp çarpıntısı, sıkışma veya huzursuzluk yaşarım.',
        'isReverse': false,
      },
      {'text': 'Bedensel olarak rahatım.', 'isReverse': true}, // #9
      {
        'text': 'Kaslarımı sıkılı tutuyormuşum gibi hissederim.',
        'isReverse': false,
      },
      {'text': 'Nefesimi farkında olmadan tuttuğıum olur.', 'isReverse': false},
      {
        'text': 'Fiziksel belirtiler beni daha da endişelendirir.',
        'isReverse': false,
      },

      // C) Zihinsel Meşguliyet & Kontrol (6 questions)
      {'text': 'Zihnim durmadan bir şeylerle meşgul.', 'isReverse': false},
      {
        'text':
            'Her şeyi kontrol etmezsem kötü bir şey olacakmış gibi hissederim.',
        'isReverse': false,
      },
      {'text': 'Düşüncelerimi susturmakta zorlanıyorum.', 'isReverse': false},
      {'text': 'Olayları oluruna bırakabilirim.', 'isReverse': true}, // #16
      {
        'text': 'Aklımdan geçenleri durduramamak beni yorar.',
        'isReverse': false,
      },
      {'text': 'Kontrol bende değilse huzursuz olurum.', 'isReverse': false},

      // D) Kaçınma ve Erteleme (6 questions)
      {'text': 'Kaygı yaratan durumlardan uzak dururum.', 'isReverse': false},
      {'text': 'Yapmam gereken işleri ertelerim.', 'isReverse': false},
      {
        'text': 'Zorlayıcı şeyleri ötelemek beni rahatlatır.',
        'isReverse': false,
      },
      {'text': 'Yüzleşmek yerine kaçmayı seçtiğim olur.', 'isReverse': false},
      {'text': 'Kaçındığım şeyler zamanla daha büyür.', 'isReverse': false},
      {'text': 'Sorunlarla doğrudan ilgilenirim.', 'isReverse': true}, // #24
      // E) Güven Arama (6 questions)
      {
        'text': 'Birinin beni rahatlatmasına ihtiyaç duyarım.',
        'isReverse': false,
      },
      {'text': 'Sürekli onay alma ihtiyacı hissederim.', 'isReverse': false},
      {
        'text': 'Karar verirken başkalarına danışmadan rahat edemem.',
        'isReverse': false,
      },
      {'text': 'Tek başıma karar vermekte zorlanırım.', 'isReverse': false},
      {'text': 'Kendi değerlendirmeme güvenirim.', 'isReverse': true}, // #29
      {'text': 'Yanlış yapmaktan çok korkarım.', 'isReverse': false},

      // F) Bunaltı ve İçsel Baskı (6 questions)
      {'text': 'İçimde sürekli bir baskı hissi var.', 'isReverse': false},
      {
        'text': 'Kendimi daralmış veya sıkışmış hissederim.',
        'isReverse': false,
      },
      {
        'text': 'Zaman zaman her şey üstüme geliyormuş gibi olur.',
        'isReverse': false,
      },
      {'text': 'Rahatlayabildiğim anlar vardır.', 'isReverse': true}, // #34
      {'text': 'Bunaltı hissi beni tüketiyor.', 'isReverse': false},
      {'text': 'İçsel huzur hissim azaldı.', 'isReverse': false},

      // G) Kaygıyı Gizleme / Normalleştirme (12 questions)
      {
        'text': 'Kaygımı başkalarına belli etmemeye çalışırım.',
        'isReverse': false,
      },
      {
        'text': '“Herkes böyle hissediyor” diyerek geçiştiririm.',
        'isReverse': false,
      },
      {
        'text': 'Aslında kaygılıyım ama normalmiş gibi davranırım.',
        'isReverse': false,
      },
      {
        'text': 'Sorun yokmuş gibi davranmak işime geliyor.',
        'isReverse': false,
      },
      {'text': 'Kaygımın farkında değilim.', 'isReverse': false}, // Çeldirici
      {'text': 'Duygularımı küçümserim.', 'isReverse': false},
      {'text': 'Kaygı beni tanımlamaz.', 'isReverse': true}, // #43
      {
        'text': 'Hissettiklerimi bastırdığımı fark ediyorum.',
        'isReverse': false,
      },
      {'text': 'Güçlü görünmek için içimi saklarım.', 'isReverse': false},
      {
        'text': 'Kaygıdan söz etmeyi gereksiz bulurum.',
        'isReverse': false,
      }, // Çeldirici
      {'text': 'İçimde olanları net tarif edemiyorum.', 'isReverse': false},
      {'text': '“İyiyim” demek daha kolay geliyor.', 'isReverse': false},
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
