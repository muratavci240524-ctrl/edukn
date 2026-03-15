import '../../../models/survey_model.dart';
import 'guidance_test_definition.dart';

class BurdonAttentionTest extends GuidanceTestDefinition {
  @override
  String get id => 'burdon_v1';

  @override
  String get title => 'Burdon Dikkat Testi (BDT)';

  @override
  String get description =>
      'Bu test, seçici dikkat, dikkatin sürdürülmesi ve hata eğilimini ölçmek için tasarlanmıştır. '
      'Sayfada göreceğiniz karakterler arasından "a, b, d, g" harflerini bulup işaretlemeniz beklenmektedir. '
      'Her bölüm için kısıtlı süreniz vardır.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'burdon_section',
      title: 'Dikkat Testi Uygulaması',
      description:
          'Aşağıdaki tabloda "a, b, d, g" harflerini bulup üzerlerine tıklayarak işaretleyiniz.',
      questions:
          [], // Burdon test uses a custom UI instead of standard questions
    ),
  ];
}
