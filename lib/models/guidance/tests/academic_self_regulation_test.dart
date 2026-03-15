import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class AcademicSelfRegulationTest extends GuidanceTestDefinition {
  @override
  String get id => 'academic_self_regulation_v1';

  @override
  String get title => 'Akademik Öz-Düzenleme ve Planlama Ölçeği (AÖDPÖ)';

  @override
  String get description =>
      'Bu ölçek; bireyin akademik süreçlerde hedef belirleme, plan yapma, uygulama ve süreci izleme becerilerini ölçer. "Bilmek" ile "yapabilmek" arasındaki niyet-davranış uyumunu ortaya koymayı amaçlar.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'aodp_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Hedef Belirleme Netliği (1-10)
      'Akademik hedeflerim nettir.',
      'Ne için çalıştığımı çoğu zaman bilirim.',
      'Hedeflerimi yazılı veya zihinsel olarak belirlerim.',
      'Çalışırken hangi konunun öncelikli olduğunu bilirim.',
      'Kısa vadeli hedefler koyarım.',
      'Uzun vadeli hedeflerim vardır.',
      'Ne zaman neyi başarmak istediğim bellidir.',
      'Hedeflerim sık sık değişir.', // 8
      'Ne yapacağımı bilmeden çalışmaya başlarım.', // 9
      'Hedefim olmadığında çalışmak zorlaşır.',

      // B) Planlama ve Organizasyon (11-20)
      'Çalışma planı yaparım.',
      'Günlük veya haftalık planlar hazırlarım.',
      'Dersleri belli bir sıraya koyarım.',
      'Çalışma süremi önceden belirlerim.',
      'Plan yapmadan çalışmaya başlarım.', // 15
      'Planlarım gerçekçidir.',
      'Hangi gün ne çalışacağımı bilirim.',
      'Plan yapmayı gereksiz bulurum.', // 18
      'Planım bozulduğunda yenisini yaparım.',
      'Plansız çalışmak beni zorlar.',

      // C) Planı Uygulama ve Sürdürme (21-30)
      'Yaptığım plana çoğu zaman uyarım.',
      'Başladığım işi yarım bırakırım.', // 22
      'Planlı çalışırken daha verimli olurum.',
      'Planı uygulamakta zorlanırım.', // 24
      'Motivasyonum düşse bile plana devam ederim.',
      'Küçük aksamalarda tamamen vazgeçmem.',
      'Planımı sürdürmek için kendimi zorlarım.',
      'Planlarım genelde kâğıt üzerinde kalır.', // 28
      'Başladığım çalışmayı bitirmeye önem veririm.',
      'Planı uygulamak benim için zordur.', // 30
      // D) Zaman ve Dikkat Yönetimi (31-40)
      'Zamanımı iyi kullandığımı düşünürüm.',
      'Çalışırken dikkatim kolay dağılır.', // 32
      'Ne kadar süre çalışacağımı ayarlayabilirim.',
      'Gereksiz şeyler zamanımı alır.', // 34
      'Çalışma sırasında odaklanabilirim.',
      'Molalarımı kontrol edebilirim.',
      'Zamanın nasıl geçtiğini fark etmem.', // 37
      'Dikkatimi toplamakta zorlanırım.', // 38
      'Zaman baskısı altında daha dağılırım.', // 39
      'Çalışma süresini bilinçli yönetirim.',

      // E) Süreci İzleme ve Öz-Değerlendirme (41-50)
      'Çalışmamın işe yarayıp yaramadığını düşünürüm.',
      'Hatalarımdan ders çıkarırım.',
      'Ne kadar ilerlediğimi kontrol ederim.',
      'Çalışma yöntemimi gerektiğinde değiştiririm.',
      'Aynı hataları tekrarlarım.', // 45
      'Sonuçlara bakarak planımı düzenlerim.',
      'Neyi iyi yaptığımı fark ederim.',
      'Neyi yanlış yaptığımı görmekte zorlanırım.', // 48
      'Kendi çalışma sürecimi değerlendiririm.',
      'Çalışma sonunda kendime geri bildirim veririm.',
    ];

    final options = ['Evet', 'Kısmen', 'Hayır'];

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
