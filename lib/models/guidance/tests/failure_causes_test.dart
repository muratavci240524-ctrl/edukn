import '../../survey_model.dart';
import 'guidance_test_definition.dart';

class FailureCausesTest extends GuidanceTestDefinition {
  @override
  String get id => 'failure_causes_v1';

  @override
  String get title => 'Başarısızlık Nedenleri Anketi (BNA)';

  @override
  String get description =>
      'Bu anket, derslerinizdeki başarınızı artırmak ve başarısızlığa yol açan nedenleri tespit etmek amacıyla hazırlanmıştır. Aşağıdaki maddelerden size uygun olanları işaretleyiniz. Bu anket bir sınav değildir ve sonuçları sadece rehberlik amaçlı kullanılacaktır.';

  @override
  List<SurveySection> get sections => [
    SurveySection(
      id: 'section_main',
      title: 'Başarısızlık Nedenleri',
      questions: [
        SurveyQuestion(
          id: 'failure_reasons_checklist',
          text: 'Aşağıdaki nedenlerden sizin için geçerli olanları seçiniz:',
          type: SurveyQuestionType.multipleChoice,
          isRequired: false,
          options: [
            'Bir önceki okuldan ya da sınıftan iyi yetişmemiş olduğum için',
            'TV, oyun ve eğlenceye çok zaman ayırdığım için',
            'Yeterince dinlenip, özgürce eğlenmemiş olduğum için',
            'Karşı cinsten arkadaşlar başarım etkilediği için',
            'Ev işlerine ve kardeşlerime zaman ayırmak zorunda olduğum için',
            'Ailemden ayrı kaldığım (yurt, pansiyon vb.) için',
            'Ailemdeki huzursuzluk yüzünden ders çalışmaya zaman ayıramadığım için',
            'Okul-alan seçimini doğru yapmadığım için',
            'Günümün büyük bölümü okulda geçtiğinden, çalışmaya zaman bulamadığım için',
            'Ders çalışma programları çok ağır olduğu için',
            'Derslerin bazılarını bir türlü sevemediğim için',
            'Hayatta işimize yaramaz düşüncesi ile bazı derslere çalışmadığım için',
            'Laboratuvar çalışması yerine ezbercilik beklendiği için',
            'Okul idaresi sorunlarımızla ilgilenmediği için',
            'Sınıf rehber öğretmeni kişisel problemlerimle ilgilenmediği için',
            'Kendime uygun arkadaş edinemediğim için',
            'Bedensel rahatsızlıklarım olduğu için',
            'Aileme maddi katkı sağlamak zorunda olduğum için',
            'Kimseye açamadığım kişisel problemlerim olduğu için',
            'Ev ödevlerinin çokluğu derslerime engel olduğu için',
            'Meslek dersleri ile faaliyetler çok zamanımı aldığı için',
            'Ruh sağlığımın (moral) bozuk olması nedeni ile çalışmak istemediğim için',
            'Doğru dürüst beslenmediğim için',
            'Bir üst öğrenim devam şansım az olduğu için',
            'Maddi sıkıntılar içinde olduğum için',
            'Bazı öğretmenler dersleri düzeyimize uygun anlatmadıkları için',
            'Bazı öğretmenlerin bana karşı olumsuz tutumları olduğu için',
            'Başarılarım takdir edilmiyor diye yeterli çabayı gösteremediğim için',
            'Evde derslerime yardım edebilecek kimsem olmadığı için',
            'Okulda aşırı baskı ve disiplin olduğu için',
            'Sınıf geçmek kolay olduğu için',
          ],
        ),
      ],
    ),
  ];
}
