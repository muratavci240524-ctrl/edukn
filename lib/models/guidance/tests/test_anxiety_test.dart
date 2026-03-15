import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class TestAnxietyTest extends GuidanceTestDefinition {
  @override
  String get id => 'test_anxiety_v1';

  @override
  String get title => 'Sınav Kaygısı Ölçeği (SKÖ)';

  @override
  String get description =>
      'Bu ölçek, sınavlara hazırlık ve sınav anındaki duygu, düşünce ve bedensel tepkilerinizi belirlemek amacıyla hazırlanmıştır. 50 maddeden oluşan bu çalışmada, her maddeyi dikkatle okuyarak size uygunsa "Doğru", uygun değilse "Yanlış" seçeneğini işaretleyiniz. Bu ölçek bir başarı testi değildir, kendinizi en iyi yansıtan yanıtları vermeniz sonuçların doğruluğu için önemlidir.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'sk_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<String> texts = [
      'Sınava girmeden de sınıf geçmenin ve başarılı olmanın bir yolu olmasını isterdim',
      'Bir sınavda başarılı olmak, diğer sınavlarda kendime güvenimin artmasına sebep olmaz',
      'Çevremdekiler (ailem, arkadaşlarım) başaracağım konusunda bana güveniyorlar',
      'Bir sınav sırasında, bazen zihnimin sınavla ilgili olmayan konulara kaydığını zannediyorum',
      'Önemli bir sınavdan önce / sonra canım bir şey yapmak istemez',
      'Öğretmenin sık sık küçük yazılı veya sözlü yoklamalar yaptığı derslerden nefret ederim',
      'Sınavların mutlaka resmi, ciddi ve gerginlik yaratan durumlar olması gerekmez',
      'Sınavlarda başarılı olanlar çoğunlukla hayatta da iyi pozisyonlara gelirler',
      'Önemli bir sınavdan önce veya sınav sırasında bazı arkadaşlarımın çalışırken daha az zorlandıklarını ve benden daha akıllı olduklarını düşünürüm',
      'Eğer sınavlar olmasaydı dersleri daha iyi öğreneceğimden eminim',
      'Ne kadar başarılı olacağım konusundaki endişeler, sınava hazırlığımı ve sınav başarımı etkiler',
      'Önemli bir sınava girecek olmam uykularımı bozar',
      'Sınav sırasında çevremdeki insanların gezinmesi ve bana bakmalarından sıkıntı duyarım',
      'Her zaman düşünmesem de, başarısız olursam çevremdekilerin bana hangi gözle bakacaklarından endişelenirim',
      'Geleceğimin sınavlarda göstereceğim başarıya bağlı olduğunu bilmek beni üzüyor',
      'Kendimi bir toplayabilsem, bir çok kişiden daha iyi notlar alacağımı biliyorum',
      'Başarısız olursam, insanlar benim yeteneğimden şüpheye düşecekler',
      'Hiçbir zaman sınavlara tam olarak hazırlandığım duygusunu yaşayamam',
      'Bir sınavdan önce bir türlü gevşeyemem',
      'Önemli sınavlardan önce zihnim adeta durur kalır',
      'Bir sınav sırasında dışarıdan gelen gürültüler, çevremdekilerin çıkardıkları sesler, ışık, oda sıcaklığı, vb. beni rahatsız eder',
      'Sınavdan önce daima huzursuz, gergin ve huzursuz olurum',
      'Sınavların insanın gelecekteki amaçlarına ulaşması konusunda ölçü olmasına hayret ederim',
      'Sınavlar insanın gerçekten ne kadar bildiğini göstermez',
      'Düşük not aldığımda hiç kimseye notumu söylemem',
      'Bir sınavdan önce çoğunlukla içimden bağırmak gelir',
      'Önemli sınavlardan önce midem bulanır',
      'Önemli bir sınava hazırlanırken çok kere olumsuz düşüncelerle peşin bir yenilgiyi yaşarım',
      'Sınav sonuçlarını almadan önce kendimi çok endişeli ve huzursuz hissederim',
      'Bir sınav veya teste başlarken ihtiyaç duyulmayan bir işe girebilmeyi çok isterim',
      'Bir sınavda başarılı olamazsam, zaman zaman zannettiğim kadar akıllı olamadığımı düşünürüm',
      'Eğer kırık not alırsam, annem ve babam müthiş hayal kırıklığına uğrar',
      'Sınavlarla ilgili endişelerim çoğunlukla tam olarak hazırlanmamı engeller ve bu durum beni daha çok endişelendirir',
      'Sınav sırasında, bacağımı salladığımı, parmaklarımı sıraya vurduğumu hissediyorum',
      'Bir sınavdan sonra çoğunlukla yapmış olduğumdan daha iyi yapabileceğimi düşünürüm',
      'Bir sınav sırasında duygularım dikkatimin dağılmasına neden olur',
      'Bir sınava ne kadar çok çalışırsam, o kadar çok karıştırıyorum',
      'Başarısız olursam, kendimle ilgili görüşlerim değişir',
      'Bir sınav sırasında bedenimin belirli yerlerindeki kaslar kasılır',
      'Bir sınavdan önce ne kendime tam olarak güvenebilirim, ne de zihinsel olarak gevşeyebilirim',
      'Başarısız olursam arkadaşlarımın gözünde değerimin düşeceğini biliyorum',
      'Önemli problemlerimden biri, bir sınava tam olarak hazırlanıp hazırlanmadığımı bilememektir',
      'Gerçekten önemli bir sınava girerken çoğunlukla bedensel olarak panik halinde olurum',
      'Testi değerlendirenlerin, bazı öğrencilerin sınavda çok heyecanlandıklarını bilmelerini ve bunu testi değerlendirirken hesaba katmalarını isterdim',
      'Sınıf geçmek için sınava girmektense, ödev hazırlamayı tercih ederdim',
      'Kendi notumu söylemeden önce arkadaşlarımın kaç aldığını bilmek isterim',
      'Kırık not aldığım zaman, tanıdığım bazı insanların benimle alay edeceğini biliyorum ve bu beni rahatsız ediyor',
      'Eğer sınavlara yalnız başıma girsem ve zamanla sınırlanmamış olsam çok daha başarılı olacağımı düşünüyorum',
      'Sınavdaki sonuçların hayat başarım ve güvenliğimle doğrudan ilişkili olduğunu düşünürüm',
      'Sınavlar sırasında bazen gerçekten bildiklerimi unutacak kadar heyecanlanıyorum',
    ];

    return List.generate(texts.length, (i) {
      return SurveyQuestion(
        id: 'q${i + 1}',
        text: texts[i],
        type: SurveyQuestionType.singleChoice,
        isRequired: true,
        options: ['D', 'Y'],
      );
    });
  }
}
