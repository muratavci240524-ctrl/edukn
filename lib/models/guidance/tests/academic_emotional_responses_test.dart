import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class AcademicEmotionalResponsesTest extends GuidanceTestDefinition {
  @override
  String get id => 'academic_emotional_responses_v1';

  @override
  String get title => 'Akademik Duygusal Tepkiler Ölçeği (ADTÖ)';

  @override
  String get description =>
      'Bu ölçek; bireyin akademik süreçler sırasında yaşadığı duygusal tepkileri, bu tepkilerin davranışa etkisini ve duygusal dayanıklılık düzeyini ölçmek amacıyla hazırlanmıştır. Sınav, hata ve başarı anlarındaki duygusal refleksleri analiz etmeyi amaçlar.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'adt_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Sınav Kaygısı ve Gerginlik (1-10)
      'Sınavdan önce yoğun gerginlik yaşarım.',
      'Sınav yaklaşınca ders çalışmak zorlaşır.',
      'Sınav anında bildiklerimi unutabilirim.',
      'Sınavdan önce fiziksel belirtiler yaşarım (çarpıntı vb.).',
      'Sınav düşüncesi beni huzursuz eder.',
      'Sınavlar beni fazlasıyla strese sokar.',
      'Sınavdan sonra uzun süre rahatlayamam.',
      'Sınavlar benim için baskı kaynağıdır.',
      'Sınav kelimesi bile kaygımı artırır.',
      'Sınavlar yüzünden uyku düzenim bozulur.',

      // B) Hata ve Başarısızlık Tepkileri (11-20)
      'Hata yaptığımda moralim hızla bozulur.',
      'Yanlış yaptığımda kendime kızarım.',
      'Başarısızlık beni uzun süre etkiler.',
      'Hata yapmaktan korktuğum için çekingen davranırım.',
      'Yanlışlarımı kişisel bir eksiklik gibi görürüm.',
      'Başarısız olduğumda motivasyonum düşer.',
      'Eleştirilmek beni zorlar.',
      'Hata yapınca denemekten vazgeçebilirim.',
      'Yanlışlar aklımda uzun süre kalır.',
      'Başarısızlık beni çalışmaktan soğutabilir.',

      // C) Duygusal Dayanıklılık (21-30)
      'Olumsuz sonuçlardan sonra toparlanabilirim.',
      'Hata yaptıktan sonra yeniden denemeye istekli olurum.',
      'Zorlandığımda pes etmem.',
      'Olumsuz duygularım zamanla azalır.',
      'Başarısızlık beni tamamen durdurmaz.',
      'Duygularımı kontrol altına alabilirim.',
      'Zor bir sınavdan sonra kendimi yeniden motive edebilirim.',
      'Moral bozukluğu uzun sürmez.',
      'Zorlandığımda çözüm ararım.',
      'Akademik stresle baş edebildiğimi hissederim.',

      // D) Akademik Heyecan ve Tatmin (31-40)
      'Başardığımda içten bir sevinç hissederim.',
      'Öğrenmek bana keyif verir.',
      'Zor bir soruyu çözmek beni mutlu eder.',
      'Akademik başarı beni duygusal olarak tatmin eder.',
      'Çalışmanın sonunda iyi hissettiğim olur.',
      'Derslerde ilerlediğimi hissetmek hoşuma gider.',
      'Anladığım konular beni heyecanlandırır.',
      'Öğrendikçe kendime güvenim artar.',
      'Akademik başarı beni motive eder.',
      'Çalışmanın duygusal bir karşılığı vardır.',

      // E) Kaçınma ve Duygusal Geri Çekilme (41-50)
      'Kaygılandığım konulardan uzak dururum.',
      'Zor dersleri ertelemeyi tercih ederim.',
      'Duygusal olarak zorlandığımda çalışmayı bırakırım.',
      'Derslerle ilgili duygularımdan kaçınarım.', // User wrote 'kaçınarım' in prompt, correcting to 'kaçınırım'
      'Kaygım arttığında derslerden soğurum.',
      'Zorlayıcı akademik durumları görmezden gelirim.',
      'Gerginlik hissettiğimde geri çekilirim.',
      'Derslerle ilgili konuşmak bile bazen zor gelir.',
      'Akademik baskı beni içe kapatır.',
      'Duygusal olarak zorlandığımda dersleri ikinci plana atarım.',
    ];

    final options = ['Evet', 'Hayır'];

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
