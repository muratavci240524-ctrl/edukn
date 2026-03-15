import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class ExamCognitiveProcessesTest extends GuidanceTestDefinition {
  @override
  String get id => 'exam_cognitive_processes_v1';

  @override
  String get title => 'Sınav Anı Bilişsel Süreçler Ölçeği (SABSÖ)';

  @override
  String get description =>
      'Bu ölçek; bireyin sınav sırasında yaşadığı zihinsel süreçleri değerlendirir. Bilgi düzeyinden ziyade, bilginin sınav anında erişilebilirliğini, dikkat sürekliliğini ve zaman yönetimini analiz etmeyi amaçlar.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'sabs_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Dikkat ve Odak Sürekliliği (1-10)
      'Sınavın başında dikkatim nettir.', // 1
      'Sınav ilerledikçe zihnim dağılır.', // 2
      'Aynı soruya uzun süre odaklanabilirim.', // 3
      'Gürültü veya hareket beni kolay etkiler.', // 4
      'Sınav boyunca zihnim sorudadır.', // 5
      'Dikkatim sınav sırasında sık sık başka yerlere gider.', // 6
      'Soruları okurken kopmalar yaşarım.', // 7
      'Odaklanma sorunum sınavın ortasında artar.', // 8
      'Dikkatimi tekrar toplamakta zorlanmam.', // 9
      'Sınav sonunda zihinsel yorgunluk artar.', // 10
      // B) Zihinsel Kilitlenme ve Donakalma (11-20)
      'Bildiğim sorularda bile kilitlenirim.', // 11
      'Bir soruya takılıp kalırım.', // 12
      'Zihnim bazen tamamen boşalır.', // 13
      'Kilitlendiğimde devam etmekte zorlanırım.', // 14
      'Zihinsel kilitlenme yaşadığımda paniklerim.', // 15
      'Kilitlenince başka soruya geçebilirim.', // 16
      'Kilitlenme kısa sürer.', // 17
      'Kilitlendiğimde zaman kaybederim.', // 18
      'Kilitlenme sınav sonucumu etkiler.', // 19
      'Kilitlenmeden çıkmak için yöntemim vardır.', // 20
      // C) İç Konuşma ve Kendine Telkin (21-30)
      'Sınavda kendimle konuşurum.', // 21
      '“Yapamayacağım” düşüncesi aklıma gelir.', // 22
      'Kendime moral veririm.', // 23
      'İç sesim beni olumsuz etkiler.', // 24
      'Hata yaptığımda kendime kızarım.', // 25
      'İç konuşmam dikkatimi bozar.', // 26
      'Kendime güven veren cümleler kurarım.', // 27
      'İç sesim sınav boyunca susmaz.', // 28
      'Olumsuz düşünceler soruya odaklanmamı zorlaştırır.', // 29
      'İç konuşmamı kontrol edebilirim.', // 30
      // D) Zaman Algısı ve Yönetimi (31-40)
      'Zamanı doğru kullandığımı düşünürüm.', // 31
      'Zamanın hızla aktığını hissederim.', // 32
      'Bir soruya ayırmam gereken süreyi bilirim.', // 33
      'Zaman baskısı beni panikletir.', // 34
      'Sınav sonunda zamanım yetmez.', // 35
      'Zamanımı kontrol altında tutabilirim.', // 36
      'Süreyi düşünmek dikkatimi bozar.', // 37
      'Zamanı fark etmeden tüketirim.', // 38
      'Zamanla yarışmak beni zorlar.', // 39
      'Zaman yönetimim sınav performansımı etkiler.', // 40
      // E) Soruya Bilişsel Yaklaşım (41-50)
      'Soruyu anlamadan işlem yaparım.', // 41
      'Soruyu dikkatle okurum.', // 42
      'Anahtar bilgileri fark ederim.', // 43
      'Soruyu hızlı ama doğru analiz ederim.', // 44
      'Sorunun ne istediğini kaçırırım.', // 45
      'Zor sorularda paniklerim.', // 46
      'Sorulara stratejik yaklaşırım.', // 47
      'Sorunun tamamını okumadan işaretlerim.', // 48
      'Yanlışlarım genelde dikkat hatasından olur.', // 49
      'Soru çözme sırasında mantığımı korurum.', // 50
    ];

    final options = [
      'Hiç Uygun Değil',
      'Kısmen Uygun',
      'Çoğunlukla Uygun',
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
