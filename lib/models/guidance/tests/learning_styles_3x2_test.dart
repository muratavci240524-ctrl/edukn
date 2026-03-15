import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class LearningStyles3x2Test extends GuidanceTestDefinition {
  @override
  String get id => 'learning_styles_3x2_v1';

  @override
  String get title => '3x2 Öğrenme Stilleri Ölçeği (3x2-ÖSÖ)';

  @override
  String get description =>
      'Bu ölçek bireyin sözel, görsel ve kinestetik bilgi türlerini algılama ve işleme süreçlerini değerlendirmek amacıyla geliştirilmiştir. Etiketleyici değil, profil çıkarıcı bir yapıdadır.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'ls_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> questions = [
      // A) Sözel Algılama (1-6)
      'Anlatılanları dinleyerek daha kolay öğrenirim.', // 1 (Ters)
      'Uzun sözlü anlatımlarda çabuk koparım.', // 2
      'Dinleyerek bilgi almak benim için zorlayıcıdır.', // 3
      'Bir konuyu önce sözlü duymak isterim.', // 4 (Ters)
      'Anlatım sırasında sözcükleri kaçırdığımda konuyu kaybederim.', // 5
      'Dinlediklerimi zihnimde canlandırırım.', // 6 (Çeldirici)
      // B) Sözel İşleme (7-12)
      'Anlattıklarımı tekrar ederek öğrenirim.', // 7 (Ters)
      'Konuyu başkasına anlattığımda daha iyi kavrarım.', // 8 (Ters)
      'Sözlü tekrarlar bana zaman kaybı gibi gelir.', // 9
      'Konuları yüksek sesle düşünerek çözerim.', // 10 (Ters)
      'Sözel ifade gerektiren görevlerde zorlanırım.', // 11
      'Kendi kendime konuşarak problem çözerim.', // 12 (Çeldirici)
      // C) Görsel Algılama (13-18)
      'Şema, grafik ve tabloları hızlıca anlarım.', // 13 (Ters)
      'Görsel olmayan anlatımlarda dikkatim dağılır.', // 14
      'Resim, şekil ve renkler öğrenmemi kolaylaştırır.', // 15 (Ters)
      'Metin ağırlıklı anlatımlar beni yorar.', // 16
      'Bir konuyu görmeden anlamam zor olur.', // 17
      'Görsel destek olsa da fark etmez.', // 18 (Çeldirici)
      // D) Görsel İşleme (19-24)
      'Öğrendiklerimi zihnimde görsellere dönüştürürüm.', // 19 (Ters)
      'Notlarımı şekil ve renklerle düzenlerim.', // 20 (Ters)
      'Görsel düzenleme yapmadan çalışırım.', // 21
      'Harita, akış şeması gibi araçları sık kullanırım.', // 22 (Ters)
      'Görsel düşünmek bana zor gelir.', // 23
      'Görselleri sadece süs olarak görürüm.', // 24 (Çeldirici)
      // E) Kinestetik Algılama (25-30)
      'Yaparak–deneyerek öğrenmek bana daha uygundur.', // 25 (Ters)
      'Uzun süre oturarak çalışmak beni zorlar.', // 26
      'Hareket etmeden öğrenmekte güçlük çekerim.', // 27
      'Deneme–yanılma bana zaman kaybettirir.', // 28 (Çeldirici)
      'Somut deneyim yaşamadan anlamam zor olur.', // 29
      'Dinlemek veya izlemek bana yeterlidir.', // 30 (Ters - çapraz)
      // F) Kinestetik İşleme (31-36)
      'Uygulama yapınca bilgiler kalıcı olur.', // 31 (Ters)
      'Öğrendiklerimi kullanmadıkça unuturum.', // 32 (Ters)
      'Teorik bilgilerle çalışmak bana yeterlidir.', // 33
      'Aktif rol almadığım öğrenmelerde zorlanırım.', // 34 (Ters)
      'Hata yaparak öğrenmek beni rahatsız eder.', // 35
      'Deneyimleyerek öğrenmek bana karmaşık gelir.', // 36 (Çeldirici)
      // G) Genel & Çeldirici Maddeler (37-48)
      'Tek bir öğrenme stilim olduğunu düşünüyorum.', // 37 (Çeldirici)
      'Öğrenme tarzım ortama göre değişir.', // 38 (Ters)
      'Her konuda aynı şekilde öğrenirim.', // 39
      'Farklı öğrenme yollarını birlikte kullanırım.', // 40 (Ters)
      'Öğrenme stilimi hiç düşünmem.', // 41
      'Öğrenme şeklim geliştirilebilir.', // 42 (Ters)
      'Öğrenme tercihlerim net değildir.', // 43
      'Bazı konularda görsel, bazılarında uygulamalı öğrenirim.', // 44 (Ters)
      'Öğrenme stilim başarımı etkiler.', // 45 (Çeldirici)
      'Öğrenme tarzım değişmez.', // 46
      'Öğrenme sürecimi bilinçli yönetirim.', // 47 (Ters)
      'Farklı yöntemler beni daha iyi öğrenen biri yapar.', // 48 (Ters)
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
