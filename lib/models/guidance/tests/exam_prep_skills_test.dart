import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class ExamPrepSkillsTest extends GuidanceTestDefinition {
  @override
  String get id => 'exam_prep_skills_v1';

  @override
  String get title => 'Sınavlara Hazırlık Beceri Ölçeği (SHBÖ)';

  @override
  String get description =>
      'Bu ölçek ders bilgisi düzeyini değil, sınavlara hazırlanma sürecindeki planlama, süreklilik, strateji ve öz değerlendirme becerilerini ölçmek amacıyla geliştirilmiştir. Ölçek tanı koymaz, tarama amaçlıdır.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'shb_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Çalışma Planı Oluşturma (1-7)
      'Sınavlara hazırlanırken yazılı bir plan yaparım.', // 1 (Ters)
      'Ne zaman ne çalışacağımı önceden belirlerim.', // 2 (Ters)
      'Çalışma planı yaparım ama çoğu zaman uymam.', // 3
      'Plansız çalıştığımı fark ederim.', // 4
      'Plan yapmanın gereksiz olduğunu düşünürüm.', // 5
      'Günlük ve haftalık hedefler belirlerim.', // 6 (Ters)
      'Çalışmaya başlamadan önce hedefim nettir.', // 7 (Ters)
      // B) Çalışma Sürekliliği ve Disiplin (8-14)
      'Çalışmaya başladıktan sonra devamını getirmekte zorlanırım.', // 8
      'Düzenli çalışmayı uzun süre sürdürebilirim.', // 9 (Ters)
      'Çalışma motivasyonum sık sık düşer.', // 10
      'Son günlere bırakma eğilimim vardır.', // 11
      'Çalışma saatlerim genellikle düzensizdir.', // 12
      'Planladığım sürede çalışmayı bırakırım.', // 13 (Düzenli mi bitiriyor yoksa sıkılıyor mu? Metinde "Planladığım sürede çalışmayı bırakırım" disiplin içinde ama süreklilik grubunda)
      'Çalışma disiplinim dönem içinde dalgalanır.', // 14
      // C) Stratejik Çalışma Becerisi (15-21)
      'Hangi derse nasıl çalışmam gerektiğini bilirim.', // 15 (Ters)
      'Her derse aynı şekilde çalışırım.', // 16
      'Zayıf olduğum konulara öncelik veririm.', // 17 (Ters)
      'Çalışırken zamanımı verimli kullanırım.', // 18 (Ters)
      'Zor konuları ertelemeyi tercih ederim.', // 19
      'Sadece kolay konulara yönelirim.', // 20
      'Çalışma yöntemlerimi sonuçlara göre değiştiririm.', // 21 (Ters)
      // D) Kaynak ve Materyal Kullanımı (22-27)
      'Kaynak seçiminde kararsız kalırım.', // 22
      'Aynı anda çok fazla kaynağa başlarım.', // 23
      'Kullandığım kaynakları bilinçli seçerim.', // 24 (Ters)
      'Kaynak değiştirmenin beni ilerleteceğini düşünürüm.', // 25
      'Bir kaynağı bitirmeden yenisine geçerim.', // 26
      'Kaynakları amacına uygun kullanırım.', // 27 (Ters)
      // E) Tekrar ve Pekiştirme (28-33)
      'Öğrendiğim konuları düzenli tekrar ederim.', // 28 (Ters)
      'Tekrar yapmaya yeterince zaman ayırmam.', // 29
      'Tekrarın önemini bilsem de uygulamam.', // 30
      'Unuttuğumu fark ettiğim konulara geri dönerim.', // 31 (Ters)
      'Tekrarlarım genellikle sınavdan hemen önce olur.', // 32
      'Tekrar yapmadığım için konuları unuturum.', // 33
      // F) Öz Değerlendirme ve Geri Bildirim (34-40)
      'Deneme sonuçlarını analiz ederim.', // 34 (Ters)
      'Yanlışlarımın nedenini araştırırım.', // 35 (Ters)
      'Denemelerdeki yanlışlarım beni demotive eder.', // 36
      'Yanlışlardan ders çıkarırım.', // 37 (Ters)
      'Deneme sonuçlarına göre planımı güncellerim.', // 38 (Ters)
      'Denemeleri sadece puan görmek için çözerim.', // 39
      'Geri bildirimlere kulak veririm.', // 40 (Ters)
      // G) Genel Hazırlık & Çeldirici Maddeler (41-50)
      'Sınavlara yeterince hazırlandığımı düşünürüm.', // 41 (Çeldirici)
      'Aslında nasıl çalışacağımı tam bilmiyorum.', // 42
      'Çalışıyorum ama ilerleme hissetmiyorum.', // 43
      'Sınavlara hazırlık süreci beni zihinsel olarak yorar.', // 44
      'Hazırlık sürecini kontrol edebildiğimi hissederim.', // 45 (Ters)
      'Hazırlık sürecim sınavdan sınava değişir.', // 46
      'Bazen çok çalışıp bazen tamamen bırakırım.', // 47
      'Sınavlara hazırlanmak benim için karmaşık bir süreçtir.', // 48
      'Hazırlık becerilerim geliştirilebilir.', // 49 (Ters)
      'Sınavlara nasıl hazırlanacağımı öğrenmem gerektiğini düşünüyorum.', // 50 (Ters)
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
