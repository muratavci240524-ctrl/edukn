import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../models/school/official_document_model.dart';

/// MEB Ortaöğretim Kurumları Yönetmeliği (RG: 07/09/2013 - 28758 ve Güncel Değişiklikler)
/// Lise (Anadolu, Fen, Sosyal Bilimler, Mesleki ve Teknik, İHL) Özel Resmi Evrak Şablonları
class OfficialDocumentCatalogOrtaogretim {
  static String _today() => DateFormat('dd.MM.yyyy').format(DateTime.now());

  static String _str(Map<String, dynamic> a, String k, [String fallback = '']) {
    final v = a[k];
    if (v == null) return fallback;
    final s = v.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  static List<String> _list(Map<String, dynamic> a, String k) {
    final v = a[k];
    if (v is List) {
      return v
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static String _numberedLines(List<String> items) {
    if (items.isEmpty) return '';
    final buf = StringBuffer();
    for (int i = 0; i < items.length; i++) {
      buf.writeln('${i + 1}. ${items[i]}');
    }
    return buf.toString().trimRight();
  }

  static String _authorityTitle(SchoolDocContext ctx, [String prefix = '']) {
    final base = ctx.principalTitle.trim().isNotEmpty
        ? ctx.principalTitle.trim()
        : 'Okul Müdürü';
    if (prefix.isEmpty ||
        base.toUpperCase().contains(prefix.toUpperCase())) {
      return base;
    }
    return '$prefix / $base';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 11. KATEGORİ TANIMI (ORTAÖĞRETİM / LİSE YÖNETMELİĞİ ÖZEL)
  // ═══════════════════════════════════════════════════════════════════════════
  static const OfficialDocCategory category = OfficialDocCategory(
    id: 'ortaogretim_lise_ozel',
    order: 12,
    title: '11. Ortaöğretim (Lise) Yönetmeliği Evrakları',
    subtitle:
        'Sorumluluk Sınavı Komisyonu, Mazeret Sınavı, Onur Kurulu, Lise Disiplin & Ceza Silme, Nakil Denklik ve Diploma Teslim',
    audience: DocAudience.admin,
    icon: Icons.account_balance_rounded,
    color: Color(0xFF1D4ED8),
    scopes: [DocRegulationScope.ortaogretimLise],
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // BAŞLIK 11 ŞABLONLARI: ORTAÖĞRETİM KURUMLARI YÖNETMELİĞİ
  // ═══════════════════════════════════════════════════════════════════════════
  static final List<OfficialDocTemplate> templates = [
    // 11.1 Sorumluluk Sınavları Komisyon, Uygulama ve Puan Çizelgesi
    OfficialDocTemplate(
      id: 'lise_sorumluluk_sinavi_tutanagi',
      code: '11.1',
      categoryId: 'ortaogretim_lise_ozel',
      title: 'Lise Sorumluluk Sınavı Komisyon Uygulama Tutanağı ve Puan / İmza Çizelgesi',
      subtitle:
          'Md. 58 kapsamında sorumluluk sınav komisyonu tutanağı ve öğrenci yoklama-puan-imza tablosu',
      legalBasis: 'MEB Ortaöğretim Kurumları Yönetmeliği Md. 58',
      scopes: const [DocRegulationScope.ortaogretimLise],
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.circularSignatureTable,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.assignment_turned_in_rounded,
      customStudentTableHeaders: const [
        'S.No',
        'No / Şube',
        'Öğrenci Adı Soyadı',
        'Sorumlu Ders / Kademe',
        'Rakamla Puan',
        'Yazıyla Puan',
        'Öğrenci İmzası',
      ],
      customStudentRowBuilder: (i, s, a) => [
        '${i + 1}',
        '${s.studentNo} (${s.className})',
        s.fullName,
        '${a["branch"] ?? ""} (${a["examGradeLevel"] ?? ""})',
        '',
        '',
        '',
      ],
      questions: [
        const DocQuestionField(
          key: 'examPeriod',
          label: 'Sorumluluk Sınavı Dönemi (Md. 58)',
          type: DocFieldType.dropdown,
          options: [
            '1. Dönem Başı (Eylül - İlk Hafta) Sorumluluk Sınavları',
            '2. Dönem Başı (Şubat - İlk Hafta) Sorumluluk Sınavları',
            'Ders Yılı Sonu (Son İki Hafta) Sorumluluk Sınavları',
          ],
          defaultValue: '1. Dönem Başı (Eylül - İlk Hafta) Sorumluluk Sınavları',
        ),
        const DocQuestionField(
          key: 'branch',
          label: 'Sınavı Yapılan Ders / Alan',
          type: DocFieldType.branchSelect,
        ),
        const DocQuestionField(
          key: 'examGradeLevel',
          label: 'Sorumlu Olunan Sınıf Düzeyi',
          type: DocFieldType.dropdown,
          options: ['9. Sınıf', '10. Sınıf', '11. Sınıf', '12. Sınıf'],
          defaultValue: '9. Sınıf',
        ),
        const DocQuestionField(
          key: 'targetClasses',
          label: 'Sınava Girecek Öğrencilerin Bulunduğu Şube(ler)',
          type: DocFieldType.multiClassSelect,
          required: true,
        ),
        DocQuestionField(
          key: 'date',
          label: 'Sınav Tarihi ve Başlama-Bitiş Saati',
          type: DocFieldType.text,
          defaultValue: '${_today()} (10:00 - 10:40)',
        ),
        const DocQuestionField(
          key: 'commission1',
          label: '1. Komisyon Üyesi Alan Öğretmeni',
          type: DocFieldType.staffSelect,
        ),
        const DocQuestionField(
          key: 'commission2',
          label: '2. Komisyon Üyesi Öğretmen',
          type: DocFieldType.staffSelect,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Sınav Dönemi', _str(a, 'examPeriod')),
        MapEntry('Ders ve Sınıf Düzeyi', '${_str(a, "branch")} — ${_str(a, "examGradeLevel")}'),
        MapEntry('Sınav Tarih / Saati', _str(a, 'date')),
        MapEntry('Sınav Komisyonu', [_str(a, 'commission1'), _str(a, 'commission2')].where((e) => e.isNotEmpty).join(' — ')),
      ],
      composeBody: (a, ctx) => '''
SORUMLULUK SINAVI UYGULAMA VE DEĞERLENDİRME KOMİSYONU TUTANAĞI

MEB Ortaöğretim Kurumları Yönetmeliğinin 58 inci maddesi hükümleri uyarınca ${_str(a, 'examPeriod')} kapsamında "${_str(a, 'examGradeLevel')} ${_str(a, 'branch')}" dersi sorumluluk sınavı ${_str(a, 'date')} tarihinde komisyonumuz huzurunda kurallara uygun olarak gerçekleştirilmiştir.

Sınav soru kağıtları ve cevap anahtarı komisyonumuzca hazırlanmış; 100 tam puan üzerinden yapılan değerlendirmede en az 50 (elli) puan alan öğrencilerin sorumluluğu kalkacak şekilde yoklama ve puan çizelgesi aşağıda tanzim edilmiştir:''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(a, 'commission1', '1. Komisyon Üyesi'),
          title: 'Sınav Komisyonu Üyesi (Alan Öğrt.)',
        ),
        DocSigner(
          name: _str(a, 'commission2', '2. Komisyon Üyesi'),
          title: 'Sınav Komisyonu Üyesi',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'GÖRÜLDÜ / ONAY'),
          isApproval: true,
        ),
      ],
    ),

    // 11.2 Ortak Yazılı Mazeret Sınavı Başvuru İnceleme ve Kabul Komisyonu Tutanağı
    OfficialDocTemplate(
      id: 'ortak_sinav_mazeret_kabul_tutanagi',
      code: '11.2',
      categoryId: 'ortaogretim_lise_ozel',
      title: 'Ortak Yazılı Mazeret Sınavı Başvuru İnceleme ve Kabul Komisyonu Tutanağı',
      subtitle:
          '5 iş günü içinde sunulan sağlık raporu / geçerli mazeret belgelerinin kabulü ve mazeret sınav takvimi kararı',
      legalBasis:
          'MEB Ortaöğretim Yönetmeliği Md. 45 / İlköğretim Yönetmeliği Md. 23 & Ölçme-Değerlendirme Yönetmeliği',
      scopes: const [
        DocRegulationScope.ortaogretimLise,
        DocRegulationScope.ilkogretimOkulOncesi,
      ],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.event_repeat_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Komisyon Karar Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'examPeriod',
          label: 'İlgili Ortak Sınav Dönemi',
          type: DocFieldType.dropdown,
          options: [
            '1. Dönem 1. Ortak Yazılı Sınavları Mazeret Değerlendirmesi',
            '1. Dönem 2. Ortak Yazılı Sınavları Mazeret Değerlendirmesi',
            '2. Dönem 1. Ortak Yazılı Sınavları Mazeret Değerlendirmesi',
            '2. Dönem 2. Ortak Yazılı Sınavları Mazeret Değerlendirmesi',
          ],
          defaultValue: '1. Dönem 1. Ortak Yazılı Sınavları Mazeret Değerlendirmesi',
        ),
        const DocQuestionField(
          key: 'targetClass',
          label: 'Şube Seçimi (Tekil veya Örnek)',
          type: DocFieldType.classSelect,
        ),
        const DocQuestionField(
          key: 'acceptedStudents',
          label: 'Mazereti Kabul Edilen Öğrenciler ve Dersleri',
          type: DocFieldType.multiline,
          defaultValue:
              'Yasal 5 iş günü içinde resmi sağlık raporu / veli mazeret dilekçesi sunan öğrencilerin başvuruları incelenerek uygun görülmüştür.',
        ),
        const DocQuestionField(
          key: 'makeupSchedule',
          label: 'Belirlenen Mazeret Sınavı Tarihi ve Uygulama Yeri',
          type: DocFieldType.text,
          defaultValue: 'İlan edilen ortak mazeret sınav haftasında ilgili zümrelerce uygulanacaktır.',
        ),
        const DocQuestionField(
          key: 'members',
          label: 'İnceleme Komisyonu Üyeleri',
          type: DocFieldType.multiStaffSelect,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Sınav Dönemi', _str(a, 'examPeriod')),
        MapEntry('Karar Tarihi', _str(a, 'date', _today())),
        MapEntry('Mazeret Sınav Takvimi', _str(a, 'makeupSchedule')),
      ],
      composeBody: (a, ctx) => '''
ORTAK YAZILI VE UYGULAMALI SINAVLAR MAZERET DEĞERLENDİRME TUTANAĞI

MEB Ölçme ve Değerlendirme Yönetmeliği ile ilgili kurum yönetmeliği hükümleri uyarınca; "${_str(a, 'examPeriod')}" oturumlarına katılamayan ve 5 (beş) iş günü yasal süresi içerisinde velisi tarafından resmi mazeret belgesi (sağlık raporu, resmi izin, doğal afet/ailevi mücbir sebep) ibraz edilen öğrencilerin dilekçeleri incelenmiştir.

KABUL VE UYGULAMA KARARI:
1. ${_str(a, 'acceptedStudents')}
2. Mazereti uygun görülen öğrencilerin mazeret sınavlarına alınmasına (${_str(a, 'makeupSchedule')}), sınav tarih ve saatlerinin en az bir hafta önceden okul panosunda ve veli iletişim kanallarında duyurulmasına,
3. Geçerli mazeret belgesi sunmayan veya süresi dışında başvuran öğrencilerin e-Okul sistemine "G" (Girmedi) olarak işlenmesine oy birliği ile karar verilmiştir.''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(3))
          DocSigner(name: m, title: 'Komisyon Üyesi'),
        DocSigner(
          name: ctx.vicePrincipals.isNotEmpty
              ? ctx.vicePrincipals.first.fullName
              : 'Müdür Yardımcısı',
          title: 'Ölçme-Değerlendirme Md. Yrd.',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'UYGUNDUR'),
          isApproval: true,
        ),
      ],
    ),

    // 11.3 Okul Öğrenci Onur Kurulu Seçimi ve Onur Belgesi Ödüllendirme Tutanağı
    OfficialDocTemplate(
      id: 'lise_onur_kurulu_onur_belgesi_tutanagi',
      code: '11.3',
      categoryId: 'ortaogretim_lise_ozel',
      title: 'Lise Öğrenci Onur Kurulu Toplantısı ve Onur Belgesi Ödüllendirme Tutanağı',
      subtitle:
          'Md. 182-184 uyarınca Onur Kurulu çalışmaları ve puan şartı aranmaksızın Onur Belgesi verilecek öğrencilerin tespiti',
      legalBasis: 'MEB Ortaöğretim Kurumları Yönetmeliği Md. 182–184 & Md. 160',
      scopes: const [DocRegulationScope.ortaogretimLise],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.workspace_premium_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Toplantı Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'advisorTeacher',
          label: 'Onur Kurulu Danışman / Başkan Öğretmeni',
          type: DocFieldType.staffSelect,
        ),
        const DocQuestionField(
          key: 'studentHead',
          label: 'Onur Kurulu Öğrenci Başkanı (12. Sınıf Temsilcisi)',
          type: DocFieldType.text,
          hint: 'Örn: Zeynep KAYA (12-A)',
        ),
        const DocQuestionField(
          key: 'honoredStudents',
          label: 'Onur Belgesi İle Ödüllendirilmesi Teklif Edilen Öğrenciler (Ad Soyad - Şube - Gerekçe)',
          type: DocFieldType.multiline,
          defaultValue:
              'Türkçeyi doğru ve güzel kullanma, bilimsel/sanatsal/sportif başarı, görgü kurallarına örnek uyum ve toplumsal duyarlılık gösteren öğrenciler tespit edilmiştir.',
        ),
        const DocQuestionField(
          key: 'decisions',
          label: 'Onur Kurulu Gündem ve Kararları',
          type: DocFieldType.multiCheck,
          options: [
            'Okulda olumlu akran kültürünün güçlendirilmesi, nezaket ve görgü kurallarına uyum konusunda sınıf temsilcileri aracılığıyla farkındalık çalışması yürütülmesine karar verildi.',
            'Yönetmeliğin 160 ıncı maddesi uyarınca not ortalaması şartına bağlı olmaksızın örnek davranış ve üstün gayret gösteren öğrencilerin "Onur Belgesi" ile ödüllendirilmek üzere Öğrenci Ödül ve Disiplin Kuruluna / Okul Müdürlüğüne sunulmasına karar verildi.',
            'Devamsızlık, derse geç kalma ve okul eşyasına zarar verme gibi olumsuz eğilimlerin akran rehberliği ile önlenmesi için şube temsilcilerinin görüşlerinin alınmasına karar verildi.',
            'Milli bayramlar, sosyal sorumluluk kampanyaları ve çevre koruma faaliyetlerine öğrenci katılımının teşvik edilmesine karar verildi.',
            'Sınavlarda akademik dürüstlük, kopyasız sınav kültürü ve emeğe saygı bilincinin güçlendirilmesi için sınıf panolarında bilgilendirme yapılmasına karar verildi.',
            'Okula yeni başlayan 9. sınıf öğrencilerine üst sınıf temsilcileri tarafından akran oryantasyon desteği sunulmasına karar verildi.',
            'Dijital mecralarda okulun ve arkadaşlarının saygınlığını koruyan sorumlu sosyal medya kullanımı ilkelerinin yaygınlaştırılmasına karar verildi.',
          ],
          defaultValue: [
            'Okulda olumlu akran kültürünün güçlendirilmesi, nezaket ve görgü kurallarına uyum konusunda sınıf temsilcileri aracılığıyla farkındalık çalışması yürütülmesine karar verildi.',
            'Yönetmeliğin 160 ıncı maddesi uyarınca not ortalaması şartına bağlı olmaksızın örnek davranış ve üstün gayret gösteren öğrencilerin "Onur Belgesi" ile ödüllendirilmek üzere Öğrenci Ödül ve Disiplin Kuruluna / Okul Müdürlüğüne sunulmasına karar verildi.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Kurul Adı', 'Okul Öğrenci Onur Kurulu (Md. 182)'),
        MapEntry('Tarih / Dönem', '${_str(a, "date", _today())} — ${ctx.activeTermLabel}'),
        MapEntry('Danışman Öğretmen', _str(a, 'advisorTeacher', 'Onur Kurulu Danışmanı')),
        MapEntry('Öğrenci Temsilcisi', _str(a, 'studentHead', '-')),
      ],
      composeBody: (a, ctx) => '''
OKUL ÖĞRENCİ ONUR KURULU TOPLANTI VE ÖDÜLLENDİRME TUTANAĞI

MEB Ortaöğretim Kurumları Yönetmeliğinin 182-184 üncü maddeleri uyarınca oluşturulan ${ctx.schoolName} Öğrenci Onur Kurulu, ${_str(a, 'date', _today())} tarihinde toplanarak aşağıdaki değerlendirme ve teklif kararlarını almıştır:

ONUR BELGESİ TEKLİF LİSTESİ VE GEREKÇESİ:
${_str(a, 'honoredStudents')}

ALINAN KARARLAR:
${_numberedLines(_list(a, 'decisions'))}''',
      buildSigners: (a, ctx) => [
        if (_str(a, 'studentHead').isNotEmpty)
          DocSigner(
            name: _str(a, 'studentHead'),
            title: 'Onur Kurulu Öğrenci Başkanı',
          ),
        DocSigner(
          name: _str(a, 'advisorTeacher', 'Danışman Öğretmen'),
          title: 'Onur Kurulu Başkanı Öğretmen',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'UYGUNDUR'),
          isApproval: true,
        ),
      ],
    ),

    // 11.4 Ortaöğretim Öğrenci Ödül ve Disiplin Kurulu Karar Tutanağı
    OfficialDocTemplate(
      id: 'lise_disiplin_kurulu_karar_tutanagi',
      code: '11.4',
      categoryId: 'ortaogretim_lise_ozel',
      title: 'Ortaöğretim Okul Öğrenci Ödül ve Disiplin Kurulu Karar Tutanağı (Md. 164-176)',
      subtitle:
          'Kınama, Kısa Süreli Uzaklaştırma, Okul Değiştirme veya Örgün Eğitim Dışına Çıkarma disiplin kurul kararı',
      legalBasis: 'MEB Ortaöğretim Kurumları Yönetmeliği Md. 163–176',
      scopes: const [DocRegulationScope.ortaogretimLise],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.gavel_rounded,
      questions: [
        const DocQuestionField(
          key: 'decisionNo',
          label: 'Disiplin Kurulu Karar No',
          type: DocFieldType.text,
          defaultValue: 'Karar No: 2026/03',
        ),
        DocQuestionField(
          key: 'date',
          label: 'Karar Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'targetClass',
          label: 'Öğrencinin Şubesi',
          type: DocFieldType.classSelect,
        ),
        const DocQuestionField(
          key: 'student',
          label: 'İncelenen Öğrenci',
          type: DocFieldType.studentSelect,
        ),
        const DocQuestionField(
          key: 'summary',
          label: 'Disiplin Konusu Fiil, Yazılı Savunma ve Rehberlik Raporu Özeti',
          type: DocFieldType.multiline,
          defaultValue:
              'Olay tutanağı, tanık ifadeleri, öğrencinin yazılı savunması ve Rehberlik ve Psikolojik Danışma Servisinin ön inceleme raporu Yönetmeliğin 168 ve 171 inci maddelerine uygun biçimde kurulca değerlendirilmiştir.',
        ),
        const DocQuestionField(
          key: 'penalty',
          label: 'Kurulca Verilen Ceza ve Davranış Puanı Uygulaması (Md. 164 & 170)',
          type: DocFieldType.dropdown,
          options: [
            'Ceza Verilmesine Yer Olmadığına — Yazılı Sözlü Uyarı ve Rehberlik İzlemesine',
            'Md. 164/1 Uyarınca "KINAMA" Cezası Verilmesine (-10 Davranış Puanı)',
            'Md. 164/2 Uyarınca "OKULDAN 1-5 GÜN KISA SÜRELİ UZAKLAŞTIRMA" Cezası Verilmesine (-20 Davranış Puanı)',
            'Md. 164/3 Uyarınca "OKUL DEĞİŞTİRME" Teklifinin İlçe Öğrenci Disiplin Kuruluna Gönderilmesine (-40 Davranış Puanı)',
            'Md. 164/4 Uyarınca "ÖRGÜN EĞİTİM DIŞINA ÇIKARMA" Teklifinin İl Öğrenci Disiplin Kuruluna Sunulmasına (-80 Davranış Puanı)',
          ],
          defaultValue:
              'Md. 164/1 Uyarınca "KINAMA" Cezası Verilmesine (-10 Davranış Puanı)',
        ),
        const DocQuestionField(
          key: 'members',
          label: 'Disiplin Kurulu Üyesi Öğretmenler',
          type: DocFieldType.multiStaffSelect,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Karar Sayısı / Tarihi', '${_str(a, "decisionNo")} — ${_str(a, "date", _today())}'),
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Verilen Karar', _str(a, 'penalty')),
      ],
      composeBody: (a, ctx) => '''
OKUL ÖĞRENCİ ÖDÜL VE DİSİPLİN KURULU KARAR TUTANAĞI

OLAYIN ÖZETİ, REHBERLİK GÖRÜŞÜ VE SAVUNMANIN DEĞERLENDİRİLMESİ:
${_str(a, 'summary')}

Yönetmeliğin 168 inci maddesi gereğince öğrencinin daha önce disiplin cezası alıp almadığı, derslerdeki tutumu, fiilin işlenişinde tahrik unsuru ve samimi pişmanlık durumu ayrı ayrı tartışılmıştır.

KARAR VE YASAL İTİRAZ YOLU:
Kurulumuzca yapılan oylama neticesinde ilgili öğrenci hakkında:
"${_str(a, 'penalty')}"
yönünde karar verilmiştir. Okul müdürü onayını müteakip kararın öğrenci velisine yazılı tebliğine; tebliğ tarihinden itibaren 5 (beş) iş günü içinde İlçe/İl Öğrenci Disiplin Kuruluna itiraz hakkının bulunduğunun belirtilmesine karar verilmiştir.''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(4))
          DocSigner(name: m, title: 'Disiplin Kurulu Üyesi'),
        DocSigner(
          name: ctx.vicePrincipals.isNotEmpty
              ? ctx.vicePrincipals.first.fullName
              : 'Kurul Başkanı',
          title: 'Disiplin Kurulu Başkanı (Md. Yrd.)',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'ONAY'),
          isApproval: true,
        ),
      ],
    ),

    // 11.5 Ders Yılı Sonu Disiplin Cezası Silinmesi ve Davranış Puanı İadesi Kararı
    OfficialDocTemplate(
      id: 'lise_disiplin_cezasi_silme_karari',
      code: '11.5',
      categoryId: 'ortaogretim_lise_ozel',
      title: 'Ders Yılı Sonu Disiplin Cezası Silinmesi ve Davranış Puanı İadesi Tutanağı (Md. 178)',
      subtitle:
          'Olumlu davranışlarıyla kendini düzelten öğrencilerin disiplin cezalarının yıl sonu kurul kararıyla silinmesi',
      legalBasis: 'MEB Ortaöğretim Kurumları Yönetmeliği Md. 178',
      scopes: const [DocRegulationScope.ortaogretimLise],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.cleaning_services_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Yıl Sonu Kurul Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'studentsList',
          label: 'Cezası Silinerek Davranış Puanı İade Edilen Öğrenciler (Ad Soyad - Şube - Ceza Türü)',
          type: DocFieldType.multiline,
          defaultValue:
              'Sınıf rehber öğretmenleri ve Rehberlik Servisinin olumlu görüşü doğrultusunda dönem içinde davranışlarını düzelttiği tespit edilen öğrenciler aşağıda değerlendirilmiştir.',
        ),
        const DocQuestionField(
          key: 'includeStaffSignatureTable',
          label: 'Tutanak Sonuna Öğretmenler Kurulu İmza Sirküsü Eklensin mi?',
          type: DocFieldType.yesNo,
          defaultValue: false,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Dayanak Mevzuat', 'MEB Ortaöğretim Kurumları Yönetmeliği Md. 178'),
        MapEntry('Karar Tarihi', '${_str(a, "date", _today())} — Ders Yılı Sonu'),
      ],
      composeBody: (a, ctx) => '''
DİSİPLİN CEZALARININ SİLİNMESİ VE DAVRANIŞ PUANI İADESİ KURUL KARAR TUTANAĞI

MEB Ortaöğretim Kurumları Yönetmeliğinin 178 inci maddesi hükümleri doğrultusunda; eğitim ve öğretim yılı içerisinde disiplin cezası almış olmakla birlikte sonraki süreçte okul kurallarına uyumu, ders başarısı ve olumlu davranış değişiklikleri sınıf rehber öğretmenleri ile Okul Rehberlik Servisince gözlemlenen öğrencilerin durumları ders yılı sonu kurulunda görüşülmüştür.

DEĞERLENDİRME VE KARAR:
${_str(a, 'studentsList')}

Yukarıda durumları görüşülen öğrencilerin aldıkları disiplin cezalarının e-Okul / sicil kayıtlarından silinmesine ve düşürülen davranış puanlarının kendilerine iade edilmesine oy birliği/çokluğu ile karar verilmiştir.''',
      buildSigners: (a, ctx) => [
        if (ctx.vicePrincipals.isNotEmpty)
          DocSigner(
            name: ctx.vicePrincipals.first.fullName,
            title: 'Disiplin Kurulu Başkanı',
          ),
        if (ctx.counselors.isNotEmpty)
          DocSigner(
            name: ctx.counselors.first.fullName,
            title: 'Rehber Öğretmen / PDR',
          ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'Kurul Başkanı / ONAY'),
          isApproval: true,
        ),
      ],
    ),

    // 11.6 Lise Nakil ve Geçiş Komisyonu Kontenjan ve Sorumlu Ders Tespit Tutanağı
    OfficialDocTemplate(
      id: 'lise_nakil_gecis_komisyonu_tutanagi',
      code: '11.6',
      categoryId: 'ortaogretim_lise_ozel',
      title: 'Lise Nakil, Geçiş, Denklik ve Sorumlu Ders Tespit Komisyonu Tutanağı (Md. 37-41)',
      subtitle:
          'Farklı lise türlerinden nakil gelen öğrencilerin muaf/sorumlu derslerinin ve kontenjan kabulünün tespiti',
      legalBasis: 'MEB Ortaöğretim Kurumları Yönetmeliği Md. 37–41',
      scopes: const [DocRegulationScope.ortaogretimLise],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.compare_arrows_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Komisyon Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'studentInfo',
          label: 'Nakil Gelen Öğrenci Adı Soyadı, Geldiği Okul Türü ve Yerleştiği Sınıf',
          type: DocFieldType.text,
          hint: 'Örn: Kerem DEMİR — Mesleki ve Teknik AL -> 10-B Sınıfı',
        ),
        const DocQuestionField(
          key: 'responsibleCourses',
          label: 'Okul Türü Farkı Nedeniyle Sorumlu Tutulacağı / Muaf Olacağı Dersler',
          type: DocFieldType.multiline,
          defaultValue:
              'Haftalık ders çizelgesi karşılaştırması sonucunda öğrencinin önceki okulunda görmediği veya kredi/saat farkı bulunan ortak/alan derslerinden sorumlu tutulması, gördüğü eşdeğer derslerin ise intibakının yapılması kararlaştırılmıştır.',
        ),
        const DocQuestionField(
          key: 'members',
          label: 'Nakil ve Geçiş Komisyonu Üyeleri',
          type: DocFieldType.multiStaffSelect,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Komisyon', 'Okul Nakil, Geçiş ve İntibak Komisyonu'),
        MapEntry('Öğrenci / Geçiş Bilgisi', _str(a, 'studentInfo')),
        MapEntry('Tarih', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
NAKİL, GEÇİŞ VE DERS İNTİBAK KOMİSYONU TUTANAĞI

MEB Ortaöğretim Kurumları Yönetmeliğinin 37 ila 41 inci maddeleri hükümleri uyarınca e-Okul nakil sistemi üzerinden okulumuza nakli gerçekleşen (${_str(a, 'studentInfo')}) öğrencinin haftalık ders çizelgesi ve transkript intibak incelemesi komisyonumuzca yapılmıştır.

İNTİBAK VE SORUMLULUK KARARI:
${_str(a, 'responsibleCourses')}

Belirlenen sorumlu derslerin e-Okul sistemine işlenmesine ve öğrenci ile velisine yazılı olarak tebliğ edilmesine oy birliği ile karar verilmiştir.''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(3))
          DocSigner(name: m, title: 'Komisyon Üyesi'),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'Komisyon Başkanı / ONAY'),
          isApproval: true,
        ),
      ],
    ),

    // 11.7 Lise Sosyal Sorumluluk Programı ve Hayat Boyu Öğrenme Mezuniyet Portfolyo Raporu
    OfficialDocTemplate(
      id: 'lise_sosyal_sorumluluk_mezuniyet_raporu',
      code: '11.7',
      categoryId: 'ortaogretim_lise_ozel',
      title: 'Lise Sosyal Sorumluluk Programı ve Toplum Hizmeti Tamamlama Onay Raporu',
      subtitle:
          'Ortaöğretim süresince yürütülen zorunlu sosyal sorumluluk / toplum hizmeti saatlerinin dönemlik onay formu',
      legalBasis:
          'MEB Ortaöğretim Kurumları Yönetmeliği & Sosyal Etkinlikler Yönetmeliği',
      scopes: const [DocRegulationScope.ortaogretimLise],
      audience: DocAudience.teacher,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.handshake_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Onay Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'targetClass',
          label: 'Şube Seçimi',
          type: DocFieldType.classSelect,
        ),
        const DocQuestionField(
          key: 'projectName',
          label: 'Sosyal Sorumluluk Projesi / Kurumsal İş Birliği Adı',
          type: DocFieldType.text,
          defaultValue: 'Ağaçlandırma, Yaşlı-Engelli Dayanışması ve Okuma Kültürü Gönüllülük Projesi',
        ),
        const DocQuestionField(
          key: 'completedHours',
          label: 'Tamamlanan Faaliyet Süresi (Saat) ve Katılımcı Sayısı',
          type: DocFieldType.text,
          defaultValue: '15 Saat Sosyal Sorumluluk Çalışması — Tüm Şube Öğrencileri',
        ),
        const DocQuestionField(
          key: 'advisor',
          label: 'Danışman / Sınıf Rehber Öğretmeni',
          type: DocFieldType.staffSelect,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Şube / Dönem', '${_str(a, "targetClass")} — ${ctx.academicYear}'),
        MapEntry('Proje Adı', _str(a, 'projectName')),
        MapEntry('Tamamlanan Süre', _str(a, 'completedHours')),
        MapEntry('Tarih', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
ORTAÖĞRETİM SOSYAL SORUMLULUK VE TOPLUM HİZMETİ TAMAMLAMA TUTANAĞI

MEB Ortaöğretim Kurumları Yönetmeliği ve Sosyal Etkinlikler Yönetmeliği kapsamında; okulumuz ${_str(a, 'targetClass')} şubesi öğrencilerinin toplumsal duyarlılık, yardımlaşma, çevre bilinci ve aktif vatandaşlık becerilerini geliştirmek amacıyla yürüttükleri "${_str(a, 'projectName')}" çalışması (${_str(a, 'completedHours')}) başarıyla tamamlanmıştır.

Gerçekleştirilen çalışma kanıtları kontrol edilerek öğrencilerin e-Okul Sosyal Etkinlik Modülü / öğrenci portfolyolarına işlenmiştir.''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(a, 'advisor', ctx.currentUser?.fullName ?? 'Danışman Öğretmen'),
          title: 'Danışman / Rehber Öğretmen',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'ONAY'),
          isApproval: true,
        ),
      ],
    ),

    // 11.8 Lise Mezuniyet Komisyonu ve İmza Karşılığı Diploma Teslim Çizelgesi
    OfficialDocTemplate(
      id: 'lise_mezuniyet_diploma_teslim_tutanagi',
      code: '11.8',
      categoryId: 'ortaogretim_lise_ozel',
      title: 'Lise Mezuniyet Komisyonu Kontrol Tutanağı ve Diploma Teslim İmza Çizelgesi',
      subtitle:
          'Md. 69-73 kapsamında 12. sınıf mezuniyet kontrolü ve öğrencilere imza karşılığı diploma teslim defteri',
      legalBasis: 'MEB Ortaöğretim Kurumları Yönetmeliği Md. 69–73',
      scopes: const [DocRegulationScope.ortaogretimLise],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.circularSignatureTable,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.school_outlined,
      customStudentTableHeaders: const [
        'S.No',
        'No / Şube',
        'Mezun Öğrenci Adı Soyadı',
        'T.C. Kimlik No',
        'Diploma No / Tarih',
        'Teslim Alan İmzası',
      ],
      customStudentRowBuilder: (i, s, a) => [
        '${i + 1}',
        '${s.studentNo} (${s.className})',
        s.fullName,
        s.tcNo,
        '',
        '',
      ],
      questions: [
        const DocQuestionField(
          key: 'targetClasses',
          label: 'Mezun Olan 12. Sınıf Şube(ler)i',
          type: DocFieldType.multiClassSelect,
          required: true,
        ),
        DocQuestionField(
          key: 'date',
          label: 'Mezuniyet / Diploma Kontrol Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'vp',
          label: 'Mezuniyet İşlemlerinden Sorumlu Müdür Yardımcısı',
          type: DocFieldType.staffSelect,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Mezuniyet Dönemi', ctx.academicYear),
        MapEntry('Şubeler', _list(a, 'targetClasses').join(', ')),
        MapEntry('Düzenleme Tarihi', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
MEZUNİYET KONTROL TUTANAĞI VE DİPLOMA TESLİM ÇİZELGESİ

MEB Ortaöğretim Kurumları Yönetmeliğinin 69 ila 73 üncü maddeleri uyarınca tüm sınıflara ait sorumlu dersi bulunmayan, devamsızlık ve mezuniyet şartlarını eksiksiz sağlayan aşağıda kimlik bilgileri yazılı öğrencilerimizin ortaöğretim diplomaları e-Okul kayıtlarıyla karşılaştırılarak kontrol edilmiş, soğuk damga işlemleri tamamlanmış ve kimlik kontrolü yapılarak bizzat kendisine / yasal velisine imza karşılığı teslim edilmiştir:''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(
            a,
            'vp',
            ctx.vicePrincipals.isNotEmpty
                ? ctx.vicePrincipals.first.fullName
                : 'Müdür Yardımcısı',
          ),
          title: 'Kontrol Eden Müdür Yardımcısı',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'ONAY'),
          isApproval: true,
        ),
      ],
    ),
  ];
}
