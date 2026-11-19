import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../models/school/official_document_model.dart';

/// MEB Okul Öncesi Eğitim ve İlköğretim Kurumları Yönetmeliği (RG: 26/07/2014 - 29072)
/// ve Ortak MEB Mevzuatı Ek Resmi Evrak Şablonları
class OfficialDocumentCatalogIlkogretim {
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
  // 10. KATEGORİ TANIMI (OKUL ÖNCESİ VE İLKÖĞRETİM YÖNETMELİĞİ ÖZEL)
  // ═══════════════════════════════════════════════════════════════════════════
  static const OfficialDocCategory category = OfficialDocCategory(
    id: 'ilkogretim_okul_oncesi_ozel',
    order: 11,
    title: '10. Okul Öncesi ve İlköğretim Yönetmeliği Evrakları',
    subtitle:
        'İYEP Komisyonu, ŞÖK Sınıf Geçme/Tekrar, Uyum Haftası, Destek Eğitim Odası, ÖDDK Kararı, Kura & Portfolyo',
    audience: DocAudience.admin,
    icon: Icons.child_care_rounded,
    color: Color(0xFF0D9488),
    scopes: [DocRegulationScope.ilkogretimOkulOncesi],
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // MEVCUT ORTAK KATEGORİLERE (1, 3, 4, 6, 9) EKLENEN KRİTİK MEB ŞABLONLARI
  // ═══════════════════════════════════════════════════════════════════════════
  static final List<OfficialDocTemplate> crossCategoryTemplates = [
    // 1.11 Değerler Eğitimi / ÇEDES ve Okul İklimi Komisyonu
    OfficialDocTemplate(
      id: 'degerler_egitimi_komisyonu_tutanagi',
      code: '1.11',
      categoryId: 'idari_kurul_komisyon',
      title: 'Değerler Eğitimi, Okul İklimi ve ÇEDES Yürütme Komisyonu Tutanağı',
      subtitle:
          'Türkiye Yüzyılı Maarif Modeli Erdem-Değer-Eylem çerçevesi, aylık değer temaları ve etkinlik planlaması',
      legalBasis:
          'MEB İlköğretim / Ortaöğretim Kurumları Yönetmeliği & Sosyal Etkinlikler Yönetmeliği',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.volunteer_activism_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Toplantı Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'chair',
          label: 'Komisyon Başkanı',
          type: DocFieldType.staffSelect,
        ),
        const DocQuestionField(
          key: 'members',
          label: 'Komisyon Üyesi Öğretmenler',
          type: DocFieldType.multiStaffSelect,
        ),
        const DocQuestionField(
          key: 'themes',
          label: 'Planlanan Değer Temaları ve Uygulama Kararları',
          type: DocFieldType.multiCheck,
          options: [
            'Türkiye Yüzyılı Maarif Modeli "Erdem-Değer-Eylem" çerçevesinde saygı, sorumluluk, adalet, merhamet, vatanseverlik ve dürüstlük temalarının aylık takvime bağlanmasına karar verildi.',
            'Her ay belirlenen değer temasına ilişkin sınıf panolarının, rehberlik etkinliklerinin ve zümre içi ders ilişkilendirmelerinin yapılmasına karar verildi.',
            'Çevreme Duyarlıyım Değerlerime Sahip Çıkıyorum (ÇEDES), Sıfır Atık ve gönüllülük/yardımlaşma projelerinin öğrenci kulüpleriyle eşgüdümlü yürütülmesine karar verildi.',
            'Dijital nezaket, siber zorbalıktan korunma ve Türkçenin doğru/güzel kullanımı konularında farkındalık seminerleri düzenlenmesine karar verildi.',
            'Aile katılımını güçlendirmek amacıyla velilere yönelik aylık değer bülteni paylaşılmasına ve dönem sonunda komisyon faaliyet raporunun hazırlanmasına karar verildi.',
            'Akran nezaketi, empati, büyüklerine saygı ve okul eşyasını koruma temalarının sınıf rehberlik saatlerinde örnek olaylarla işlenmesine karar verildi.',
            'Kütüphane, yaşlı/engelli dayanışması, fidan dikimi ve hayvanları koruma gibi uygulamalı iyilik çalışmalarının teşvik edilmesine karar verildi.',
            'Olumlu davranışlarıyla akranlarına örnek olan öğrencilerin Onur Kurulu / ÖDDK iş birliğiyle görünür kılınarak takdir edilmesine karar verildi.',
          ],
          defaultValue: [
            'Türkiye Yüzyılı Maarif Modeli "Erdem-Değer-Eylem" çerçevesinde saygı, sorumluluk, adalet, merhamet, vatanseverlik ve dürüstlük temalarının aylık takvime bağlanmasına karar verildi.',
            'Her ay belirlenen değer temasına ilişkin sınıf panolarının, rehberlik etkinliklerinin ve zümre içi ders ilişkilendirmelerinin yapılmasına karar verildi.',
            'Dijital nezaket, siber zorbalıktan korunma ve Türkçenin doğru/güzel kullanımı konularında farkındalık seminerleri düzenlenmesine karar verildi.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Komisyon Adı', 'Değerler Eğitimi ve Okul İklimi Yürütme Komisyonu'),
        MapEntry('Toplantı Tarihi / Dönem', '${_str(a, "date", _today())} — ${ctx.academicYear}'),
        MapEntry('Komisyon Başkanı', _str(a, 'chair', ctx.principalName)),
      ],
      composeBody: (a, ctx) => '''
${ctx.academicYear} eğitim ve öğretim yılında ${ctx.schoolName} bünyesinde öğrencilerin milli, manevi, ahlaki ve insani değerleri içselleştirmelerini desteklemek amacıyla Değerler Eğitimi Yürütme Komisyonu ${_str(a, 'date', _today())} tarihinde toplanarak aşağıdaki kararları almıştır:

ALINAN KOMİSYON KARARLARI:
${_numberedLines(_list(a, 'themes'))}

İşbu tutanak komisyon üyelerince imza altına alınarak yürürlüğe konulmuştur.''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(5))
          DocSigner(name: m, title: 'Komisyon Üyesi'),
        DocSigner(
          name: _str(a, 'chair', ctx.principalName),
          title: 'Komisyon Başkanı',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'UYGUNDUR'),
          isApproval: true,
        ),
      ],
    ),

    // 3.8 Görev ve Sınıf / Oda Demirbaş Devir-Teslim Tutanağı
    OfficialDocTemplate(
      id: 'gorev_demirbas_devir_teslim_tutanagi',
      code: '3.8',
      categoryId: 'idari_personel_yazi',
      title: 'İdari Görev, Atölye/Laboratuvar veya Sınıf Demirbaş Devir-Teslim Tutanağı',
      subtitle:
          'Müdür/Md. Yrd. görev değişimi, laboratuvar, kütüphane, destek eğitim odası veya derslik demirbaş devri',
      legalBasis:
          'MEB İlköğretim Md. 39-43 / Ortaöğretim Md. 78-80 & Taşınır Mal Yönetmeliği',
      scopes: const [DocRegulationScope.ortakMevzuat],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.swap_horiz_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Devir-Teslim Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'handoverType',
          label: 'Devir-Teslim Konusu',
          type: DocFieldType.dropdown,
          options: [
            'Müdür Yardımcılığı / İdari Görev ve Dosya Devir-Teslimi',
            'Sınıf / Derslik ve Etkileşimli Tahta Demirbaş Devir-Teslimi',
            'Fen / Bilişim Laboratuvarı, Atölye veya Z-Kütüphane Sorumluluğu Devri',
            'Rehberlik Servisi Gizli Dosya ve Arşiv Devir-Teslimi',
            'Taşınır Kayıt / Ambar Demirbaş Devir-Teslimi',
          ],
          defaultValue: 'Sınıf / Derslik ve Etkileşimli Tahta Demirbaş Devir-Teslimi',
        ),
        const DocQuestionField(
          key: 'giver',
          label: 'Devreden (Teslim Eden) Görevli',
          type: DocFieldType.staffSelect,
        ),
        const DocQuestionField(
          key: 'receiver',
          label: 'Devralan (Teslim Alan) Görevli',
          type: DocFieldType.staffSelect,
        ),
        const DocQuestionField(
          key: 'items',
          label: 'Devredilen Evrak, Anahtar, Cihaz ve Demirbaş Kalemleri',
          type: DocFieldType.multiCheck,
          options: [
            'Oda/derslik anahtarları, dolap kilitleri ve demirbaş eşya dayanıklı taşınır listesi (TİF)',
            'Etkileşimli tahta / projeksiyon, kumanda, güç kablosu ve internet bağlantı donanımı (çalışır durumda)',
            'Öğrenci sıra, masa, öğretmen masası, yazı tahtası ve sınıf panoları (sağlam ve eksiksiz)',
            'Birim/zümre resmi klasörleri, gelen-giden evrak dosyaları, mühür/kaşe ve zimmet kayıtları',
            'İlk yardım dolabı, yangın tüpü / acil çıkış yönlendirme levhaları kontrolü',
            'Laboratuvar / atölye deney setleri, kimyasal/sarf malzeme dolabı ve güvenlik talimatnameleri',
            'Kütüphane kitap/materyal envanter listesi, okuyucu kayıt defteri ve ödünç takip çizelgeleri',
            'Dijital şifre/yetki tanımlamaları, e-Okul/MEBBİS/kurum otomasyon görev devir mutabakatı',
          ],
          defaultValue: [
            'Oda/derslik anahtarları, dolap kilitleri ve demirbaş eşya dayanıklı taşınır listesi (TİF)',
            'Etkileşimli tahta / projeksiyon, kumanda, güç kablosu ve internet bağlantı donanımı (çalışır durumda)',
            'Öğrenci sıra, masa, öğretmen masası, yazı tahtası ve sınıf panoları (sağlam ve eksiksiz)',
          ],
        ),
        const DocQuestionField(
          key: 'note',
          label: 'Varsa Hasar / Eksik Notu veya Özel Şerh',
          type: DocFieldType.text,
          defaultValue: 'Tüm demirbaş ve dosyalar tam, sağlam ve çalışır vaziyette teslim edilmiştir.',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Devir-Teslim Türü', _str(a, 'handoverType')),
        MapEntry('Devir Tarihi', _str(a, 'date', _today())),
        MapEntry('Teslim Eden', _str(a, 'giver', '................................')),
        MapEntry('Teslim Alan', _str(a, 'receiver', '................................')),
      ],
      composeBody: (a, ctx) => '''
GÖREV VE DEMİRBAŞ DEVİR-TESLİM TUTANAĞI

${ctx.schoolName} bünyesinde "${_str(a, 'handoverType')}" kapsamında aşağıda dökümü yer alan evrak, dosya, donanım ve taşınır demirbaşlar ${_str(a, 'date', _today())} tarihinde yerinde sayılarak ve çalışır durumu kontrol edilerek taraflar arasında devir ve teslim edilmiştir.

TESLİM EDİLEN KALEMLER:
${_numberedLines(_list(a, 'items'))}

TESPİT VE AÇIKLAMA:
${_str(a, 'note')}

İşbu devir-teslim tutanağı üç nüsha halinde düzenlenmiş olup birer nüshası taraflara verilmiş, bir nüshası kurum dosyasına kaldırılmıştır.''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(a, 'giver', 'Teslim Eden'),
          title: 'Devreden (Teslim Eden)',
        ),
        DocSigner(
          name: _str(a, 'receiver', 'Teslim Alan'),
          title: 'Devralan (Teslim Alan)',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'ONAY'),
          isApproval: true,
        ),
      ],
    ),

    // 4.7 Veli Disiplin / Davranış Değerlendirme Kurulu Görüşmeye Davet & Savunma Tebligatı
    OfficialDocTemplate(
      id: 'disiplin_savunma_veli_davet_yazisi',
      code: '4.7',
      categoryId: 'idari_disiplin_kaza',
      title: 'Disiplin / ÖDDK Yazılı Savunma İstemi ve Veli Görüşmeye Davet Tebligatı',
      subtitle:
          'ÖDDK veya Öğrenci Disiplin Kurulu süreci öncesi öğrenci savunma hakkı ve veli resmi davet yazısı',
      legalBasis:
          'MEB İlköğretim Yönetmeliği Md. 57 / Ortaöğretim Yönetmeliği Md. 171',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.officialLetter,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.mark_email_unread_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Tebligat Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'docNo',
          label: 'Sayı / Dosya No',
          type: DocFieldType.text,
          defaultValue: 'ÖDDK-DİS / 2026-01',
        ),
        const DocQuestionField(
          key: 'targetClass',
          label: 'Öğrencinin Şubesi',
          type: DocFieldType.classSelect,
        ),
        const DocQuestionField(
          key: 'student',
          label: 'Öğrenci Adı Soyadı ve Numarası',
          type: DocFieldType.studentSelect,
        ),
        const DocQuestionField(
          key: 'parentName',
          label: 'Sayın Veli Adı Soyadı',
          type: DocFieldType.text,
          hint: 'Örn: Sayın Ahmet YILMAZ',
        ),
        const DocQuestionField(
          key: 'boardType',
          label: 'İlgili Kurul',
          type: DocFieldType.dropdown,
          options: [
            'Öğrenci Davranışlarını Değerlendirme Kurulu (İlköğretim Md. 57)',
            'Okul Öğrenci Ödül ve Disiplin Kurulu (Ortaöğretim Md. 171)',
          ],
          defaultValue:
              'Öğrenci Davranışlarını Değerlendirme Kurulu (İlköğretim Md. 57)',
        ),
        const DocQuestionField(
          key: 'inviteDate',
          label: 'Görüşme / Savunma Tarihi ve Saati',
          type: DocFieldType.text,
          defaultValue: '.... / .... / 2026 Saat: 14:00',
        ),
        const DocQuestionField(
          key: 'incidentBrief',
          label: 'Görüşme Konusu Davranış / Olay Özeti',
          type: DocFieldType.multiline,
          defaultValue:
              'Okul içi davranış kurallarına uyum ve yaşanan olaya ilişkin pedagojik değerlendirme ve savunma hakkının kullandırılması.',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Sayı / Tarih', '${_str(a, "docNo")} — ${_str(a, "date", _today())}'),
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('İlgili Kurul', _str(a, 'boardType')),
        MapEntry('Davet Zamanı', _str(a, 'inviteDate')),
      ],
      composeBody: (a, ctx) => '''
SAYIN ${_str(a, 'parentName', 'ÖĞRENCİ VELİSİ').toUpperCase()}
(${_str(a, 'student')} Velisi)

Okulumuz ${_str(a, 'targetClass')} şubesi öğrencisi velisi bulunduğunuz ${_str(a, 'student')} hakkında "${_str(a, 'incidentBrief')}" konusuyla ilgili olarak ${_str(a, 'boardType')} Başkanlığınca inceleme ve değerlendirme süreci başlatılmıştır.

İlgili MEB Kurum Yönetmeliği hükümleri uyarınca öğrencimizin yasal savunma hakkının kullandırılması, rehberlik ve aile iş birliği tedbirlerinin görüşülmesi amacıyla ${_str(a, 'inviteDate')} tarihinde okulumuz ilgili müdür yardımcılığı / kurul odasında hazır bulunmanız gerekmektedir. Belirtilen tarihte geçerli mazeret bildirmeksizin katılmamanız halinde değerlendirmenin mevcut dosya evrakı üzerinden yapılacağı hususunda bilgilerinizi ve gereğini rica ederim.

--------------------------------------------------------------------------------
KESİLEBİLİR VELİ TEBELLÜĞ BELGESİ:
Velisi bulunduğum ${_str(a, 'student')} ile ilgili ${_str(a, 'date', _today())} tarihli kurul davet ve savunma bildirim yazısını elden / tebliğ yoluyla teslim aldım.
Tarih: ..../..../2026  |  Veli Adı Soyadı ve İmzası: .............................................''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: ctx.vicePrincipals.isNotEmpty
              ? ctx.vicePrincipals.first.fullName
              : 'Kurul Başkanı',
          title: 'Kurul Başkanı / Müdür Yrd.',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx),
          isApproval: true,
        ),
      ],
    ),

    // 6.7 DYK / İYEP / Akademik Kurs Dönem Sonu Değerlendirme Raporu
    OfficialDocTemplate(
      id: 'kurs_dyk_donem_sonu_raporu',
      code: '6.7',
      categoryId: 'ogretmen_zumre_akademik',
      title: 'DYK / İYEP / Akademik Yetiştirme Kursu Dönem Sonu Değerlendirme Raporu',
      subtitle:
          'Kursa katılan öğrenci devam durumu, kazanım erişi artışı ve dönem sonu öğretmen faaliyet raporu',
      legalBasis:
          'MEB Destekleme ve Yetiştirme Kursları Yönergesi & İYEP Yönergesi',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
        DocRegulationScope.ozelOgretimKurs,
      ],
      audience: DocAudience.teacher,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.trending_up_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Rapor Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'courseType',
          label: 'Kurs / Program Türü',
          type: DocFieldType.dropdown,
          options: [
            'Destekleme ve Yetiştirme Kursu (DYK)',
            'İlkokullarda Yetiştirme Programı (İYEP)',
            'LGS / YKS Sınava Hazırlık ve Takviye Kursu',
            'Okul İçi Akademik Telafi ve Etüt Programı',
          ],
          defaultValue: 'Destekleme ve Yetiştirme Kursu (DYK)',
        ),
        const DocQuestionField(
          key: 'branch',
          label: 'Ders / Alan',
          type: DocFieldType.branchSelect,
        ),
        const DocQuestionField(
          key: 'stats',
          label: 'Kayıtlı Öğrenci Sayısı, Devam Oranı ve Toplam İşlenen Saat',
          type: DocFieldType.text,
          defaultValue: 'Kayıtlı: 20 Öğrenci | Devam Oranı: %92 | İşlenen: 36 Ders Saati',
        ),
        const DocQuestionField(
          key: 'outcomes',
          label: 'Gerçekleştirilen Kazanım ve Gelişim Tespitleri',
          type: DocFieldType.multiCheck,
          options: [
            'Yıllık kurs planında yer alan konu ve öğrenme çıktılarının tamamı süresi içinde işlenmiştir.',
            'Süreç başında yapılan hazırbulunuşluk tespiti ile dönem sonu değerlendirmesi arasında net/puan artışı sağlanmıştır.',
            'Üst düzey düşünme, okuduğunu anlama ve yeni nesil soru çözüm becerileri örnek uygulamalarla pekiştirilmiştir.',
            'Devamsızlık eğilimi gösteren öğrencilerin velileriyle zamanında görüşülerek kursa devamlılık korunmuştur.',
            'Bireysel öğrenme eksikliği devam eden öğrenciler için bir sonraki dönem etüt/takip önerileri sınıf rehber öğretmenine iletilmiştir.',
          ],
          defaultValue: [
            'Yıllık kurs planında yer alan konu ve öğrenme çıktılarının tamamı süresi içinde işlenmiştir.',
            'Süreç başında yapılan hazırbulunuşluk tespiti ile dönem sonu değerlendirmesi arasında net/puan artışı sağlanmıştır.',
            'Üst düzey düşünme, okuduğunu anlama ve yeni nesil soru çözüm becerileri örnek uygulamalarla pekiştirilmiştir.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Program Türü', _str(a, 'courseType')),
        MapEntry('Ders / Branş', _str(a, 'branch', 'Genel')),
        MapEntry('Dönem / Tarih', '${ctx.academicYear} (${ctx.activeTermLabel}) — ${_str(a, "date", _today())}'),
        MapEntry('Sayısal Özet', _str(a, 'stats')),
      ],
      composeBody: (a, ctx) => '''
