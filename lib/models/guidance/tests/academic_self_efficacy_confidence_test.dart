import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class AcademicSelfEfficacyConfidenceTest extends GuidanceTestDefinition {
  @override
  String get id => 'academic_self_efficacy_confidence_v1';

  @override
  String get title => 'Öz-Yeterlik ve Akademik Kendine Güven Ölçeği (AÖKGÖ)';

  @override
  String get description =>
      'Bireyin akademik yeterlilik inancını, zorluklarla baş etme algısını ve kendine güven sürekliliğini analiz eder.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'self_eff_conf_questions',
      title: 'Sorular',
      questions: _getQuestions(),
    ),
  ];

  List<SurveyQuestion> _getQuestions() {
    final List<Map<String, dynamic>> items = [
      // A) Akademik Öz-Yeterlik İnancı (1-12)
      {'text': 'Zor derslerin üstesinden gelebilirim.', 'type': 'L'},
      {'text': 'İstersem çoğu akademik görevi başarabilirim.', 'type': 'L'},
      {'text': 'Yeni konular beni korkutmaz.', 'type': 'L'},
      {'text': 'Akademik olarak yeterli olduğuma inanırım.', 'type': 'L'},
      {'text': 'Çoğu derste başarılı olabileceğimi düşünürüm.', 'type': 'L'},
      {
        'text': 'Akademik görevler gözümde büyür.',
        'type': 'L',
        'reverse': true,
      }, // 6
      {'text': 'Çalışırsam sonuç alacağımı bilirim.', 'type': 'L'},
      {
        'text': 'Zor sorularla karşılaşınca paniklerim.',
        'type': 'L',
        'reverse': true,
      }, // 8
      {'text': 'Akademik sorunlara çözüm bulabilirim.', 'type': 'L'},
      {
        'text': 'Kendimi birçok kişiden daha yetersiz hissederim.',
        'type': 'L',
        'reverse': true,
      }, // 10
      {'text': 'Öğrendiklerimi uygulayabileceğime inanırım.', 'type': 'L'},
      {'text': 'Akademik becerilerime güvenirim.', 'type': 'L'},

      // B) Zorlukla Baş Etme Algısı (13-24)
      {'text': 'Zorlandığımda çözüm ararım.', 'type': 'B'},
      {
        'text': 'İlk denemede olmazsa vazgeçerim.',
        'type': 'B',
        'reverse': true,
      }, // 14
      {'text': 'Zorluk beni tamamen durdurmaz.', 'type': 'B'},
      {'text': 'Alternatif yollar denerim.', 'type': 'B'},
      {'text': 'Engellerle karşılaşınca devam edebilirim.', 'type': 'B'},
      {
        'text': 'Zorlandığımda başkalarına bırakırım.',
        'type': 'B',
        'reverse': true,
      }, // 18
      {'text': 'Zor görevler beni geliştirir.', 'type': 'B'},
      {
        'text': 'Baskı altında performansım düşer.',
        'type': 'B',
        'reverse': true,
      }, // 20
      {'text': 'Zor durumlarda sakin kalabilirim.', 'type': 'B'},
      {'text': 'Zorluklar beni yıldırır.', 'type': 'B', 'reverse': true}, // 22
      {'text': 'Sabırlı davranabilirim.', 'type': 'B'},
      {
        'text': 'Mücadele etmekten kaçınırım.',
        'type': 'B',
        'reverse': true,
      }, // 24
      // C) Başarıyı Sahiplenme (25-36)
      {'text': 'Başarımın nedeni kendi çabamdır.', 'type': 'L'},
      {'text': 'İyi notlar şans eseridir.', 'type': 'L', 'reverse': true}, // 26
      {'text': 'Sonuçlar üzerinde etkimin olduğunu düşünürüm.', 'type': 'L'},
      {'text': 'Başarımı kendime mal ederim.', 'type': 'L'},
      {'text': 'Çalışmamla başarı arasında bağ kurarım.', 'type': 'L'},
      {
        'text': 'Başarı çoğunlukla dış etkenlere bağlıdır.',
        'type': 'L',
        'reverse': true,
      }, // 30
      {'text': 'Ne yaparsam sonucu etkilerim.', 'type': 'L'},
      {'text': 'Başarıyı kontrol edebileceğimi hissederim.', 'type': 'L'},
      {'text': 'Kendi performansımı yönlendirebilirim.', 'type': 'L'},
      {
        'text': 'Sonuçlar benim dışımda gelişir.',
        'type': 'L',
        'reverse': true,
      }, // 34
      {'text': 'Başarıyı sahiplenirim.', 'type': 'L'},
      {'text': 'Emek vermenin karşılığını alırım.', 'type': 'L'},

      // D) Hata ve Başarısızlık Algısı (37-46)
      {'text': 'Hata yapmak beni geliştirir.', 'type': 'L'},
      {
        'text': 'Hata yaptığımda moralim tamamen bozulur.',
        'type': 'L',
        'reverse': true,
      }, // 38
      {'text': 'Yanlışlardan ders çıkarırım.', 'type': 'L'},
      {
        'text': 'Başarısızlık beni tanımlar.',
        'type': 'L',
        'reverse': true,
      }, // 40
      {'text': 'Hata yaptıktan sonra toparlanabilirim.', 'type': 'L'},
      {
        'text': 'Yanlış yapmaktan çok korkarım.',
        'type': 'L',
        'reverse': true,
      }, // 42
      {'text': 'Başarısızlık geçici olabilir.', 'type': 'L'},
      {
        'text': 'Hata yapınca kendime güvenim azalır.',
        'type': 'L',
        'reverse': true,
      }, // 44
      {'text': 'Denemeye devam edebilirim.', 'type': 'L'},
      {
        'text': 'Başarısızlık beni durdurur.',
        'type': 'L',
        'reverse': true,
      }, // 46
      // E) Akademik Kendine Güven Sürekliliği (47-60)
      {'text': 'Kendime olan güvenim kolay sarsılmaz.', 'type': 'B'},
      {
        'text': 'Küçük bir olumsuzluk beni geriye çeker.',
        'type': 'B',
        'reverse': true,
      }, // 48
      {'text': 'Uzun vadede güvenimi korurum.', 'type': 'B'},
      {'text': 'Başarılarım güvenimi artırır.', 'type': 'B'},
      {
        'text': 'Güvenim sık sık dalgalanır.',
        'type': 'B',
        'reverse': true,
      }, // 51
      {'text': 'Zamanla daha da güçlenirim.', 'type': 'B'},
      {'text': 'Yeni görevlerde kendime güvenirim.', 'type': 'B'},
      {
        'text': 'Başkaları benden daha iyidir diye düşünürüm.',
        'type': 'B',
        'reverse': true,
      }, // 54
      {'text': 'Akademik olarak sağlam dururum.', 'type': 'B'},
      {
        'text': 'Güvenim dış etkilere bağlıdır.',
        'type': 'B',
        'reverse': true,
      }, // 56
      {'text': 'Kendi potansiyelime inanırım.', 'type': 'B'},
      {
        'text': 'Kendimden sık sık şüphe ederim.',
        'type': 'B',
        'reverse': true,
      }, // 58
      {'text': 'Zorluklara rağmen güvenimi korurum.', 'type': 'B'},
      {'text': 'Akademik anlamda kendimden eminim.', 'type': 'B'},
    ];

    final likertOptions = [
      'Hiç Uygun Değil',
      'Az Uygun',
      'Kısmen Uygun',
      'Oldukça Uygun',
      'Tamamen Uygun',
    ];

    final behaviorOptions = ['Hayır', 'Bazen', 'Evet'];

    return List.generate(items.length, (i) {
      final item = items[i];
      return SurveyQuestion(
        id: 'q${i + 1}',
        text: item['text'],
        type: SurveyQuestionType.singleChoice,
        isRequired: true,
        options: item['type'] == 'L' ? likertOptions : behaviorOptions,
      );
    });
  }
}
