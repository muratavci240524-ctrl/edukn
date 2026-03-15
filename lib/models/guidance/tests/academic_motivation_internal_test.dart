import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class AcademicMotivationInternalTest extends GuidanceTestDefinition {
  @override
  String get id => 'academic_motivation_internal_v1';

  @override
  String get title => 'Akademik Motivasyon ve İçsel Güdülenme Ölçeği (AM-İGÖ)';

  @override
  String get description =>
      'Bireyin içsel öğrenme isteğini, akademik anlam algısını ve dışsal baskılara karşı tutumunu analiz eder.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'motivation_internal_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<Map<String, dynamic>> items = [
      // A) İçsel Öğrenme İsteği (1-11)
      {'text': 'Öğrenmek bana keyif verir.'},
      {'text': 'Sadece not için çalışırım.', 'reverse': true}, // 2
      {'text': 'Merak ettiğim konuları araştırırım.'},
      {'text': 'Dersler benim ilgimi çekmez.', 'reverse': true}, // 4
      {'text': 'Yeni şeyler öğrenmek isterim.'},
      {'text': 'Öğrenmek benim için yük gibidir.', 'reverse': true}, // 6
      {'text': 'Bilgi edinmek beni tatmin eder.'},
      {'text': 'Ders çalışmayı gereksiz bulurum.', 'reverse': true}, // 8
      {'text': 'Öğrenirken zamanın geçtiğini fark etmem.'},
      {'text': 'Öğrenmeye karşı isteksizim.', 'reverse': true}, // 10
      {'text': 'Öğrenme isteğim içimden gelir.'},

      // B) Dışsal Baskı ve Zorunluluk Algısı (12-21)
      {'text': 'Ailem istediği için çalışırım.'},
      {'text': 'Çalışmazsam sorun olur diye çalışırım.'},
      {'text': 'Kimse zorlamasa çalışmam.', 'reverse': true}, // 14
      {'text': 'Not korkusu beni motive eder.'},
      {'text': 'Başkalarının beklentisi beni etkiler.'},
      {'text': 'Sadece ceza almamak için çalışırım.', 'reverse': true}, // 17
      {'text': 'Ödül olmasa çaba göstermem.', 'reverse': true}, // 18
      {'text': 'Baskı olmadan da çalışabilirim.'},
      {'text': 'Zorunluluk beni harekete geçirir.'},
      {'text': 'Kendi isteğim baskıdan daha etkilidir.'},

      // C) Anlam ve Amaç Oluşturma (22-31)
      {'text': 'Derslerin hayatımla bağlantısını görürüm.'},
      {
        'text': 'Öğrendiklerimin ne işe yaradığını bilmem.',
        'reverse': true,
      }, // 23
      {'text': 'Çalışmanın bir amacı vardır benim için.'},
      {'text': 'Dersler anlamsız gelir.', 'reverse': true}, // 25
      {'text': 'Öğrenmenin bana katkısını fark ederim.'},
      {'text': 'Neden çalıştığımı bilmem.', 'reverse': true}, // 27
      {'text': 'Dersleri geleceğimle ilişkilendiririm.'},
      {'text': 'Amaç göremezsem çalışmam.', 'reverse': true}, // 29
      {'text': 'Öğrenmenin bir anlamı vardır.'},
      {
        'text': 'Dersler benim için sadece zorunluluktur.',
        'reverse': true,
      }, // 31
      // D) Başarıya Yönelik Tutum (32-41)
      {'text': 'Başarmak beni motive eder.'},
      {'text': 'Başarısızlık beni tamamen durdurur.', 'reverse': true}, // 33
      {'text': 'Kendimi geliştirmek isterim.'},
      {'text': 'Başarı benim için önemli değildir.', 'reverse': true}, // 35
      {'text': 'Başarı için çaba gösteririm.'},
      {'text': 'Başaramayacağımı düşününce vazgeçerim.', 'reverse': true}, // 37
      {'text': 'Başarı süreciyle ilgilenirim.'},
      {'text': 'Sonuç benim için önemsizdir.', 'reverse': true}, // 39
      {'text': 'İlerleme görmek beni motive eder.'},
      {'text': 'Başarı beni heyecanlandırır.'},

      // E) Zorlanmaya Karşı Dayanıklılık (42-51)
      {'text': 'Zorlandığımda devam ederim.'},
      {'text': 'Zorlanınca bırakırım.', 'reverse': true}, // 43
      {'text': 'Emek gerektiren işleri yapabilirim.'},
      {'text': 'Çabuk pes ederim.', 'reverse': true}, // 45
      {'text': 'Zorluk beni geliştirir.'},
      {'text': 'Zorlandığımda motivasyonum düşer.', 'reverse': true}, // 47
      {'text': 'Sabırlı olabilirim.'},
      {'text': 'Zorluklar beni durdurmaz.'},
      {'text': 'Zor işler beni korkutur.', 'reverse': true}, // 50
      {'text': 'Mücadele edebilirim.'},

      // F) Akademik Gönüllülük (52-66)
      {'text': 'Kimse söylemeden çalışırım.'},
      {'text': 'Hatırlatılmadan çalışmam.', 'reverse': true}, // 53
      {'text': 'Sorumluluk alırım.'},
      {
        'text': 'Çalışmak için sürekli yönlendirilmem gerekir.',
        'reverse': true,
      }, // 55
      {'text': 'Kendi planımı yapabilirim.'},
      {'text': 'Kendi kendime çalışmak zor gelir.', 'reverse': true}, // 57
      {'text': 'Çalışmayı ben başlatırım.'},
      {
        'text': 'Akademik sorumluluk almaktan kaçınırım.',
        'reverse': true,
      }, // 59
      {'text': 'Gönüllü olarak çalışırım.'},
      {'text': 'Kendi öğrenmemden sorumluyum.'},
      {'text': 'Başkasına bağlı olmadan çalışabilirim.'},
      {'text': 'Kendi isteğimle çaba gösteririm.'},
      {'text': 'Çalışmak benim tercihimdir.'},
      {'text': 'Zorlanmadan gönüllü olurum.'},
      {'text': 'Akademik sorumluluk almaya hazırım.'},
    ];

    final options = [
      'Bana Hiç Uygun Değil',
      'Bana Az Uygun',
      'Bana Uygun',
      'Bana Çok Uygun',
    ];

    return List.generate(items.length, (i) {
      final item = items[i];
      return SurveyQuestion(
        id: 'q${i + 1}',
        text: item['text'],
        type: SurveyQuestionType.singleChoice,
        isRequired: true,
        options: options,
      );
    });
  }
}
