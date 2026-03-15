import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class TimeManagementDisciplineTest extends GuidanceTestDefinition {
  @override
  String get id => 'time_management_discipline_v1';

  @override
  String get title => 'Zaman Yönetimi ve Akademik Öz-Disiplin Ölçeği (ZYÖDÖ)';

  @override
  String get description =>
      'Bireyin akademik görevlerde zamanı planlama, uygulama, dikkati sürdürme, ertelemeyi kontrol etme ve başladığı işi bitirme becerilerini değerlendirir.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'zyodo_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Zaman Planlama Becerisi (1-13)
      'Derslerim için günlük plan yaparım.',
      'Haftalık çalışma programım vardır.',
      'Zamanımı bilinçli kullanırım.',
      'Yapmam gereken işleri önceden planlarım.',
      'Gün içinde önceliklerimi belirlerim.',
      'Çalışma süremi kontrol edebilirim.',
      'Zamanımın nasıl geçtiğinin farkındayımdır.',
      'Plansız çalışırım.', // 8
      'Program yapmadan ilerlerim.', // 9
      'Zamanı genellikle boşa harcarım.', // 10
      'Çalışma saatlerimi netleştiririm.',
      'Zaman yönetiminde zorlanırım.', // 12
      'Günlük hedefler belirlerim.',

      // B) Erteleme ve Kaçınma Eğilimi (14-25)
      'Yapmam gereken işleri son ana bırakırım.', // 14
      'Çalışmayı sık sık ertelerim.',
      'Zor görevlerden kaçınırım.',
      'Başlamak benim için zordur.',
      '“Sonra yaparım” demeyi sık kullanırım.',
      'Erteleme alışkanlığım vardır.',
      'Yapmam gereken işi geciktiririm.',
      'Başlamak yerine oyalanırım.', // 21
      'Hemen işe koyulurum.',
      'Ertelemeyi kontrol edebilirim.',
      'İşleri zamanında başlatırım.',
      'Kaçınmadan çalışabilirim.', // 25
      // C) Dikkati Sürdürme ve Devamlılık (26-36)
      'Çalışırken dikkatim çabuk dağılır.', // 26
      'Uzun süre odaklanabilirim.',
      'Başladığım işi sürdürürüm.',
      'Dikkatim sık sık bölünür.', // 29
      'Çalışma sırasında koparım.',
      'Dikkatimi toparlamakta zorlanırım.',
      'Bir görevi yarım bırakırım.', // 32
      'Odaklanınca verimli çalışırım.',
      'Çalışma süresini tamamlarım.',
      'Zihinsel devamlılığım iyidir.',
      'Dikkatimi yeniden toplayabilirim.', // 36
      // D) Öz-Disiplin ve Sorumluluk (37-52)
      'Sorumluluklarımı yerine getiririm.',
      'Kendime koyduğum kurallara uyarım.',
      'İsteksiz olsam da görevimi yaparım.',
      'Disiplinli çalışabilirim.',
      'Çalışmayı ertelememek için kendimi zorlarım.',
      'Planıma sadık kalırım.',
      'Kendimi kontrol edebilirim.',
      'Motivasyonum olmasa da çalışarım.',
      'Disiplinsizim.', // 45
      'Kendimi denetlemekte zorlanırım.',
      'Sorumluluk almaktan kaçınırım.',
      'Bırakma eğilimim yüksektir.',
      'Görevleri tamamlamakta zorlanırım.', // 49
      'Kendi kendimi yönetebilirim.',
      'Çalışma alışkanlığım vardır.',
      'Düzenli çalışırım.', // 52
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
