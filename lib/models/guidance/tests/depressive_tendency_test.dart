import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class DepressiveTendencyTest extends GuidanceTestDefinition {
  @override
  String get id => 'depressive_tendency_v1';

  @override
  String get title => 'Depresif Eğilim Ölçeği (DEÖ)';

  @override
  String get description =>
      'Bu ölçek; bireylerin son iki hafta – bir ay içerisindeki duygu durum, düşünce biçimi, enerji düzeyi, ilgi-zevk alanları ve günlük işlevselliklerine ilişkin depresif eğilim göstergelerini değerlendirmek amacıyla geliştirilmiştir. Ölçek tanı koymaz, tarama amaçlıdır.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'deo_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<Map<String, dynamic>> items = [
      // A) Duygusal Çöküntü (6 questions)
      {
        'text': 'Son zamanlarda kendimi sık sık mutsuz hissediyorum.',
        'isReverse': false,
      },
      {
        'text': 'Gün içinde keyfim belirgin şekilde düşüyor.',
        'isReverse': false,
      },
      {'text': 'Nedensiz bir iç sıkıntısı yaşıyorum.', 'isReverse': false},
      {'text': 'Ruh halim genellikle dengelidir.', 'isReverse': true}, // #4
      {
        'text': 'Eskiden beni üzen şeyler artık daha ağır geliyor.',
        'isReverse': false,
      },
      {'text': 'Duygularımı tanımlamakta zorlanıyorum.', 'isReverse': false},

      // B) İlgi ve Zevk Kayabı (6 questions)
      {
        'text': 'Daha önce severek yaptığım şeyler artık ilgimi çekmiyor.',
        'isReverse': false,
      },
      {'text': 'Günlük aktiviteler bana anlamsız geliyor.', 'isReverse': false},
      {'text': 'Keyif alabileceğim şeyler hâlâ var.', 'isReverse': true}, // #9
      {'text': 'Bir şeye heveslenmekte zorlanıyorum.', 'isReverse': false},
      {
        'text': 'Boş zamanlarımı değerlendirmek istemiyorum.',
        'isReverse': false,
      },
      {
        'text': 'Eğlenceli bir şey yapınca kendimi suçlu hissederim.',
        'isReverse': false,
      },

      // C) Enerji ve Motivasyon (6 questions)
      {
        'text': 'Günlük işleri yapmak bana çok zor geliyor.',
        'isReverse': false,
      },
      {'text': 'Sabahları güne başlamakta zorlanıyorum.', 'isReverse': false},
      {
        'text': 'Kendimi fiziksel olarak yorgun hissediyorum.',
        'isReverse': false,
      },
      {'text': 'Enerjim genellikle yeterlidir.', 'isReverse': true}, // #16
      {'text': 'Basit işler bile gözümde büyüyor.', 'isReverse': false},
      {'text': 'Dinlensem bile yorgunluğum geçmiyor.', 'isReverse': false},

      // D) Bilişsel Yavaşlama ve Umutsuzluk (6 questions)
      {'text': 'Düşüncelerim eskisine göre daha yavaş.', 'isReverse': false},
      {
        'text': 'Geleceğe dair olumlu şeyler düşünmekte zorlanıyorum.',
        'isReverse': false,
      },
      {'text': 'Zihnim çoğu zaman dağınık.', 'isReverse': false},
      {
        'text': 'Sorunların çözülebileceğine inanırım.',
        'isReverse': true,
      }, // #22
      {
        'text': 'Hayatımda bir şeylerin düzelmesi zor görünüyor.',
        'isReverse': false,
      },
      {
        'text': 'Olan biteni anlamlandırmakta güçlük çekiyorum.',
        'isReverse': false,
      },

      // E) Kendilik Algısı (6 questions)
      {
        'text': 'Kendimle ilgili memnuniyetsizlik hissediyorum.',
        'isReverse': false,
      },
      {
        'text': 'Kendimi yeterli biri olarak görürüm.',
        'isReverse': true,
      }, // #26
      {'text': 'Başarısızlıklarımı çok kafama takıyorum.', 'isReverse': false},
      {
        'text': 'Kendime karşı sert davrandığımı fark ediyorum.',
        'isReverse': false,
      },
      {'text': 'Değerli biri olduğumu hissederim.', 'isReverse': true}, // #29
      {'text': 'Kendimle barışık hissetmiyorum.', 'isReverse': false},

      // F) Sosyal Geri Çekilme (6 questions)
      {'text': 'İnsanlarla görüşmek istemiyorum.', 'isReverse': false},
      {'text': 'Yalnız kalmayı tercih ediyorum.', 'isReverse': false},
      {'text': 'Sosyal ortamlarda bulunmak beni yorar.', 'isReverse': false},
      {
        'text': 'Yakınlarımla vakit geçirmek bana iyi gelir.',
        'isReverse': true,
      }, // #34
      {'text': 'Konuşmak için enerjim yok.', 'isReverse': false},
      {'text': 'İnsanlardan uzaklaştığımı hissediyorum.', 'isReverse': false},

      // G) Duygusal Donukluk ve Kaçınma (9 questions)
      {'text': 'Duygularımı hissetmemeye çalışıyorum.', 'isReverse': false},
      {
        'text': 'Bazı şeylere karşı hissizleştiğimi fark ediyorum.',
        'isReverse': false,
      },
      {
        'text': 'Sorunları düşünmemek için kendimi oyalıyorum.',
        'isReverse': false,
      },
      {'text': 'Duygularımla yüzleşmekten kaçınıyorum.', 'isReverse': false},
      {
        'text': 'İyi ya da kötü, pek bir şey hissetmiyorum.',
        'isReverse': false,
      },
      {
        'text': 'Kendimi otomatik pilotta yaşıyor gibi hissediyorum.',
        'isReverse': false,
      },
      {
        'text': 'Her şey normalmiş gibi davranıyorum ama içim öyle değil.',
        'isReverse': false,
      },
      {
        'text': 'Zaman geçsin diye yaşıyormuşum gibi hissediyorum.',
        'isReverse': false,
      },
      {
        'text': 'Yaşadıklarım beni duygusal olarak uyuşturdu.',
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
