import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class AcademicSelfEfficacyTest extends GuidanceTestDefinition {
  @override
  String get id => 'academic_self_efficacy_v1';

  @override
  String get title => 'Akademik Öz-Yeterlik Algısı Ölçeği (AOEÖ)';

  @override
  String get description =>
      'Bu ölçek; bireyin akademik görevleri başarabileceğine dair inancını, bu inancın istikrarını ve gerçekçiliğini değerlendirir. Öz-yeterliğin dalgalandığı alanları ve "yapabilirim" duygusunun kırılganlığını ortaya koymayı amaçlar.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'aoeo_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Akademik Görev Güveni (1-8)
      'Akademik görevlerin çoğunu başarıyla yapabileceğime inanırım.', // 1
      'Bir ödev veya proje verildiğinde yapabileceğimden emin olurum.', // 2
      'Akademik görevler gözümde genellikle büyür.', // 3
      'Yapmam gereken işer bana çoğu zaman zor gelir.', // 4
      'Başladığım akademik bir işi tamamlayabileceğimi düşünürüm.', // 5
      'Akademik görevler karşısında kendime güvenim düşüktür.', // 6
      'Çalışırsam başarabileceğimi hissederim.', // 7 (Ters)
      'Akademik görevler beni çoğu zaman korkutur.', // 8
      // B) Zor Görevlerde Öz-Yeterlik (9-16)
      'Zor sorular karşısında kendime olan güvenim azalır.', // 9
      'Zor konular benim için aşılması güç engeller gibidir.', // 10
      'Zorlandığımda yapamayacağımı düşünmeye başlarım.', // 11
      'Zor görevler beni motive eder.', // 12 (Ters)
      'Zor konularda da başarılı olabileceğime inanırım.', // 13 (Ters)
      'Zor bir dersle karşılaşınca güvenim düşer.', // 14
      'Zor görevlerde genellikle başkalarına ihtiyaç duyarım.', // 15
      'Zor görevlerin üstesinden gelebileceğimi düşünürüm.', // 16 (Ters is not mentioned in 16, but user prompt says 16 is implicitly standard)
      // Actually, looking at prompts:
      // A) 1, 2, 5 are positive. 3, 4, 6, 8 are negative. 7 is (Ters) but the prompt says "Çalışırsam başarabileceğimi hissederim (Ters)". This means agreement = High Self-Efficacy.
      // Wait, let's re-read numbering:
      // 1. İnanırım (Pos), 2. Emin olurum (Pos), 3. Büyür (Neg), 4. Zor gelir (Neg), 5. Düşünürüm (Pos), 6. Düşüktür (Neg), 7. Hissederim (Pos) (Ters), 8. Korkutur (Neg).
      // If 7 is Ters, it means standard is Neg. So 1,2,5 are also likely meant to be reversed later or treated specially.
      // Let's stick to user's "8. TERS MADDELER: 7, 12, 13, 21, 23, 30, 37, 38, 48" list.

      // C) Başarısızlık Sonrası Öz-Yeterlik (17-24)
      'Başarısızlık sonrası kendime olan güvenim sarsılır.', // 17
      'Kötü bir not aldıktan sonra “ben yapamıyorum” diye düşünürüm.', // 18
      'Başarısızlık beni uzun süre etkiler.', // 19
      'Bir başarısızlık tüm yeteneğimi sorgulamama neden olur.', // 20
      'Başarısızlık sonrası yeniden denemeye cesaret ederim.', // 21 (Ters)
      'Kötü bir sonuç öz-yeterliğimi düşürür.', // 22
      'Hatalarımı geliştirici olarak görebilirim.', // 23 (Ters)
      'Başarısızlık beni geri çeker.', // 24
      // D) Derslere Göre Değişen Güven (25-32)
      'Bazı derslerde kendime güvenirken bazılarında hiç güvenmem.', // 25
      'Öz-yeterliğim derse göre çok değişir.', // 26
      'Sayısal derslerde kendime güvenim düşüktür.', // 27
      'Sözel derslerde daha yeterli hissederim.', // 28
      'Ders değiştikçe yapabilirim duygum değişir.', // 29
      'Tüm derslerde benzer düzeyde kendime güvenirim.', // 30 (Ters)
      'Bazı derslerde baştan kaybedeceğimi düşünürüm.', // 31
      'Güvenim derslere bağlı olarak dalgalanır.', // 32
      // E) Karşılaştırmaya Dayalı Öz-Yeterlik (33-40)
      'Kendimi sık sık arkadaşlarımla kıyaslarım.', // 33
      'Başkaları benden iyiyse kendime olan güvenim azalır.', // 34
      'Sınıftaki başarılı öğrenciler beni yıldırır.', // 35
      'Başkalarının performansı beni olumsuz etkiler.', // 36
      'Kendimi başkalarına göre değil, kendi ilerlememe göre değerlendiririm.', // 37 (Ters)
      'Başkalarının başarısı beni motive eder.', // 38 (Ters)
      'Kıyaslama yapmadan kendime güvenemem.', // 39
      'Akademik özgüvenim çevremdekilere bağlıdır.', // 40
      // F) Öz-Yeterlik Farkındalığı (41-50)
      'Akademik olarak kendimi yeterli biri olarak görüyorum.', // 41
      'Ne zaman güçlü ne zaman zayıf olduğumu bilirim.', // 42
      'Öz-yeterliğimin neden arttığını veya azaldığını fark ederim.', // 43
      'Kendime güvenim çoğu zaman gerçekçidir.', // 44
      'Güvenim bazen gerçeği yansıtmaz.', // 45
      'Kendimi olduğumdan güçlü görmüş olabilirim.', // 46
      'Bazen kendimi gereğinden fazla küçümsediğimi hissederim.', // 47
      'Öz-yeterliğimin geliştirilebileceğini düşünüyorum.', // 48 (Ters)
      'Güvenim çoğu zaman duruma bağlıdır.', // 49
      'Öz-yeterliğim zamanla değişir.', // 50
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
