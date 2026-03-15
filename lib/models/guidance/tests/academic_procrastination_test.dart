import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class AcademicProcrastinationTest extends GuidanceTestDefinition {
  @override
  String get id => 'academic_procrastination_v1';

  @override
  String get title => 'Akademik Erteleme Ölçeği (AEÖ)';

  @override
  String get description =>
      'Bu ölçek akademik görevlerin neden ve nasıl ertelendiğini; ertelemenin davranışsal, bilişsel ve duygusal kaynaklarını değerlendirmek amacıyla geliştirilmiştir. Ölçek tanı koymaz, tarama amaçlıdır.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'ae_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Göreve Başlama Güçlüğü (1-6)
      'Bir akademik göreve başlamak benim için zordur.', // 1
      'Nereden başlayacağımı bilemediğim için ertelerim.', // 2
      'Çalışmaya başlamak için uygun anı beklerim.', // 3
      'Başladığımda devam etmekte zorlanırım.', // 4
      'Küçük bir adımla başlamayı başarabilirim.', // 5 (Reverse)
      'Göreve başlama düşüncesi bile beni yorar.', // 6
      // B) Duygusal Kaçınma (7-12)
      'Çalışma düşüncesi bende rahatsızlık yaratır.', // 7
      'Canım istemediğinde akademik işleri ertelerim.', // 8
      'Olumsuz duygular ertelememe neden olur.', // 9
      'Rahatsız hissetmemek için ödevden uzak dururum.', // 10
      'Duygularımı düzenleyerek çalışabilirim.', // 11 (Reverse)
      'Çalışma duygusal olarak beni zorlar.', // 12
      // C) Bilişsel Erteleme Gerekçeleri (13-18)
      'Daha sonra daha iyi yapacağımı düşünürüm.', // 13
      'Yeterince hazır hissetmeden başlamak istemem.', // 14
      'Zamanım varmış gibi davranırım.', // 15
      'Ertelememi mantıklı gerekçelerle açıklarım.', // 16
      'Ertelemenin beni zor durumda bıraktığını fark ederim.', // 17 (Reverse)
      'Son anda daha iyi çalıştığımı düşünürüm.', // 18
      // D) Mükemmeliyetçilik & Kendini Sabotaj (19-24)
      'Mükemmel yapamayacaksam hiç başlamam.', // 19
      'Küçük hatalar motivasyonumu düşürür.', // 20
      'Kendimden beklentilerim çok yüksektir.', // 21
      'Başarısız olma ihtimali beni durdurur.', // 22
      'Elimden geleni yapmanın yeterli olduğunu kabul ederim.', // 23 (Reverse)
      'Yüksek beklentilerim ertelememe yol açar.', // 24
      // E) Zaman Yönetimi & Planlama (25-30)
      'Zamanımı planlamakta zorlanırım.', // 25
      'Çalışma programına uymakta güçlük çekerim.', // 26
      'Günlük işler akademik görevlerin önüne geçer.', // 27
      'Zamanı etkili kullanabilirim.', // 28 (Reverse)
      'Ne zaman çalışacağımı netleştirmem.', // 29
      'Plan yapmadan ilerlemeye çalışırım.', // 30
      // F) Motivasyon & Amaç Netliği (31-36)
      'Akademik hedeflerim nettir.', // 31 (Reverse)
      'Neden çalışmam gerektiğini bazen unuturum.', // 32
      'Çalışmanın uzun vadeli faydasını göz ardı ederim.', // 33
      'Kısa vadeli zevkleri tercih ederim.', // 34
      'Hedeflerim beni harekete geçirir.', // 35 (Reverse)
      'Amaçsızlık ertelememe yol açar.', // 36
      // G) Genel Erteleme & Çeldirici Maddeler (37-54)
      'Akademik görevleri genelde zamanında yaparım.', // 37 (Çeldirici)
      'Erteleme benim için ciddi bir sorun değildir.', // 38 (Çeldirici)
      'Akademik sorumluluklarımı iyi yönetirim.', // 39 (Çeldirici)
      'Çoğu zaman son ana bırakırım.', // 40
      'Erteleme alışkanlık haline gelmiştir.', // 41
      'Bazen ertelediğimin farkında bile olmam.', // 42
      'Ertelememin nedenleri karışıktır.', // 43
      'Bazı dönemler çok ertelerim, bazı dönemler hiç.', // 44
      'Ertelemeyi kontrol edebileceğimi düşünüyorum.', // 45 (Reverse)
      'Ertelemeyle başa çıkma konusunda kararsızım.', // 46
      'Erteleme beni akademik olarak zorlar.', // 47
      'Ertelediğim için kendime kızarım.', // 48
      'Erteleme sonrası yoğun stres yaşarım.', // 49
      'Ertelemem başarıma zarar verir.', // 50
      'Ertelemeyle baş etmeyi öğrenmem gerektiğini hissederim.', // 51
      'Erteleme bazen beni rahatlatır.', // 52
      'Ertelemenin geçici olduğunu düşünürüm.', // 53
      'Erteleme davranışım beni tanımlar gibi hissederim.', // 54
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
