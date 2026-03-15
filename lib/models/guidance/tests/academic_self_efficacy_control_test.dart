import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class AcademicSelfEfficacyControlTest extends GuidanceTestDefinition {
  @override
  String get id => 'academic_self_efficacy_control_v1';

  @override
  String get title => 'Akademik Öz-Yeterlik ve Kontrol Algısı Ölçeği (AÖKÖ)';

  @override
  String get description =>
      'Bu ölçek; bireyin akademik görevlerdeki başarısını kendi çabasına mı, yoksa şansa ve dış etkenlere mi bağladığını ve "yapabilirim" inancının ne düzeyde olduğunu değerlendirir.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'aoko_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Akademik Öz-Yeterlik İnancı (1-12)
      'Zor bir konuyu çalışarak öğrenebilirim.',
      'Anlamadığım konuları çözebilirim.',
      'İstersem çoğu sınavda başarılı olabilirim.',
      'Akademik olarak yeterli olduğuma inanırım.',
      'Zorlandığım derslerin üstesinden gelebilirim.',
      'Öğrenme hızım yeterlidir.',
      'Çalışmam sonuç verir.',
      'Başaramayacağımı düşünürüm.', // 8
      'Bir konuyu öğrenmek benim elimdedir.',
      'Akademik açıdan kendime güvenirim.',
      'Zor sorular beni yıldırmaz.',
      'Yapamayacağımı düşündüğüm çok şey vardır.', // 12
      // B) İçsel Kontrol Algısı (13-24)
      'Başarım büyük ölçüde bana bağlıdır.',
      'Ne kadar çalışırsam o kadar sonuç alırım.',
      'Başarımı kendi çabam belirler.',
      'Sonuçlar benim kontrolümdedir.',
      'Plan yaparsam başarırım.',
      'Çalışma biçimim sonucu etkiler.',
      'Başarısızlıklarımın sorumluluğunu alırım.',
      'Sonuçları ben belirlerim.',
      'Doğru yöntemle her şey değişebilir.',
      'Kendi kararlarım önemlidir.',
      'Başarım tesadüf değildir.',
      'Ben istersem işler değişir.',

      // C) Dışsal Kontrol Algısı (25-35)
      'Sınavlar şansa bağlıdır.',
      'Öğretmenim iyiyse başarılı olurum.',
      'Sorular zorsa yapacak bir şey yoktur.',
      'Şartlar uygunsa başarılı olurum.',
      'Sistem adil olsaydı daha başarılı olurdum.',
      'Sonuçlar genellikle benim dışımda gelişir.',
      'Başarı çoğu zaman kısmete bağlıdır.',
      'Ne yaparsam yapayım sonuç değişmez.',
      'Dış etkenler daha belirleyicidir.',
      'Başarı çevresel faktörlere bağlıdır.',
      'Benim elimde olmayan çok şey var.', // 35
      // D) Çaba–Sonuç İlişkisi Algısı (36-50)
      'Çalışmazsam başaramam.',
      'Emek vermeden başarı olmaz.',
      'Yeterince çalışınca sonuç alırım.',
      'Az çalışarak başarılı olmak zordur.',
      'Çabamın karşılığını alırım.',
      'Planlı çalışmak sonucu değiştirir.',
      'Çaba göstermeden iyi not alınmaz.',
      'Başarı süreklilik ister.',
      'Çalışma süremle notlarım ilişkilidir.',
      'Çabam çoğu zaman boşa gider.', // 45
      'Ne kadar uğraşsam da fark etmez.', // 46
      'Çaba sonucu garanti etmez.', // 47
      'Çok çalışsam da başaramam.', // 48
      'Emek bazen anlamsızdır.', // 49
      'Sonuçlar çabadan bağımsızdır.', // 50
    ];

    final options = [
      'Hiç Uygun Değil',
      'Biraz Uygun',
      'Oldukça Uygun',
      'Tamamen Uygun',
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