KURS VE YETİŞTİRME PROGRAMI DÖNEM SONU FAALİYET RAPORU

${ctx.academicYear} eğitim ve öğretim yılında kurumumuzda yürütülen "${_str(a, 'courseType')}" (${_str(a, 'branch')}) çalışmalarına ilişkin dönem sonu akademik değerlendirme bulguları aşağıda sunulmuştur:

DEĞERLENDİRME VE SONUÇ MADDELERİ:
${_numberedLines(_list(a, 'outcomes'))}

İşbu rapor dönem sonu kurs dosyasına konulmak ve okul/kurum müdürlüğüne sunulmak üzere düzenlenmiştir.''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: ctx.currentUser?.fullName ?? 'Kurs Öğretmeni',
          title: '${_str(a, "branch")} Öğretmeni',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'İNCELENDİ / UYGUNDUR'),
          isApproval: true,
        ),
      ],
    ),

    // 9.4 Ders Kitabı / Yayın / Eğitim Materyali Dağıtım ve İmza Çizelgesi
    OfficialDocTemplate(
      id: 'kitap_materyal_dagitim_tutanagi',
      code: '9.4',
      categoryId: 'ortak_liste_kart',
      title: 'Ders Kitabı, Yardımcı Yayın ve Eğitim Materyali Dağıtım İmza Çizelgesi',
      subtitle:
          'MEB ücretsiz ders kitapları, kurumsal yayın seti, deneme fasikülü veya tablet/malzeme teslim imza tablosu',
      legalBasis:
          'MEB Ders Kitapları ve Eğitim Araçları Yönetmeliği & Kurum Yayın Dağıtım Esasları',
      scopes: const [DocRegulationScope.ortakMevzuat],
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.circularSignatureTable,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.auto_stories_rounded,
      customStudentTableHeaders: const [
        'S.No',
        'Şube / No',
        'Öğrenci Adı Soyadı',
        'Teslim Edilen Kitap / Set',
        'Adet / Tam',
        'Öğrenci / Veli İmzası',
      ],
      customStudentRowBuilder: (i, s, a) => [
        '${i + 1}',
        '${s.className} / ${s.studentNo}',
        s.fullName,
        (a['materialName'] ?? 'Tam Set').toString(),
        (a['pieceCount'] ?? 'Tam').toString(),
        '',
      ],
      questions: [
        const DocQuestionField(
          key: 'targetClasses',
          label: 'Dağıtım Yapılan Şube(ler)',
          type: DocFieldType.multiClassSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'materialName',
          label: 'Dağıtılan Kitap / Yayın Seti / Materyal Adı',
          type: DocFieldType.text,
          defaultValue: 'MEB Ders Kitabı ve Kurumsal Soru Bankası Seti',
          required: true,
        ),
        const DocQuestionField(
          key: 'pieceCount',
          label: 'Set / Kitap Adedi Bilgisi',
          type: DocFieldType.text,
          defaultValue: '1 Tam Set',
        ),
        DocQuestionField(
          key: 'date',
          label: 'Dağıtım Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'distributor',
          label: 'Dağıtımı Yapan Öğretmen / Görevli',
          type: DocFieldType.staffSelect,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Dağıtılan Materyal', _str(a, 'materialName')),
        MapEntry('Şubeler / Tarih', '${_list(a, "targetClasses").join(", ")} — ${_str(a, "date", _today())}'),
        MapEntry('Teslim Eden Görevli', _str(a, 'distributor', ctx.currentUser?.fullName ?? 'Sınıf / Ders Öğretmeni')),
      ],
      composeBody: (a, ctx) => '''
KİTAP, YAYIN VE EĞİTİM MATERYALİ TESLİM TUTANAĞI

${ctx.academicYear} eğitim ve öğretim yılında aşağıda kimlik bilgileri yer alan öğrencilerimize "${_str(a, 'materialName')}" (${_str(a, 'pieceCount')}) eksiksiz ve sağlam olarak imza karşılığında teslim edilmiştir:''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(a, 'distributor', ctx.currentUser?.fullName ?? 'Görevli Öğretmen'),
          title: 'Dağıtımı Yapan Görevli',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'ONAY'),
          isApproval: true,
        ),
      ],
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // BAŞLIK 10 ŞABLONLARI: OKUL ÖNCESİ VE İLKÖĞRETİM KURUMLARI YÖNETMELİĞİ
  // ═══════════════════════════════════════════════════════════════════════════
  static final List<OfficialDocTemplate> templates = [
    // 10.1 İYEP Komisyonu Kuruluş ve Öğrenci Belirleme Tutanağı
    OfficialDocTemplate(
      id: 'iyep_komisyon_ogrenci_belirleme',
      code: '10.1',
      categoryId: 'ilkogretim_okul_oncesi_ozel',
      title: 'İYEP (İlkokullarda Yetiştirme Programı) Okul Komisyonu ve Öğrenci Belirleme Tutanağı',
      subtitle:
          '3. ve 4. sınıflarda Türkçe-Matematik ÖBA uygulama sonuçları, modül dağılımı ve öğretmen görevlendirme kararı',
      legalBasis:
          'MEB İlköğretim Kurumları Yönetmeliği Md. 33 & İYEP Yönergesi',
      scopes: const [DocRegulationScope.ilkogretimOkulOncesi],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.school_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Toplantı Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'chair',
          label: 'İYEP Okul Komisyonu Başkanı',
          type: DocFieldType.staffSelect,
        ),
        const DocQuestionField(
          key: 'members',
          label: 'İYEP Komisyonu Üyesi Sınıf / Rehber Öğretmenler',
          type: DocFieldType.multiStaffSelect,
        ),
        const DocQuestionField(
          key: 'summaryCounts',
          label: 'ÖBA Uygulanan ve İYEP\'e Alınan Öğrenci Özeti',
          type: DocFieldType.text,
          defaultValue:
              '3. Sınıf: Türkçe 12 / Matematik 10 Öğrenci — 4. Sınıf: Türkçe 8 / Matematik 9 Öğrenci',
        ),
        const DocQuestionField(
          key: 'schedulePlan',
          label: 'İYEP Uygulama Gün ve Saat Planlaması',
          type: DocFieldType.text,
          defaultValue:
              'Hafta içi ders bitimi / Hafta sonu (Haftalık toplam 6-10 ders saati sınırına uygun)',
        ),
        const DocQuestionField(
          key: 'decisions',
          label: 'Alınan İYEP Komisyon Kararları',
          type: DocFieldType.multiCheck,
          options: [
            '3. ve 4. sınıf şubelerinde Öğrenci Belirleme Aracı (ÖBA) sonuçlarının e-Okul İYEP Modülüne eksiksiz işlenmesine ve baraj puanı altında kalan öğrencilerin ilgili modüllere (Modül 1, 2, 3) yerleştirilmesine karar verildi.',
            'İYEP gruplarının 1-6 veya 7-10 kişilik mevzuat sınırlarına uygun oluşturulmasına; öncelikle öğrencinin kendi sınıf öğretmeninin veya okuldaki diğer sınıf öğretmenlerinin görevlendirilmesine karar verildi.',
            'İYEP kapsamına alınan öğrencilerin velilerine yazılı "İYEP Veli Bilgilendirme ve Sorumluluk Belgesi" imzalatılarak öğrencilerin düzenli devamının sağlanmasına karar verildi.',
            'Özel eğitim tanılaması (RAM raporu) bulunan tam zamanlı kaynaştırma öğrencilerinin İYEP yerine BEP ve Destek Eğitim Odası kapsamında desteklenmesine dikkat edilmesine karar verildi.',
            'Modül sonlarında Öğrenci Değerlendirme Aracı (ÖDA) uygulanarak kazanımlara ulaşan öğrencilerin bir üst modüle geçirilmesine veya programdan mezun edilmesine karar verildi.',
          ],
          defaultValue: [
            '3. ve 4. sınıf şubelerinde Öğrenci Belirleme Aracı (ÖBA) sonuçlarının e-Okul İYEP Modülüne eksiksiz işlenmesine ve baraj puanı altında kalan öğrencilerin ilgili modüllere (Modül 1, 2, 3) yerleştirilmesine karar verildi.',
            'İYEP gruplarının 1-6 veya 7-10 kişilik mevzuat sınırlarına uygun oluşturulmasına; öncelikle öğrencinin kendi sınıf öğretmeninin veya okuldaki diğer sınıf öğretmenlerinin görevlendirilmesine karar verildi.',
            'İYEP kapsamına alınan öğrencilerin velilerine yazılı "İYEP Veli Bilgilendirme ve Sorumluluk Belgesi" imzalatılarak öğrencilerin düzenli devamının sağlanmasına karar verildi.',
            'Modül sonlarında Öğrenci Değerlendirme Aracı (ÖDA) uygulanarak kazanımlara ulaşan öğrencilerin bir üst modüle geçirilmesine veya programdan mezun edilmesine karar verildi.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Komisyon', 'İYEP Okul Yürütme ve Öğrenci Belirleme Komisyonu'),
        MapEntry('Tarih / Öğretim Yılı', '${_str(a, "date", _today())} — ${ctx.academicYear}'),
        MapEntry('Öğrenci Dağılım Özeti', _str(a, 'summaryCounts')),
        MapEntry('Haftalık Çalışma Planı', _str(a, 'schedulePlan')),
      ],
      composeBody: (a, ctx) => '''
${ctx.schoolName} İYEP Okul Komisyonu, MEB İlkokullarda Yetiştirme Programı Yönergesi hükümleri uyarınca önceki eğitim-öğretim dönemlerinden çeşitli nedenlerle Türkçe ve Matematik dersi temel becerilerinde eksiklik yaşayan öğrencileri belirlemek ve yetiştirme planlamasını yapmak üzere ${_str(a, 'date', _today())} tarihinde toplanmıştır.

ALINAN KARARLAR:
${_numberedLines(_list(a, 'decisions'))}

İşbu tutanak e-Okul İYEP Modülü işlemleriyle eş zamanlı yürütülmek üzere imza altına alınmıştır.''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(5))
          DocSigner(name: m, title: 'İYEP Komisyon Üyesi'),
        DocSigner(
          name: _str(a, 'chair', ctx.principalName),
          title: 'İYEP Komisyon Başkanı',
        ),
      ],
    ),

    // 10.2 İlköğretim Sınıf Geçme / Sınıf Tekrarı ŞÖK ve Veli Talebi Tutanağı
    OfficialDocTemplate(
      id: 'ilkogretim_sinif_gecme_tekrar_tutanagi',
      code: '10.2',
      categoryId: 'ilkogretim_okul_oncesi_ozel',
      title: 'İlkokul / Ortaokul Sınıf Geçme ve Sınıf Tekrarı Değerlendirme Tutanağı (Md. 31)',
      subtitle:
          'İlkokulda veli yazılı talebiyle sınıf tekrarı veya ortaokulda ŞÖK sınıf geçme / sınıf tekrarı gerekçeli kararı',
      legalBasis:
          'MEB Okul Öncesi Eğitim ve İlköğretim Kurumları Yönetmeliği Md. 31',
      scopes: const [DocRegulationScope.ilkogretimOkulOncesi],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.rule_folder_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Değerlendirme Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'levelType',
          label: 'Uygulanan Kademe ve Mevzuat Hükmü',
          type: DocFieldType.dropdown,
          options: [
            'Ortaokul (5-8. Sınıf): ŞÖK Kararı ile Sınıf Geçme / Sınıf Tekrarı Değerlendirmesi (Md. 31)',
            'İlkokul (1-4. Sınıf): Veli Yazılı Talebi Üzerine Bir Defaya Mahsus Sınıf Tekrarı (Md. 31)',
            'Sürekli Devamsız (Özürsüz 20 Gün ve Üzeri) Öğrenci Sınıf Tekrarı Tespiti (Md. 31)',
          ],
          defaultValue:
              'Ortaokul (5-8. Sınıf): ŞÖK Kararı ile Sınıf Geçme / Sınıf Tekrarı Değerlendirmesi (Md. 31)',
        ),
        const DocQuestionField(
          key: 'targetClass',
          label: 'Şube Seçimi',
          type: DocFieldType.classSelect,
        ),
        const DocQuestionField(
          key: 'student',
          label: 'Değerlendirilen Öğrenci(ler)',
          type: DocFieldType.multiStudentSelect,
        ),
        const DocQuestionField(
          key: 'academicSummary',
          label: 'Yıl Sonu Başarı Puanı, Türkçe Ortalaması ve Devamsızlık Bilgisi',
          type: DocFieldType.multiline,
          defaultValue:
              'Öğrencinin yıl sonu ders puanları, Türkçe dersi 70,00 yeterlilik ölçütü, özürsüz devamsızlık gün sayısı ve gelişim düzeyi kurulca ayrıntılı incelenmiştir.',
        ),
        const DocQuestionField(
          key: 'verdict',
          label: 'Alınan Kurul / İdare Kararı',
          type: DocFieldType.dropdown,
          options: [
            'ŞÖK Kararı İle Bir Üst Sınıfa Geçmesine (Destekleme Tedbirleriyle) Karar Verildi',
            'Akademik Yetersizlik / Devamsızlık Nedeniyle Sınıf Tekrar Etmesine Karar Verildi',
            'İlkokul Veli Dilekçesi ve Sınıf Öğretmeni Görüşü Doğrultusunda Bir Defaya Mahsus Sınıf Tekrarına Karar Verildi',
          ],
          defaultValue:
              'ŞÖK Kararı İle Bir Üst Sınıfa Geçmesine (Destekleme Tedbirleriyle) Karar Verildi',
        ),
        const DocQuestionField(
          key: 'teachers',
          label: 'Kurula Katılan Ders / Sınıf ve Rehber Öğretmenler',
          type: DocFieldType.multiStaffSelect,
        ),
        const DocQuestionField(
          key: 'includeSokSignatureTable',
          label: 'Tutanak Sonuna ŞÖK Öğretmen İmza Sirküsü Tablosu Eklensin mi?',
          type: DocFieldType.yesNo,
          defaultValue: true,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Mevzuat Kapsamı', _str(a, 'levelType')),
        MapEntry('Şube / Tarih', '${_str(a, "targetClass")} — ${_str(a, "date", _today())}'),
        MapEntry('İlgili Öğrenci(ler)', _list(a, 'student').join(', ')),
        MapEntry('Nihai Karar', _str(a, 'verdict')),
      ],
      composeBody: (a, ctx) {
        final cls = _str(a, 'targetClass');
        final rawTeachers = _list(a, 'teachers');
        final effectiveTeachers = rawTeachers.isNotEmpty
            ? rawTeachers
            : (ctx.classTeachersByClass[cls] ?? const []);
        final teachersBlock = effectiveTeachers.isNotEmpty
            ? '\n\nKATILAN ŞUBE ÖĞRETMENLER KURULU ÜYELERİ:\n${effectiveTeachers.join(", ")}'
            : '';
        return '''
SINIF GEÇME VE SINIF TEKRARI DEĞERLENDİRME TUTANAĞI

MEB Okul Öncesi Eğitim ve İlköğretim Kurumları Yönetmeliğinin 31 inci maddesi hükümleri çerçevesinde, okulumuz $cls şubesi öğrencisi/öğrencileri (${_list(a, 'student').join(', ')}) hakkında yıl sonu akademik ve gelişimsel durum değerlendirmesi yapılmıştır.$teachersBlock

İNCELEME VE GEREKÇE:
${_str(a, 'academicSummary')}

KARAR:
Yapılan müzakere ve oylama sonucunda ilgili mevzuat hükmü gereğince öğrencinin/öğrencilerin:
"${_str(a, 'verdict')}" yönünde karar alınmış olup kararın e-Okul Yönetim Bilgi Sistemine işlenmesine ve veliye tebliğine oy birliği/çokluğu ile karar verilmiştir.''';
      },
      buildSigners: (a, ctx) => [
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'Kurul Başkanı'),
          isApproval: true,
        ),
      ],
    ),

    // 10.3 Okul Öncesi / 1. ve 5. Sınıflar Uyum Eğitimi Haftası Raporu
    OfficialDocTemplate(
      id: 'uyum_egitimi_haftasi_raporu',
      code: '10.3',
      categoryId: 'ilkogretim_okul_oncesi_ozel',
      title: 'Okul Öncesi, 1. Sınıf ve 5. Sınıflar Uyum Eğitimi Haftası Faaliyet Raporu',
      subtitle:
          'Okula uyum programı etkinlikleri, veli oryantasyon semineri ve uyum gözlem sonuç tutanağı',
      legalBasis:
          'MEB Okul Öncesi Eğitim ve İlköğretim Kurumları Yönetmeliği Uyum Eğitimi Esasları',
      scopes: const [DocRegulationScope.ilkogretimOkulOncesi],
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.emoji_emotions_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Rapor Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'gradeScope',
          label: 'Uyum Eğitimi Uygulanan Kademe',
          type: DocFieldType.dropdown,
          options: [
            'Okul Öncesi / Anasınıfı Uyum Eğitimi Programı',
            'İlkokul 1. Sınıflar Okula Uyum Haftası Programı',
            'Ortaokul 5. Sınıflar Kademe Geçiş ve Uyum Programı',
          ],
          defaultValue: 'Ortaokul 5. Sınıflar Kademe Geçiş ve Uyum Programı',
        ),
        const DocQuestionField(
          key: 'activities',
          label: 'Uygulanan Uyum Etkinlikleri ve Gözlemler',
          type: DocFieldType.multiCheck,
          options: [
            'Öğrenci ve velilere okul yöneticileri, sınıf/branş öğretmenleri ve rehberlik servisi tanıtılmıştır.',
            'Derslikler, kütüphane, yemekhane, kantin, lavabolar, bahçe oyun alanları ve acil çıkış kapıları uygulamalı olarak gezdirilmiştir.',
            'Tanışma oyunları, aidiyet geliştirici grup etkinlikleri ve okul kuralları oryantasyonu gerçekleştirilmiştir.',
            'Velilere yönelik Rehberlik Servisi tarafından "Okula Uyum Sürecinde Aile Yaklaşımı ve Ayrılık Kaygısı" bilgilendirme toplantısı yapılmıştır.',
            'Ayrılık kaygısı veya uyum güçlüğü gözlenen öğrenciler tespit edilerek PDR Servisi bireysel izleme listesine alınmıştır.',
          ],
          defaultValue: [
            'Öğrenci ve velilere okul yöneticileri, sınıf/branş öğretmenleri ve rehberlik servisi tanıtılmıştır.',
            'Derslikler, kütüphane, yemekhane, kantin, lavabolar, bahçe oyun alanları ve acil çıkış kapıları uygulamalı olarak gezdirilmiştir.',
            'Tanışma oyunları, aidiyet geliştirici grup etkinlikleri ve okul kuralları oryantasyonu gerçekleştirilmiştir.',
            'Velilere yönelik Rehberlik Servisi tarafından "Okula Uyum Sürecinde Aile Yaklaşımı ve Ayrılık Kaygısı" bilgilendirme toplantısı yapılmıştır.',
          ],
        ),
        const DocQuestionField(
          key: 'staff',
          label: 'Uygulamayı Yürüten Öğretmen / PDR Ekibi',
          type: DocFieldType.multiStaffSelect,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Uygulama Kademesi', _str(a, 'gradeScope')),
        MapEntry('Rapor Tarihi', '${_str(a, "date", _today())} — ${ctx.academicYear}'),
      ],
      composeBody: (a, ctx) => '''
OKULA UYUM EĞİTİMİ HAFTASI PLANLAMA VE DEĞERLENDİRME RAPORU

${ctx.academicYear} eğitim ve öğretim yılı başında ${ctx.schoolName} bünyesinde "${_str(a, 'gradeScope')}" kapsamında yürütülen uyum çalışmaları tamamlanmış olup gerçekleştirilen faaliyetler aşağıda kayıt altına alınmıştır:

GERÇEKLEŞTİRİLEN FAALİYETLER VE TESPİTLER:
${_numberedLines(_list(a, 'activities'))}

Uyum haftası çalışmaları planlanan takvime uygun ve sorunsuz şekilde tamamlanarak okul müdürlüğüne sunulmuştur.''',
      buildSigners: (a, ctx) => [
        for (final s in _list(a, 'staff').take(4))
          DocSigner(name: s, title: 'Uygulayıcı Öğretmen / PDR'),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'İNCELENDİ / ONAY'),
          isApproval: true,
        ),
      ],
    ),

    // 10.4 Okul Öncesi Gelişim Gözlem, Beceri Edinimi ve Portfolyo Veli Sunum Çizelgesi
    OfficialDocTemplate(
      id: 'okul_oncesi_gelisim_portfolyo_tutanagi',
      code: '10.4',
      categoryId: 'ilkogretim_okul_oncesi_ozel',
      title: 'Okul Öncesi Gelişim Gözlem, Beceri Edinimi ve Portfolyo Paylaşım Çizelgesi',
      subtitle:
          'Okul öncesi dönemlik gelişim raporu ve portfolyo sunum günü veli teslim/imza çizelgesi',
      legalBasis:
          'MEB Okul Öncesi Eğitim ve İlköğretim Kurumları Yönetmeliği Md. 30',
      scopes: const [DocRegulationScope.ilkogretimOkulOncesi],
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.circularSignatureTable,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.palette_rounded,
      customStudentTableHeaders: const [
        'S.No',
        'Şube / No',
        'Öğrenci Adı Soyadı',
        'Gelişim Raporu / Portfolyo',
        'Veli Adı Soyadı',
        'Veli İmzası',
      ],
      customStudentRowBuilder: (i, s, a) => [
        '${i + 1}',
        '${s.className} / ${s.studentNo}',
        s.fullName,
        'Teslim Edildi',
        s.parentName,
        '',
      ],
      questions: [
        const DocQuestionField(
          key: 'targetClasses',
          label: 'Okul Öncesi / Anasınıfı Şubesi',
          type: DocFieldType.multiClassSelect,
          required: true,
        ),
        DocQuestionField(
          key: 'date',
          label: 'Portfolyo Paylaşım / Teslim Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'teacher',
          label: 'Okul Öncesi Öğretmeni',
          type: DocFieldType.staffSelect,
        ),
        const DocQuestionField(
          key: 'summary',
          label: 'Dönemlik Gelişim Alanları Genel Değerlendirme Notu',
          type: DocFieldType.multiline,
          defaultValue:
              'Çocuklarımızın bilişsel, dil, sosyal-duygusal, fiziksel/hareket ve öz bakım becerilerine ilişkin gelişim gözlem kayıtları ile dönem içi ürün dosyaları (portfolyo) aile katılım etkinliğinde velilerimizle paylaşılmıştır.',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Şube / Grup', _list(a, 'targetClasses').join(', ')),
        MapEntry('Tarih / Dönem', '${_str(a, "date", _today())} — ${ctx.activeTermLabel}'),
        MapEntry('Sınıf Öğretmeni', _str(a, 'teacher', ctx.currentUser?.fullName ?? 'Okul Öncesi Öğretmeni')),
      ],
      composeBody: (a, ctx) => '''
BECERİ EDİNİMİ / GELİŞİM RAPORU VE PORTFOLYO DOSYASI VELİ TESLİM TUTANAĞI

${_str(a, 'summary')}

Aşağıda isimleri yazılı öğrencilerimizin dönemlik Gelişim Gözlem Raporu ve Portfolyo Dosyası velilerine imza karşılığı teslim edilmiştir:''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(a, 'teacher', ctx.currentUser?.fullName ?? 'Okul Öncesi Öğretmeni'),
          title: 'Okul Öncesi Öğretmeni',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'UYGUNDUR'),
          isApproval: true,
        ),
      ],
    ),

    // 10.5 Destek Eğitim Odası Açılış Onayı ve Öğretmen Görevlendirme Tutanağı
    OfficialDocTemplate(
      id: 'destek_egitim_odasi_acilis_tutanagi',
      code: '10.5',
      categoryId: 'ilkogretim_okul_oncesi_ozel',
      title: 'Destek Eğitim Odası Açılış, Öğrenci Planlama ve Öğretmen Görevlendirme Tutanağı',
      subtitle:
          'RAM raporu ve BEP Birimi kararıyla kaynaştırma / özel yetenekli öğrenciler için destek eğitim planı',
      legalBasis:
          'MEB Özel Eğitim Hizmetleri Yönetmeliği Md. 25 & İlköğretim/Ortaöğretim Yönetmeliği',
      scopes: const [
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.accessibility_new_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Karar Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'targetClass',
          label: 'Öğrencinin Kayıtlı Olduğu Şube',
          type: DocFieldType.classSelect,
        ),
        const DocQuestionField(
          key: 'student',
          label: 'Destek Eğitim Alacak Öğrenci(ler)',
          type: DocFieldType.multiStudentSelect,
        ),
        const DocQuestionField(
          key: 'ramInfo',
          label: 'RAM Özel Eğitim Değerlendirme Kurulu Rapor Tarih ve Sayısı',
          type: DocFieldType.text,
          defaultValue: 'RAM Raporu mevcuttur (BEP dosyasında saklıdır)',
        ),
        const DocQuestionField(
          key: 'weeklyHours',
          label: 'Haftalık Destek Eğitim Dersleri ve Saat Dağılımı (%40 Sınırı Dahilinde)',
          type: DocFieldType.text,
          defaultValue: 'Türkçe: 4 Saat, Matematik: 4 Saat (Toplam Haftalık 8 Ders Saati - Birebir Eğitim)',
        ),
        const DocQuestionField(
          key: 'teachers',
          label: 'Destek Eğitim Odasında Görevlendirilen Öğretmen(ler)',
          type: DocFieldType.multiStaffSelect,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Öğrenci(ler) / Şube', '${_list(a, "student").join(", ")} (${_str(a, "targetClass")})'),
        MapEntry('Dayanak RAM Raporu', _str(a, 'ramInfo')),
        MapEntry('Ders ve Saat Planı', _str(a, 'weeklyHours')),
        MapEntry('Karar Tarihi', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
DESTEK EĞİTİM ODASI PLANLAMA VE ÖĞRETMEN GÖREVLENDİRME TUTANAĞI

MEB Özel Eğitim Hizmetleri Yönetmeliğinin 25 inci maddesi ve Okul BEP Geliştirme Birimi kararı doğrultusunda; okulumuzda tam zamanlı kaynaştırma/bütünleştirme yoluyla eğitim gören veya özel yetenekli tanısı bulunan ${_list(a, 'student').join(', ')} adlı öğrencimiz için Destek Eğitim Odası eğitim planlaması aşağıda belirtildiği şekilde kararlaştırılmıştır:

1. Öğrencinin haftalık toplam ders saatinin %40'ını aşmayacak şekilde (${_str(a, 'weeklyHours')}) birebir destek eğitimi almasına,
2. Öğrenci velisinin yazılı muvafakatinin alınarak BEP hedeflerine uygun bireyselleştirilmiş materyal ve etkinliklerin uygulanmasına,
3. Destek eğitim odası ders defterinin ve gelişim izleme formlarının görevli öğretmenlerce düzenli tutulmasına,
4. İlçe Milli Eğitim Müdürlüğü onayı / MEBBİS işlemleriyle koordineli yürütülmesine karar verilmiştir.''',
      buildSigners: (a, ctx) => [
        for (final t in _list(a, 'teachers').take(4))
          DocSigner(name: t, title: 'Görevli Destek Eğitim Öğretmeni'),
        if (ctx.counselors.isNotEmpty)
          DocSigner(
            name: ctx.counselors.first.fullName,
            title: 'BEP Birimi Üyesi (PDR)',
          ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'BEP Birim Başkanı / UYGUNDUR'),
          isApproval: true,
        ),
      ],
    ),

    // 10.6 İlköğretim Öğrenci Davranışlarını Değerlendirme Kurulu (ÖDDK) Karar Tutanağı
    OfficialDocTemplate(
      id: 'ilkogretim_oddk_karar_dosyasi',
      code: '10.6',
      categoryId: 'ilkogretim_okul_oncesi_ozel',
      title: 'İlköğretim ÖDDK (Öğrenci Davranışlarını Değerlendirme Kurulu) Yaptırım Karar Tutanağı',
      subtitle:
          'Ortaokul/İHO Md. 53-61 kapsamında Uyarma, Kınama, Okul Değiştirme veya Rehberlik Tedbiri karar dosyası',
      legalBasis:
          'MEB Okul Öncesi Eğitim ve İlköğretim Kurumları Yönetmeliği Md. 53–61',
      scopes: const [DocRegulationScope.ilkogretimOkulOncesi],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.balance_rounded,
      questions: [
        const DocQuestionField(
          key: 'decisionNo',
          label: 'ÖDDK Karar Sayısı ve Tarihi',
          type: DocFieldType.text,
          defaultValue: 'Karar No: 2026/02',
        ),
        DocQuestionField(
          key: 'date',
          label: 'Toplantı Tarihi',
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
          label: 'Hakkında Değerlendirme Yapılan Öğrenci',
          type: DocFieldType.studentSelect,
        ),
        const DocQuestionField(
          key: 'article',
          label: 'Yönetmelik Kapsamındaki Davranış Maddesi ve Olay Özeti',
          type: DocFieldType.multiline,
          defaultValue:
              'Yönetmeliğin 55 inci maddesi kapsamında incelenen olay tutanağı, tanık ifadeleri, sınıf rehber öğretmeni ve PDR servisi görüş raporu kurulumuzca değerlendirilmiştir.',
        ),
        const DocQuestionField(
          key: 'sanction',
          label: 'ÖDDK Tarafından Verilen Nihai Karar / Yaptırım',
          type: DocFieldType.dropdown,
          options: [
            'Yaptırım Uygulanmasına Yer Olmadığına — Rehberlik Servisi ve Aile İş Birliği Tedbiri Uygulanmasına',
            'Md. 55/1-a Uyarınca "UYARMA" Yaptırımı Verilmesine (İyi Hal / Pişmanlık Değerlendirilerek)',
            'Md. 55/1-b Uyarınca "KINAMA" Yaptırımı Verilmesine',
            'Md. 55/1-c Uyarınca "OKUL DEĞİŞTİRME" Teklifinin İlçe Öğrenci Davranışlarını Değerlendirme Kuruluna Sunulmasına',
          ],
          defaultValue:
              'Yaptırım Uygulanmasına Yer Olmadığına — Rehberlik Servisi ve Aile İş Birliği Tedbiri Uygulanmasına',
        ),
        const DocQuestionField(
          key: 'members',
          label: 'ÖDDK Üyeleri',
          type: DocFieldType.multiStaffSelect,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Karar No / Tarih', '${_str(a, "decisionNo")} — ${_str(a, "date", _today())}'),
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Kurul Kararı', _str(a, 'sanction')),
      ],
      composeBody: (a, ctx) => '''
ÖĞRENCİ DAVRANIŞLARINI DEĞERLENDİRME KURULU (ÖDDK) KARAR TUTANAĞI

OLAYIN ÖZETİ, SAVUNMA VE REHBERLİK İNCELEMESİ:
${_str(a, 'article')}

Öğrencinin yazılı/sözlü savunması alınmış; yaşı, gelişim özellikleri, olayın meydana geliş biçimi, daha önce olumsuz bir davranışının bulunup bulunmadığı ve pişmanlık durumu Yönetmeliğin 56 ncı maddesi uyarınca titizlikle değerlendirilmiştir.

KURUL KARARI:
Yapılan gizli/açık müzakere sonucunda oy birliği/çokluğu ile;
"${_str(a, 'sanction')}"
karar verilmiş olup, kararın veliye yazılı tebliğine ve yasal itiraz süresinin (tebliğden itibaren 5 iş günü) hatırlatılmasına karar verilmiştir.''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(4))
          DocSigner(name: m, title: 'ÖDDK Üyesi'),
        DocSigner(
          name: ctx.vicePrincipals.isNotEmpty
              ? ctx.vicePrincipals.first.fullName
              : 'ÖDDK Başkanı',
          title: 'ÖDDK Başkanı (Md. Yrd.)',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'ONAY'),
          isApproval: true,
        ),
      ],
    ),

    // 10.7 İlkokul / Ortaokul Kayıt-Kabul, Şube ve Öğretmen Kura Komisyonu Tutanağı
    OfficialDocTemplate(
      id: 'ilkogretim_kayit_kura_komisyonu',
      code: '10.7',
      categoryId: 'ilkogretim_okul_oncesi_ozel',
      title: 'Okul Öncesi / 1. ve 5. Sınıflar Şube ve Öğretmen Kura Belirleme Komisyonu Tutanağı',
      subtitle:
          'Şubelerin dengeli oluşturulması, kaynaştırma dağılımı ve e-Okul / veli huzurunda şube kura tutanağı',
      legalBasis:
          'MEB Okul Öncesi Eğitim ve İlköğretim Kurumları Yönetmeliği Md. 11–13',
      scopes: const [DocRegulationScope.ilkogretimOkulOncesi],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.shuffle_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Komisyon / Kura Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'gradeLevel',
          label: 'Şube Dağılımı Yapılan Kademe',
          type: DocFieldType.dropdown,
          options: [
            'İlkokul 1. Sınıflar Şube ve Sınıf Öğretmeni Belirleme',
            'Ortaokul 5. Sınıflar Şube Dağılım ve Kura İşlemleri',
            'Okul Öncesi / Anasınıfı Yaş Grubu ve Şube Planlaması',
          ],
          defaultValue: 'Ortaokul 5. Sınıflar Şube Dağılım ve Kura İşlemleri',
        ),
        const DocQuestionField(
          key: 'members',
          label: 'Komisyon Üyesi İdareci ve Öğretmenler',
          type: DocFieldType.multiStaffSelect,
        ),
        const DocQuestionField(
          key: 'decisions',
          label: 'Uygulanan Mevzuat Esasları ve Kararlar',
          type: DocFieldType.multiCheck,
          options: [
            'Kayıt bölgesi (MERNİS/e-Kayıt) listesindeki öğrencilerin kız-erkek dağılımı ve şube mevcutları eşit/dengeli olacak biçimde planlanmıştır.',
            'MEB merkezî e-Okul otomatik şube/öğretmen kura algoritması sonuçları esas alınarak hiçbir ayrıcalığa yer verilmeden kesin şube listeleri oluşturulmuştur.',
            'Özel eğitim (kaynaştırma/bütünleştirme) raporu bulunan öğrencilerin her şubede en fazla 2 öğrenci olacak şekilde dengeli yerleştirilmesi sağlanmıştır.',
            'İkiz/çoğul gebelik kardeşi olan öğrencilerin veli dilekçesi doğrultusunda aynı veya farklı şubelerde bulunma talepleri mevzuat çerçevesinde işlenmiştir.',
            'Kesinleşen şube listelerinin okul ilan panosunda ve veli bilgilendirme sisteminde duyurulmasına karar verilmiştir.',
          ],
          defaultValue: [
            'Kayıt bölgesi (MERNİS/e-Kayıt) listesindeki öğrencilerin kız-erkek dağılımı ve şube mevcutları eşit/dengeli olacak biçimde planlanmıştır.',
            'MEB merkezî e-Okul otomatik şube/öğretmen kura algoritması sonuçları esas alınarak hiçbir ayrıcalığa yer verilmeden kesin şube listeleri oluşturulmuştur.',
            'Özel eğitim (kaynaştırma/bütünleştirme) raporu bulunan öğrencilerin her şubede en fazla 2 öğrenci olacak şekilde dengeli yerleştirilmesi sağlanmıştır.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('İşlem Kapsamı', _str(a, 'gradeLevel')),
        MapEntry('Komisyon Tarihi', '${_str(a, "date", _today())} — ${ctx.academicYear}'),
      ],
      composeBody: (a, ctx) => '''
KAYIT-KABUL VE ŞUBE BELİRLEME KOMİSYONU TUTANAĞI

${ctx.academicYear} eğitim ve öğretim yılında ${ctx.schoolName} bünyesinde "${_str(a, 'gradeLevel')}" işlemlerinin şeffaflık, fırsat eşitliği ve MEB İlköğretim Kurumları Yönetmeliği hükümlerine tam uygunluk içinde yürütülmesi amacıyla aşağıdaki kararlar alınarak uygulanmıştır:

UYGULAMA VE KARAR MADDELERİ:
${_numberedLines(_list(a, 'decisions'))}

İşbu tutanak komisyon üyelerince imza altına alınmıştır.''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(4))
          DocSigner(name: m, title: 'Komisyon Üyesi'),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'Komisyon Başkanı'),
          isApproval: true,
        ),
      ],
    ),

    // 10.8 Evde veya Hastanede Eğitim Hizmeti Planlama Tutanağı
    OfficialDocTemplate(
      id: 'evde_hastanede_egitim_tutanagi',
      code: '10.8',
      categoryId: 'ilkogretim_okul_oncesi_ozel',
      title: 'Evde veya Hastanede Eğitim Hizmeti Planlama ve Öğretmen Görevlendirme Tutanağı',
      subtitle:
          'Sağlık kurulu raporu nedeniyle okula devam edemeyen öğrenci için haftalık ders planı ve veli iş birliği tutanağı',
      legalBasis:
          'MEB Evde ve Hastanede Eğitim Hizmetleri Yönergesi & Özel Eğitim Yönetmeliği Md. 14',
      scopes: const [
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.home_work_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Planlama Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'targetClass',
          label: 'Öğrencinin Kayıtlı Olduğu Şube',
          type: DocFieldType.classSelect,
        ),
        const DocQuestionField(
          key: 'student',
          label: 'Öğrenci Adı Soyadı',
          type: DocFieldType.studentSelect,
        ),
        const DocQuestionField(
          key: 'medicalInfo',
          label: 'Sağlık Kurulu Raporu ve İlçe Özel Eğitim Hizmetleri Kurulu Kararı',
          type: DocFieldType.text,
          defaultValue: 'En az 12 hafta örgün eğitime devam edemeyeceğine dair durum bildirir sağlık kurulu raporu ve İlçe Kurulu kararı',
        ),
        const DocQuestionField(
          key: 'programDetail',
          label: 'Haftalık Ders Saati ve Ders Dağılım Planı',
          type: DocFieldType.text,
          defaultValue: 'Haftalık 10 ders saati temel akademik dersler (BEP / Öğretim Programı uyumlu)',
        ),
        const DocQuestionField(
          key: 'teachers',
          label: 'Görevlendirilen Öğretmen(ler)',
          type: DocFieldType.multiStaffSelect,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Resmi Dayanak', _str(a, 'medicalInfo')),
        MapEntry('Haftalık Program', _str(a, 'programDetail')),
        MapEntry('Tarih', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
EVDE / HASTANEDE EĞİTİM HİZMETİ PLANLAMA TUTANAĞI

Sağlık problemi nedeniyle örgün eğitim kurumundan doğrudan yararlanamayacağı resmi sağlık kurulu raporu ile belgelendirilen okulumuz ${_str(a, 'targetClass')} şubesi öğrencisi ${_str(a, 'student')} için MEB Evde ve Hastanede Eğitim Hizmetleri Yönergesi uyarınca eğitim-öğretim planlaması yapılmıştır.

1. Öğrencinin haftalık ders programı (${_str(a, 'programDetail')}) veli ile mutabık kalınan gün ve saatlerde yürütülecektir.
2. Ev ortamının eğitim-öğretime, hijyen ve iş sağlığı güvenliği koşullarına uygunluğu veli taahhüdü altına alınmıştır.
3. Öğrencinin başarı değerlendirmesi, sınav uygulamaları ve e-Okul not girişleri kayıtlı bulunduğu okulumuz üzerinden takip edilecektir.''',
      buildSigners: (a, ctx) => [
        for (final t in _list(a, 'teachers').take(3))
          DocSigner(name: t, title: 'Görevli Öğretmen'),
        const DocSigner(
          name: 'Öğrenci Velisi',
          title: 'Ev Ortamı Taahhüt / Veli',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'UYGUNDUR'),
          isApproval: true,
        ),
      ],
    ),
  ];
}

