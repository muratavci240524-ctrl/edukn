import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class PostExamSelfEvaluationTest extends GuidanceTestDefinition {
  @override
  String get id => 'post_exam_self_evaluation_v1';

  @override
  String get title => 'Sınav Sonrası Öz Değerlendirme Ölçeği (SÖDÖ)';

  @override
  String get description =>
      'Bu ölçek sınav başarısını değil, sınavdan öğrenme becerisini değerlendirir. Bireyin sınav sonrası performans analizi, hatalardan öğrenme ve duygusal düzenleme becerilerini ölçmek amacıyla geliştirilmiştir.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'sod_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Performansı Gerçekçi Değerlendirme (1-6)
      'Sınav sonucuma gerçekçi bir gözle bakabilirim.', // 1 (Ters)
      'Sınavdan sonra kendimi ya çok överim ya çok eleştiririm.', // 2
      'Sınav performansımı doğru değerlendirdiğimi düşünürüm.', // 3 (Çeldirici)
      'Sınav sonucunu kişisel değerimle eş tutarım.', // 4
      'Başarı veya başarısızlığı tek bir nedene bağlarım.', // 5
      'Performansımı artıları ve eksileriyle ele alırım.', // 6 (Ters)
      // B) Hata Analizi ve Öğrenme (7-13)
      'Yanlış yaptığım soruları incelemekten kaçınırım.', // 7
      'Yanlışlarımın nedenlerini bulmaya çalışırım.', // 8 (Ters)
      'Aynı tür yanlışları sık tekrar ederim.', // 9
      'Yanlışlarımı analiz etmek bana fayda sağlar.', // 10 (Ters)
      'Yanlışlarımı görmek moralimi bozar.', // 11
      'Yanlışlardan öğrenmeye çalışırım.', // 12 (Ters)
      'Yanlış yaptığım konulara geri dönerim.', // 13 (Ters)
      // C) Duygusal Tepkilerle Baş Etme (14-19)
      'Sınavdan sonra duygularım düşünmemi zorlaştırır.', // 14
      'Hayal kırıklığı yaşadığımda değerlendirme yapamam.', // 15
      'Sınavdan sonra sakinleşip değerlendirme yapabilirim.', // 16 (Ters)
      'Başarısızlık duygusu beni uzun süre etkiler.', // 17
      'Sınav sonrası kendimi suçlama eğilimim vardır.', // 18
      'Duygularımı kontrol edip durumu analiz edebilirim.', // 19 (Ters)
      // D) Geri Bildirim Kullanımı (20-25)
      'Öğretmenlerin geri bildirimlerini dikkate alırım.', // 20 (Ters)
      'Geri bildirimler beni savunmaya iter.', // 21
      'Başkalarının yorumları değerlendirmemi etkiler.', // 22
      'Geri bildirimleri gelişim için kullanırım.', // 23 (Ters)
      'Eleştirilmek beni rahatsız eder.', // 24
      'Geri bildirimler sayesinde eksiklerimi görürüm.', // 25 (Ters)
      // E) Sorumluluk Alma ve Öz Farkındalık (26-30)
      'Sonucun sorumluluğunu kendimde görürüm.', // 26 (Ters)
      'Başarısızlıkta dış etkenleri suçlarım.', // 27
      'Kendi payımı fark edebilirim.', // 28 (Ters)
      'Hatalarımın farkında olmam zordur.', // 29
      'Kendimi objektif değerlendirebilirim.', // 30 (Ters)
      // F) Geleceğe Yönelik Düzenleme (31-36)
      'Bir sonraki sınav için neyi değiştirmem gerektiğini bilirim.', // 31 (Ters)
      'Aynı şekilde devam ederim.', // 32
      'Sınavdan ders çıkarırım.', // 33 (Ters)
      'Gelecek sınavlar için plan yaparım.', // 34 (Ters)
      'Sınavdan sonra kısa sürede motivasyonumu kaybederim.', // 35
      'Öz değerlendirme yapmadan yeni sınava geçerim.', // 36
      // G) Genel Öz Değerlendirme & Çeldirici (37-44)
      'Sınavlardan yeterince ders çıkardığımı düşünüyorum.', // 37 (Çeldirici)
      'Sınav sonrası değerlendirme benim için zor bir süreçtir.', // 38
      'Değerlendirme yapmayı gereksiz bulurum.', // 39
      'Sınavdan öğrenmeyi başaran biriyim.', // 40 (Çeldirici)
      'Öz değerlendirme becerilerim geliştirilebilir.', // 41 (Ters)
      'Sınavdan sonra olanları hızlıca unutmak isterim.', // 42
      'Sınavlar benim için öğrenme fırsatıdır.', // 43 (Ters)
      'Sınav sonrası değerlendirme sürecini yönetebilirim.', // 44 (Ters)
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
