import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class AcademicMotivationGoalTest extends GuidanceTestDefinition {
  @override
  String get id => 'academic_motivation_goal_v1';

  @override
  String get title =>
      'Motivasyon Kaynakları ve Akademik Hedef Netliği Ölçeği (MAKÖ)';

  @override
  String get description =>
      'Bireyin içsel/dışsal motivasyonunu, hedef netliğini, anlam algısını ve sürdürülebilirlik gücünü analiz eder.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'mako_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<Map<String, dynamic>> items = [
      // A) İçsel Motivasyon (1-12)
      {'text': 'Öğrenmek bana keyif verir.', 'type': 'L'},
      {'text': 'Yeni şeyler öğrendiğimde tatmin olurum.', 'type': 'L'},
      {'text': 'Ders çalışırken zamanın geçtiğini fark etmem.', 'type': 'L'},
      {'text': 'Başarı benim için kişisel bir anlam taşır.', 'type': 'L'},
      {'text': 'Merak ettiğim konulara odaklanırım.', 'type': 'L'},
      {
        'text': 'Çalışmak bana anlamsız gelir.',
        'type': 'L',
        'reverse': true,
      }, // 6
      {'text': 'Kendimi geliştirmek beni motive eder.', 'type': 'L'},
      {'text': 'Zor konular ilgimi çeker.', 'type': 'L'},
      {'text': 'Çalışırken içimden gelerek devam ederim.', 'type': 'L'},
      {
        'text': 'Dersler benim için sadece zorunluluktur.',
        'type': 'L',
        'reverse': true,
      }, // 10
      {'text': 'Öğrenme süreci bana değer katar.', 'type': 'L'},
      {'text': 'Akademik başarı benim için önemlidir.', 'type': 'L'},

      // B) Dışsal Motivasyon (13-24)
      {'text': 'Ailem için çalışırım.', 'type': 'L'},
      {'text': 'Öğretmenlerin beklentileri beni etkiler.', 'type': 'L'},
      {'text': 'Notlar benim için güçlü bir motivasyondur.', 'type': 'L'},
      {'text': 'Takdir edilmek beni harekete geçirir.', 'type': 'L'},
      {'text': 'Ceza veya uyarı beni çalışmaya iter.', 'type': 'L'},
      {'text': 'Çevremdekilerin düşünceleri önemlidir.', 'type': 'L'},
      {'text': 'Rekabet beni motive eder.', 'type': 'L'},
      {'text': 'Ödül olmasa çalışmam.', 'type': 'L'}, // 20
      {'text': 'Başkalarıyla kıyaslanmak beni etkiler.', 'type': 'L'},
      {'text': 'Eleştirilmek beni harekete geçirir.', 'type': 'L'},
      {'text': 'Başkalarının beklentisiyle çalışırım.', 'type': 'L'},
      {'text': 'Dış baskı olmadan çalışmakta zorlanırım.', 'type': 'L'},

      // C) Hedef Netliği (25-36)
      {'text': 'Akademik hedeflerim nettir.', 'type': 'B'},
      {'text': 'Ne için çalıştığımı biliyorum.', 'type': 'B'},
      {'text': 'Geleceğe dair planlarım vardır.', 'type': 'B'},
      {'text': 'Hedeflerim belirsizdir.', 'type': 'B', 'reverse': true}, // 28
      {'text': 'Kısa vadeli hedefler koyarım.', 'type': 'B'},
      {'text': 'Uzun vadeli hedeflerim vardır.', 'type': 'B'},
      {
        'text': 'Ne istediğimden emin değilim.',
        'type': 'B',
        'reverse': true,
      }, // 31
      {'text': 'Hedeflerim beni yol gösterir.', 'type': 'B'},
      {'text': 'Çalışmam hedeflerimle ilişkilidir.', 'type': 'B'},
      {
        'text': 'Nereye gittiğimi bilmiyorum.',
        'type': 'B',
        'reverse': true,
      }, // 34
      {'text': 'Hedeflerim beni motive eder.', 'type': 'B'},
      {
        'text': 'Amaçsız çalıştığımı hissederim.',
        'type': 'B',
        'reverse': true,
      }, // 36
      // D) Anlam ve Amaç Algısı (37-46)
      {'text': 'Çalışmanın hayatımda bir anlamı var.', 'type': 'L'},
      {
        'text': 'Okul benim için gereksizdir.',
        'type': 'L',
        'reverse': true,
      }, // 38
      {'text': 'Öğrendiklerimi geleceğimle ilişkilendiririm.', 'type': 'L'},
      {'text': 'Derslerin bana katkı sağladığını düşünürüm.', 'type': 'L'},
      {'text': 'Yaptıklarımın bir amacı olduğunu hissederim.', 'type': 'L'},
      {
        'text': 'Okul hayatım boşuna gibi gelir.',
        'type': 'L',
        'reverse': true,
      }, // 42
      {'text': 'Eğitim hayatımın yönünü belirler.', 'type': 'L'},
      {'text': 'Çalışmanın bana bir değer kattığını hissederim.', 'type': 'L'},
      {
        'text': 'Neden çalıştığımı sorgularım.',
        'type': 'L',
        'reverse': true,
      }, // 45
      {
        'text': 'Okul sadece geçilmesi gereken bir süreçtir.',
        'type': 'L',
        'reverse': true,
      }, // 46
      // E) Sürdürme ve Devam Gücü (47-58)
      {'text': 'Zorlandığımda devam edebilirim.', 'type': 'B'},
      {'text': 'Motivasyonum çabuk düşer.', 'type': 'B', 'reverse': true}, // 48
      {'text': 'Başladığım işi sürdürürüm.', 'type': 'B'},
      {
        'text': 'Bir süre sonra isteğimi kaybederim.',
        'type': 'B',
        'reverse': true,
      }, // 50
      {'text': 'Çalışmaya yeniden başlayabilirim.', 'type': 'B'},
      {'text': 'Vazgeçme eğilimim düşüktür.', 'type': 'B'},
      {'text': 'Motivasyonumu toparlayabilirim.', 'type': 'B'},
      {'text': 'Çabuk pes ederim.', 'type': 'B', 'reverse': true}, // 54
      {'text': 'Uzun süre aynı hedefe odaklanabilirim.', 'type': 'B'},
      {'text': 'Motivasyonum dalgalıdır.', 'type': 'B', 'reverse': true}, // 56
      {'text': 'Devamlılık sağlayabilirim.', 'type': 'B'},
      {'text': 'Başarı için sabır gösterebilirim.', 'type': 'B'},
    ];

    final likertOptions = [
      'Hiç Uygun Değil',
      'Az Uygun',
      'Kısmen Uygun',
      'Oldukça Uygun',
      'Tamamen Uygun',
    ];

    final behaviorOptions = ['Hayır', 'Bazen', 'Evet'];

    return List.generate(items.length, (i) {
      final item = items[i];
      return SurveyQuestion(
        id: 'q${i + 1}',
        text: item['text'],
        type: SurveyQuestionType.singleChoice,
        isRequired: true,
        options: item['type'] == 'L' ? likertOptions : behaviorOptions,
      );
    });
  }
}
