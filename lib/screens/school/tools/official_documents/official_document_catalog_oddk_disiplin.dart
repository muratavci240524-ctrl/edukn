import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../models/school/official_document_model.dart';

/// MEB Okul Öncesi Eğitim ve İlköğretim Kurumları Yönetmeliği (Md. 53–61 & EK-9)
/// ve MEB Ortaöğretim Kurumları Yönetmeliği (Md. 163–178) Uyarınca
/// Adım Adım Tam ÖDDK ve Öğrenci Disiplin Soruşturma Süreci Dosya Paketi (ÖDDK-01 .. ÖDDK-16)
class OfficialDocumentCatalogOddkDisiplin {
  static String _today() => DateFormat('dd.MM.yyyy').format(DateTime.now());
  static String _nowTime() => DateFormat('HH:mm').format(DateTime.now());

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

  static String _numberedLines(List<String> items, {String prefix = ''}) {
    if (items.isEmpty) return '';
    final buf = StringBuffer();
    for (int i = 0; i < items.length; i++) {
      buf.writeln('$prefix${i + 1}. ${items[i]}');
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

  static String _blankLines(int count) => List.generate(
    count,
    (_) =>
        '........................................................................................................................................',
  ).join('\n\n');

  // ═══════════════════════════════════════════════════════════════════════════
  // ÖDDK VE ÖĞRENCİ DİSİPLİN SÜRECİ TAM DOSYA PAKETİ KATEGORİSİ
  // ═══════════════════════════════════════════════════════════════════════════
  static const OfficialDocCategory category = OfficialDocCategory(
    id: 'oddk_disiplin_surec_paketi',
    order: 5,
    title:
        '4B. ÖDDK ve Öğrenci Disiplin Soruşturma Süreci — Tam Dosya Paketi (16 Adım)',
    subtitle:
        'Sözlü Uyarı -> EK-9 Öğrenci Sözleşmesi -> Veli Önlem/Gelmeme -> Olay Tespit -> Sevk -> Havale -> Mağdur/Tanık İfade -> Savunma -> PDR Raporu -> Kurul Çağrısı -> Uzlaşma -> Karar -> Tebligat -> Ceza Silme',
    audience: DocAudience.admin,
    icon: Icons.account_balance_rounded,
    color: Color(0xFF991B1B),
    scopes: [
      DocRegulationScope.ortakMevzuat,
      DocRegulationScope.ilkogretimOkulOncesi,
      DocRegulationScope.ortaogretimLise,
    ],
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // ADIM ADIM 16 RESMİ EVRAK ŞABLONU (ÖDDK-01 .. ÖDDK-16)
  // ═══════════════════════════════════════════════════════════════════════════
  static final List<OfficialDocTemplate> templates = [
    // ─────────────────────────────────────────────────────────────────────────
    // ÖDDK-01: ÖĞRETMEN SÖZLÜ UYARI VE YAPICI GÖRÜŞME TUTANAĞI (MD. 54/1)
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'oddk_01_sozlu_uyari_yapici_gorusme',
      code: 'ÖDDK-01',
      categoryId: 'oddk_disiplin_surec_paketi',
      title:
          '1. Adım: Öğretmen Sözlü Uyarı, Yapıcı Görüşme ve İlk Farkındalık Tutanağı',
      subtitle:
          'MEB İlköğretim Md. 54/1 ve Ortaöğretim Md. 163 uyarınca kurula sevk öncesi zorunlu 1. aşama sözlü uyarı kaydı',
      legalBasis:
          'MEB İlköğretim Kurumları Yönetmeliği Md. 54/1 & Ortaöğretim Kurumları Yönetmeliği Md. 163',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.record_voice_over_rounded,
      questions: [
        const DocQuestionField(
          key: 'targetClass',
          label: 'Öğrencinin Şubesi',
          type: DocFieldType.classSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'student',
          label: 'Sözlü Uyarı ve Yapıcı Görüşme Yapılan Öğrenci',
          type: DocFieldType.studentSelect,
          required: true,
        ),
        DocQuestionField(
          key: 'date',
          label: 'Görüşme Tarihi ve Saati',
          type: DocFieldType.text,
          defaultValue: '${_today()} - ${_nowTime()}',
        ),
        const DocQuestionField(
          key: 'teacher',
          label: 'Görüşmeyi Yapan Ders / Sınıf Rehber Öğretmeni',
          type: DocFieldType.staffSelect,
        ),
        const DocQuestionField(
          key: 'observedBehaviors',
          label: 'Gözlemlenen Olumsuz Davranışlar (Birden Fazla Seçilebilir)',
          type: DocFieldType.multiCheck,
          options: [
            'Derse geç girme, ders araç-gereçlerini sürekli eksik getirme ve derse hazırlıksız gelme',
            'Ders işlenişi sırasında izinsiz konuşarak veya dolaşarak sınıfın öğrenme dikkatini dağıtma',
            'Verilen ödev, görev ve sınıf içi etkinlik sorumluluklarını alışkanlık halinde yerine getirmeme',
            'Arkadaşlarına karşı kırıcı hitap, alay etme, lakap takma veya dışlayıcı tutum sergileme',
            'Teneffüslerde koridor ve merdivenlerde koşma, itişme veya fiziksel güvenliği tehlikeye atma',
            'Okul kılık-kıyafet kurallarına ve kişisel temizlik/düzen esaslarına uymama',
            'Sınıf ve okul eşyalarını (sıra, masa, etkileşimli tahta, pano) özensiz kullanma ve kirletme',
            'Ders saatinde cep telefonu, akıllı saat veya ders dışı materyalle ilgilenme',
            'Grup çalışmalarında iş birliğinden kaçınma ve sınıf kurallarına direnç gösterme',
            'Bayrak töreni ve ortak okul etkinliklerinde tören düzenine uymama',
            'Kantin, yemekhane veya servis sırasında akranlarının hakkına saygı göstermeme',
            'Öğretmenlerinin pedagojik uyarılarına karşı ilgisiz veya olumsuz beden dili sergileme',
            'Sınıf arkadaşlarının eşyalarını izinsiz alma veya karıştırma',
            'Okul ve sınıf temizliği / Sıfır Atık kurallarına riayet etmeme',
          ],
          defaultValue: [
            'Ders işlenişi sırasında izinsiz konuşarak veya dolaşarak sınıfın öğrenme dikkatini dağıtma',
            'Arkadaşlarına karşı kırıcı hitap, alay etme, lakap takma veya dışlayıcı tutum sergileme',
          ],
        ),
        const DocQuestionField(
          key: 'pedagogicalSteps',
          label: 'Öğretmen Tarafından Uygulanan Yapıcı ve Pedagojik Yaklaşımlar',
          type: DocFieldType.multiCheck,
          options: [
            'Öğrenci ile akranlarının önünde rencide edilmeden, ders dışı uygun ortamda birebir yapıcı görüşme yapıldı.',
            'Davranışın kendisi, arkadaşları ve sınıf iklimi üzerindeki olumsuz etkileri somut örneklerle açıklandı.',
            'Öğrencinin davranışı sergileme nedenleri yargılanmadan dinlendi ve duygularını doğru ifade etme yolları konuşuldu.',
            'Okul ve sınıf kuralları ile beklenen olumlu davranış standartları açık ve anlaşılır dille hatırlatıldı.',
            'Sınıf içinde olumlu sorumluluk verilerek ve oturma düzeni gözden geçirilerek öğrencinin derse katılımı desteklendi.',
            'Olumlu davranış değişikliği gözlemlendiğinde sözel takdir ve pekiştireç verileceği belirtildi.',
            'Sınıf rehber öğretmeni ve Okul Rehberlik (PDR) Servisi ile koruyucu-önleyici bilgi paylaşımı planlandı.',
            'Davranışın tekrarı halinde MEB İlköğretim Yönetmeliği Md. 54 uyarınca 2. aşama olan "Öğrenci Sözleşmesi (EK-9)" adımına geçileceği pedagojik dille izah edildi.',
          ],
          defaultValue: [
            'Öğrenci ile akranlarının önünde rencide edilmeden, ders dışı uygun ortamda birebir yapıcı görüşme yapıldı.',
            'Davranışın kendisi, arkadaşları ve sınıf iklimi üzerindeki olumsuz etkileri somut örneklerle açıklandı.',
            'Öğrencinin davranışı sergileme nedenleri yargılanmadan dinlendi ve duygularını doğru ifade etme yolları konuşuldu.',
            'Okul ve sınıf kuralları ile beklenen olumlu davranış standartları açık ve anlaşılır dille hatırlatıldı.',
            'Davranışın tekrarı halinde MEB İlköğretim Yönetmeliği Md. 54 uyarınca 2. aşama olan "Öğrenci Sözleşmesi (EK-9)" adımına geçileceği pedagojik dille izah edildi.',
          ],
        ),
        const DocQuestionField(
          key: 'studentNote',
          label: 'Öğrencinin Görüşmedeki İfadesi ve Davranış Değişikliği Sözü (Opsiyonel)',
          type: DocFieldType.multiline,
          defaultValue:
              'Öğrenci hatasının farkına vardığını, sınıf ve okul kurallarına uyacağını ve arkadaşlarına karşı daha özenli davranacağını ifade etmiştir.',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Süreç Aşaması', '1. Aşama — Öğretmen Sözlü Uyarı ve Yapıcı Görüşme (Md. 54/1)'),
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Görüşme Zamanı', _str(a, 'date')),
        MapEntry(
          'Görüşmeyi Yapan Öğretmen',
          _str(a, 'teacher', ctx.currentUser?.fullName ?? 'Ders / Sınıf Rehber Öğretmeni'),
        ),
      ],
      composeBody: (a, ctx) => '''
ÖĞRETMEN SÖZLÜ UYARI VE YAPICI GÖRÜŞME TUTANAĞI

MEB Okul Öncesi Eğitim ve İlköğretim Kurumları Yönetmeliğinin 54 üncü maddesi ile Ortaöğretim Kurumları Yönetmeliğinin 163 üncü maddesinde yer alan "olumsuz davranışların yaptırım uygulanmadan önce pedagojik yöntemlerle düzeltilmesi" ilkesi doğrultusunda; okulumuz ${_str(a, 'targetClass')} şubesi öğrencisi ${_str(a, 'student')} ile ${_str(a, 'date')} tarihinde birebir yapıcı görüşme gerçekleştirilmiştir.

1. GÖZLEMLENEN VE GÖRÜŞMEYE KONU OLAN DAVRANIŞLAR:
${_numberedLines(_list(a, 'observedBehaviors'))}

2. UYGULANAN PEDAGOJİK REHBERLİK VE SÖZLÜ UYARI ADIMLARI:
${_numberedLines(_list(a, 'pedagogicalSteps'))}

3. ÖĞRENCİNİN DEĞERLENDİRMESİ VE SONUÇ:
${_str(a, 'studentNote')}

İşbu tutanak, öğrencinin davranış gelişimini izlemek ve mevzuatta öngörülen aşamalı rehberlik sürecini belgelendirmek amacıyla düzenlenerek sınıf rehberlik dosyasına konulmuştur.''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(a, 'teacher', ctx.currentUser?.fullName ?? 'Öğretmen'),
          title: 'Görüşmeyi Yapan Öğretmen',
        ),
        if (ctx.counselors.isNotEmpty)
          DocSigner(
            name: ctx.counselors.first.fullName,
            title: 'Bilgi Edinen Rehber Öğretmen / PDR',
          ),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // ÖDDK-02: MEB EK-9 ÖĞRENCİ OLUMLU DAVRANIŞ SÖZLEŞMESİ (MD. 54/2)
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'oddk_02_ek9_ogrenci_sozlesmesi',
      code: 'ÖDDK-02',
      categoryId: 'oddk_disiplin_surec_paketi',
      title:
          '2. Adım: MEB EK-9 Öğrenci Sözleşmesi (Olumlu Davranış Geliştirme Taahhüdü)',
      subtitle:
          'Sözlü uyarıya rağmen devam eden davranışlarda öğrenci ve öğretmen arasında imzalanan resmi EK-9 sözleşmesi',
      legalBasis:
          'MEB Okul Öncesi Eğitim ve İlköğretim Kurumları Yönetmeliği Md. 54/2 ve EK-9',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.handshake_rounded,
      questions: [
        const DocQuestionField(
          key: 'targetClass',
          label: 'Öğrencinin Şubesi',
          type: DocFieldType.classSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'student',
          label: 'Sözleşme İmzalayan Öğrenci',
          type: DocFieldType.studentSelect,
          required: true,
        ),
        DocQuestionField(
          key: 'date',
          label: 'Sözleşme Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'followUpPeriod',
          label: 'Davranış İzleme ve Değerlendirme Süresi',
          type: DocFieldType.dropdown,
          options: [
            '2 Hafta (14 Gün) İzleme Süresi',
            '3 Hafta (21 Gün) İzleme Süresi',
            '1 Ay (30 Gün) İzleme Süresi',
            'Dönem Sonuna Kadar İzleme Süresi',
          ],
          defaultValue: '3 Hafta (21 Gün) İzleme Süresi',
        ),
        const DocQuestionField(
          key: 'teacher',
          label: 'Sözleşmeyi Yapan Sınıf / Ders Öğretmeni',
          type: DocFieldType.staffSelect,
        ),
        const DocQuestionField(
          key: 'behaviorsToStop',
          label: 'Öğrencinin Tekrarlamamayı Kabul Ettiği Olumsuz Davranışlar',
          type: DocFieldType.multiCheck,
          options: [
            'Dersin akışını ve sınıfın öğrenme ortamını bozacak şekilde izinsiz konuşmak veya hareket etmek',
            'Arkadaşlarına sözlü sataşmada bulunmak, alay etmek, lakap takmak veya kırıcı davranmak',
            'Öfkelendiğinde itme, vurma, eşya fırlatma gibi fiziksel tepkiler göstermek',
            'Öğretmenlerine ve okul çalışanlarına karşı saygı sınırlarını aşan ifadeler kullanmak',
            'Okul bina, sıra, masa, akıllı tahta ve ortak kullanım eşyalarına zarar vermek',
            'Derslere geç girmek, izinsiz sınıftan çıkmak veya okul kurallarını ihlal etmek',
            'Ders araç-gereçlerini getirmemek ve verilen akademik görevleri ihmal etmek',
            'Okula cep telefonu/yasaklı eşya getirmek veya bilişim kurallarını ihlal etmek',
            'Arkadaşlarının eşyalarını izinsiz kullanmak veya saklamak',
            'Kılık-kıyafet, sıra düzeni ve temizlik kurallarına uymamak',
          ],
          defaultValue: [
            'Dersin akışını ve sınıfın öğrenme ortamını bozacak şekilde izinsiz konuşmak veya hareket etmek',
            'Arkadaşlarına sözlü sataşmada bulunmak, alay etmek, lakap takmak veya kırıcı davranmak',
          ],
        ),
        const DocQuestionField(
          key: 'positiveCommitments',
          label: 'Öğrencinin Sergileyeceği Olumlu Davranış Maddeleri (EK-9 Taahhütleri)',
          type: DocFieldType.multiCheck,
          options: [
            'Ders zili çaldığında zamanında sınıfta hazır bulunacağım ve ders araç-gereçlerimi tam getireceğim.',
            'Sınıfta söz hakkı alarak konuşacağım, öğretmenimi ve arkadaşlarımı saygıyla dinleyeceğim.',
            'Arkadaşlarımla yaşadığım anlaşmazlıklarda şiddet veya kırıcı söz yerine yapıcı iletişimi ve öğretmen desteğini seçeceğim.',
            'Kırdığım veya zarar verdiğim bir durum olduğunda özür dileyerek telafi etme sorumluluğunu üstleneceğim.',
            'Okul eşyalarını, sıraları ve etkileşimli tahtayı kendi eşyam gibi koruyup temiz tutacağım.',
            'Teneffüslerde koridor ve bahçe güvenlik kurallarına uyarak kimseye zarar vermeden hareket edeceğim.',
            'Verilen ödev ve sınıf içi görevlerimi zamanında yapmaya özen göstereceğim.',
            'Okul Rehberlik (PDR) Servisi ile planlanan bireysel görüşmelere düzenli katılacağım.',
            'Okul kıyafeti ve genel görünüm kurallarına her gün özen göstereceğim.',
            'Sosyal kulüp veya sınıf içi olumlu sorumluluk görevlerimi aktif şekilde yerine getireceğim.',
          ],
          defaultValue: [
            'Ders zili çaldığında zamanında sınıfta hazır bulunacağım ve ders araç-gereçlerimi tam getireceğim.',
            'Sınıfta söz hakkı alarak konuşacağım, öğretmenimi ve arkadaşlarımı saygıyla dinleyeceğim.',
            'Arkadaşlarımla yaşadığım anlaşmazlıklarda şiddet veya kırıcı söz yerine yapıcı iletişimi ve öğretmen desteğini seçeceğim.',
            'Okul eşyalarını, sıraları ve etkileşimli tahtayı kendi eşyam gibi koruyup temiz tutacağım.',
            'Okul Rehberlik (PDR) Servisi ile planlanan bireysel görüşmelere düzenli katılacağım.',
          ],
        ),
        const DocQuestionField(
          key: 'teacherSupport',
          label: 'Öğretmen ve Okul Rehberlik Servisinin Sağlayacağı Destekler',
          type: DocFieldType.multiCheck,
          options: [
            'Öğrencinin olumlu çabaları ve kurallara uyumu fark edilerek düzenli geri bildirim ve takdirle desteklenecektir.',
            'Akademik veya sosyal güçlük yaşadığında öğretmen ve PDR servisi tarafından rehberlik desteği sunulacaktır.',
            'Sınıf içi oturma düzeni ve görev paylaşımında öğrencinin kendini olumlu ifade edebileceği ortam sağlanacaktır.',
            'Belirlenen izleme süresi sonunda sözleşme hedefleri öğrenci ile birlikte değerlendirilecektir.',
          ],
          defaultValue: [
            'Öğrencinin olumlu çabaları ve kurallara uyumu fark edilerek düzenli geri bildirim ve takdirle desteklenecektir.',
            'Akademik veya sosyal güçlük yaşadığında öğretmen ve PDR servisi tarafından rehberlik desteği sunulacaktır.',
            'Belirlenen izleme süresi sonunda sözleşme hedefleri öğrenci ile birlikte değerlendirilecektir.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Belge Türü', 'MEB EK-9 Öğrenci Sözleşmesi (Md. 54/2 — 2. Aşama)'),
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Sözleşme / İzleme Süresi', '${_str(a, "date", _today())} — ${_str(a, "followUpPeriod")}'),
        MapEntry(
          'Rehberlik Eden Öğretmen',
          _str(a, 'teacher', ctx.currentUser?.fullName ?? 'Sınıf / Ders Öğretmeni'),
        ),
      ],
      composeBody: (a, ctx) => '''
ÖĞRENCİ OLUMLU DAVRANIŞ GELİŞTİRME SÖZLEŞMESİ (EK-9)

Ben ${ctx.schoolName} ${_str(a, 'targetClass')} sınıfı öğrencisi ${_str(a, 'student')}; daha önce öğretmenimle yaptığımız yapıcı görüşme doğrultusunda okul ortamında benden beklenen sorumlulukların farkındayım. Kendimin ve arkadaşlarımın güvenli, huzurlu ve verimli bir eğitim ortamında bulunması için aşağıdaki kararları kendi isteğimle kabul ediyorum:

A) KAÇINACAĞIM VE TEKRARLAMAYACAĞIM DAVRANIŞLAR:
${_numberedLines(_list(a, 'behaviorsToStop'))}

B) UYGULAYACAĞIM OLUMLU DAVRANIŞ SÖZLERİM:
${_numberedLines(_list(a, 'positiveCommitments'))}

C) ÖĞRETMEN VE OKUL REHBERLİK DESTEĞİ:
${_numberedLines(_list(a, 'teacherSupport'))}

SONUÇ VE BİLGİLENDİRME:
İşbu sözleşme ${_str(a, 'followUpPeriod')} boyunca birlikte izlenecektir. Sözleşme şartlarına uyulmaması ve olumsuz davranışların sürdürülmesi halinde MEB İlköğretim Kurumları Yönetmeliği Md. 54/3 uyarınca velimin okula davet edileceğini ve devamında dosyanın Öğrenci Davranışlarını Değerlendirme Kuruluna (ÖDDK) sevk edilebileceğini biliyor ve kabul ediyorum.''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(a, 'student', 'Öğrenci'),
          title: 'Sözleşmeyi Kabul Eden Öğrenci',
        ),
        DocSigner(
          name: _str(a, 'teacher', ctx.currentUser?.fullName ?? 'Öğretmen'),
          title: 'Sınıf / Ders Öğretmeni',
        ),
        if (ctx.counselors.isNotEmpty)
          DocSigner(
            name: ctx.counselors.first.fullName,
            title: 'Okul Rehber Öğretmeni / PDR',
          ),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // ÖDDK-03: SÖZLEŞME SONRASI VELİ OKULA DAVET & GÖRÜŞME / GELMEME TUTANAĞI
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'oddk_03_veli_onlem_gorusme_gelmeme_tutanagi',
      code: 'ÖDDK-03',
      categoryId: 'oddk_disiplin_surec_paketi',
      title:
          '3. Adım: Sözleşme Sonrası Veli Önlem Görüşmesi veya Veli Gelmeme Tutanağı (Md. 54/3)',
      subtitle:
          'ÖDDK sevk öncesi son zorunlu adım: Veli + İdare + Rehber Öğretmen görüşmesi ya da davete icabet etmeme tutanağı',
      legalBasis:
          'MEB Okul Öncesi Eğitim ve İlköğretim Kurumları Yönetmeliği Md. 54/3',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.family_restroom_rounded,
      questions: [
        const DocQuestionField(
          key: 'recordMode',
          label: 'Tutanak Durumu (Veli Katılım Durumuna Göre Seçiniz)',
          type: DocFieldType.dropdown,
          options: [
            '1) Veli Görüşmeye Katıldı — Veli, Okul Yönetimi ve Rehber Öğretmen İş Birliği Tutanağı',
            '2) Veli Davete İcabet Etmedi — Resmi Veli Görüşmeye Gelmeme Tespit Tutanağı (Md. 54/3)',
          ],
          defaultValue:
              '1) Veli Görüşmeye Katıldı — Veli, Okul Yönetimi ve Rehber Öğretmen İş Birliği Tutanağı',
        ),
        const DocQuestionField(
          key: 'targetClass',
          label: 'Öğrencinin Şubesi',
          type: DocFieldType.classSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'student',
          label: 'Öğrenci Seçimi',
          type: DocFieldType.studentSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'parentName',
          label: 'Veli Adı Soyadı ve İletişim Bilgisi',
          type: DocFieldType.text,
          hint: 'Örn: Mehmet KAYA (Babası) — 05xx xxx xx xx',
        ),
        DocQuestionField(
          key: 'date',
          label: 'Randevu / Görüşme Tarihi ve Saati',
          type: DocFieldType.text,
          defaultValue: '${_today()} - 14:00',
        ),
        const DocQuestionField(
          key: 'inviteChannel',
          label: 'Veliye Yapılan Davet Yöntemi ve Tarihi',
          type: DocFieldType.text,
          defaultValue:
              'Telefon görüşmesi, SMS ve yazılı davet pusulası ile önceden bildirilmiştir.',
        ),
        const DocQuestionField(
          key: 'decisions',
          label: 'Görüşmede Alınan Önlemler / Tespit Maddeleri',
          type: DocFieldType.multiCheck,
          options: [
            'Öğrenci ile daha önce yapılan sözlü uyarı ve imzalanan EK-9 Öğrenci Sözleşmesi süreci veliye ayrıntılı olarak aktarıldı.',
            'Sözleşmeye rağmen devam eden olumsuz davranışların öğrencinin akademik başarısı ve akran ilişkilerine etkisi değerlendirildi.',
            'Aile içi iletişim, sınır koyma, ekran/telefon yönetimi ve günlük çalışma düzeni konusunda veli bilgilendirildi.',
            'Öğrencinin Okul Rehberlik (PDR) Servisi ile düzenli görüşmelere devam etmesi ve velinin evde günlük davranış takibi yapması kararlaştırıldı.',
            'Gerek görülmesi halinde RAM / çocuk-ergen ruh sağlığı uzman desteği alınması yönünde veliye rehberlik edildi.',
            'Olumlu davranış değişikliği sağlanamaması veya yeni bir disiplin ihlali yaşanması halinde dosyanın Yönetmelik Md. 54/4 uyarınca ÖDDK / Disiplin Kuruluna sevk edileceği veliye açıkça bildirildi.',
            'Veliye resmi çağrı yapılmasına rağmen belirtilen tarih ve saatte okula gelmediği ve geçerli mazeret bildirmediği tutanakla tespit edildi.',
            'Velinin görüşmeye katılmaması nedeniyle mevzuat gereği süreç aksatılmaksızın dosyanın bir üst aşamaya (ÖDDK değerlendirmesine) taşınabileceği kayıt altına alındı.',
          ],
          defaultValue: [
            'Öğrenci ile daha önce yapılan sözlü uyarı ve imzalanan EK-9 Öğrenci Sözleşmesi süreci veliye ayrıntılı olarak aktarıldı.',
            'Sözleşmeye rağmen devam eden olumsuz davranışların öğrencinin akademik başarısı ve akran ilişkilerine etkisi değerlendirildi.',
            'Öğrencinin Okul Rehberlik (PDR) Servisi ile düzenli görüşmelere devam etmesi ve velinin evde günlük davranış takibi yapması kararlaştırıldı.',
            'Olumlu davranış değişikliği sağlanamaması veya yeni bir disiplin ihlali yaşanması halinde dosyanın Yönetmelik Md. 54/4 uyarınca ÖDDK / Disiplin Kuruluna sevk edileceği veliye açıkça bildirildi.',
          ],
        ),
        const DocQuestionField(
          key: 'staffParticipants',
          label: 'Görüşmede Hazır Bulunan Yönetici, Sınıf Rehber ve PDR Öğretmenleri',
          type: DocFieldType.multiStaffSelect,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Süreç Aşaması', '3. Aşama — Veli Davet ve Önlem Görüşmesi (Md. 54/3)'),
        MapEntry('Tutanak Türü', _str(a, 'recordMode')),
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Veli / Davet Bilgisi', '${_str(a, "parentName", "Öğrenci Velisi")} — ${_str(a, "inviteChannel")}'),
        MapEntry('Tarih / Saat', _str(a, 'date')),
      ],
      composeBody: (a, ctx) {
        final mode = _str(a, 'recordMode');
        final came = mode.startsWith('1');
        return '''
${came ? 'SÖZLEŞME SONRASI VELİ - OKUL YÖNETİMİ - REHBERLİK GÖRÜŞME TUTANAĞI' : 'VELİ DAVETE İCABET ETMEME (GÖRÜŞMEYE GELMEME) TESPİT TUTANAĞI'}

MEB Okul Öncesi Eğitim ve İlköğretim Kurumları Yönetmeliğinin 54 üncü maddesinin üçüncü fıkrası uyarınca; sözlü uyarı ve EK-9 Öğrenci Sözleşmesi uygulamalarına rağmen olumlu davranış değişikliği yeterince sağlanamayan ${_str(a, 'targetClass')} şubesi öğrencisi ${_str(a, 'student')}'in velisi (${_str(a, 'parentName', 'Öğrenci Velisi')}), "${_str(a, 'inviteChannel')}" yoluyla ${_str(a, 'date')} tarihinde okulumuza davet edilmiştir.

${came ? 'YAPILAN GÖRÜŞME VE KARARLAŞTIRILAN İŞ BİRLİĞİ TEDBİRLERİ:' : 'KATILIM TESPİTİ VE MEVZUAT KAYDI:'}
${_numberedLines(_list(a, 'decisions'))}

İşbu tutanak Yönetmeliğin 54 üncü maddesi gereğince yürütülen zorunlu önleyici adımları tevsik etmek üzere düzenlenerek imza altına alınmıştır.''';
      },
      buildSigners: (a, ctx) {
        final came = _str(a, 'recordMode').startsWith('1');
        final staff = _list(a, 'staffParticipants');
        return [
          if (came)
            DocSigner(
              name: _str(a, 'parentName', 'Öğrenci Velisi').split('(').first.trim(),
              title: 'Görüşmeye Katılan Öğrenci Velisi',
            ),
          for (final s in staff.take(3))
            DocSigner(name: s, title: 'Katılımcı Öğretmen / PDR'),
          DocSigner(
            name: ctx.vicePrincipals.isNotEmpty
                ? ctx.vicePrincipals.first.fullName
                : ctx.principalName,
            title: 'Okul Yönetimi / Müdür Yrd.',
            isApproval: true,
          ),
        ];
      },
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // ÖDDK-04: AYRINTILI OLAY TESPİT, DELİL VE KAMERA İNCELEME TUTANAĞI
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'oddk_04_ayrintili_olay_delil_kamera_tutanagi',
      code: 'ÖDDK-04',
      categoryId: 'oddk_disiplin_surec_paketi',
      title:
          '4. Adım: Ayrıntılı Olay Tespit, Maddi Delil ve Güvenlik Kamerası İnceleme Tutanağı',
      subtitle:
          'Disiplin/ÖDDK soruşturmasına esas teşkil eden olay yeri, saat aralığı, kamera kaydı ve hasar/delil tespit tutanağı',
      legalBasis:
          'MEB İlköğretim Yönetmeliği Md. 55–57 & Ortaöğretim Yönetmeliği Md. 164–171',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.videocam_rounded,
      questions: [
        const DocQuestionField(
          key: 'targetClass',
          label: 'Şube Seçimi',
          type: DocFieldType.classSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'students',
          label: 'Olaya Karışan Öğrenci(ler)',
          type: DocFieldType.multiStudentSelect,
          required: true,
        ),
        DocQuestionField(
          key: 'date',
          label: 'Olay Tarihi ve Tam Saat Aralığı',
          type: DocFieldType.text,
          defaultValue: '${_today()} (Saat ${_nowTime()} sıraları)',
        ),
        const DocQuestionField(
          key: 'location',
          label: 'Olayın Meydana Geldiği Tam Mahal / Kamera Açısı',
          type: DocFieldType.text,
          defaultValue: '2. Kat Koridoru — Kamera No: 04 Görüş Alanı / Sınıf Önü',
        ),
        const DocQuestionField(
          key: 'incidentFindings',
          label: 'Mahallinde Yapılan Somut Tespitler ve Alınan İlk Tedbirler',
          type: DocFieldType.multiCheck,
          options: [
            'Olay mahalline derhal müdahale edilerek taraflar birbirinden ayrılmış ve ortam güvenliği sağlanmıştır.',
            'Yaralanma / darp şüphesi açısından öğrencilerin fiziki kontrolü yapılmış, gerekli ilk yardım/sağlık tedbiri uygulanmıştır.',
            'Olayı doğrudan gören nöbetçi öğretmen, ders öğretmeni ve çevredeki görgü tanığı öğrenciler belirlenmiştir.',
            'Koridor/bahçe güvenlik kamerasının ilgili tarih ve saat aralığındaki görüntüleri idarece incelenerek yedeklenmiştir.',
            'Okul binası, sıra, kapı, cam veya etkileşimli tahtada oluşan maddi hasar fotoğraflanarak kayıt altına alınmıştır.',
            'Olayda kullanılan veya kurallara aykırı bulundurulan materyal/cihaz tutanakla muhafaza altına alınmıştır.',
            'Sosyal medya / mesajlaşma grubu üzerinden gerçekleşen siber zorbalık veya paylaşım ekran bulguları dosyaya eklenmiştir.',
            'Olaya karışan ve zarar gören öğrencilerin velilerine telefonla ilk bilgilendirme yapılmıştır.',
            'Öğrenciler sakinleşmeleri ve pedagojik destek almaları amacıyla Okul Rehberlik (PDR) Servisine yönlendirilmiştir.',
            'Tutanak ve ekleri ÖDDK / Öğrenci Ödül ve Disiplin Kurulu incelemesine sunulmak üzere Okul Müdürlüğüne teslim edilmiştir.',
          ],
          defaultValue: [
            'Olay mahalline derhal müdahale edilerek taraflar birbirinden ayrılmış ve ortam güvenliği sağlanmıştır.',
            'Olayı doğrudan gören nöbetçi öğretmen, ders öğretmeni ve çevredeki görgü tanığı öğrenciler belirlenmiştir.',
            'Olaya karışan ve zarar gören öğrencilerin velilerine telefonla ilk bilgilendirme yapılmıştır.',
            'Tutanak ve ekleri ÖDDK / Öğrenci Ödül ve Disiplin Kurulu incelemesine sunulmak üzere Okul Müdürlüğüne teslim edilmiştir.',
          ],
        ),
        const DocQuestionField(
          key: 'narrative',
          label: 'Olayın Kronolojik Oluş Şekli (Kim, Nerede, Ne Zaman, Nasıl?)',
          type: DocFieldType.multiline,
          defaultValue:
              'Belirtilen tarih ve saatte yukarıda kimlik bilgileri yer alan öğrenciler arasında yaşanan olay görevli öğretmen/idarecilerce mahallinde tespit edilmiş; maddi gerçeğin hiçbir tereddüde yer bırakmayacak şekilde ortaya konulması amacıyla ayrıntılarıyla kayıt altına alınmıştır.',
          required: true,
        ),
        const DocQuestionField(
          key: 'reporters',
          label: 'Tutanağı Düzenleyen İdareci / Nöbetçi / Ders Öğretmenleri (En Az 2 Görevli Önerilir)',
          type: DocFieldType.multiStaffSelect,
          required: true,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Belge Niteliği', 'Ayrıntılı Olay, Delil ve Kamera İnceleme Tutanağı'),
        MapEntry('Şube ve Öğrenci(ler)', '${_str(a, "targetClass")} — ${_list(a, "students").join(", ")}'),
        MapEntry('Olay Tarih / Saat', _str(a, 'date')),
        MapEntry('Olay Yeri / Kamera', _str(a, 'location')),
      ],
      composeBody: (a, ctx) => '''
AYRINTILI OLAY TESPİT, DELİL VE GÜVENLİK KAMERASI İNCELEME TUTANAĞI

1. OLAYIN KRONOLOJİK GELİŞİMİ:
${_str(a, 'narrative')}

2. MAHALLİNDE YAPILAN TESPİTLER, DELİLLER VE İLK MÜDAHALE İŞLEMLERİ:
${_numberedLines(_list(a, 'incidentFindings'))}

İşbu tutanak, olayın hemen ardından maddi vakıayı objektif olarak belgelendirmek üzere iki nüsha halinde düzenlenmiş ve aşağıda imzası bulunan görevlilerce imza altına alınarak Okul Müdürlüğüne teslim edilmiştir.''',
      buildSigners: (a, ctx) => [
        for (final r in _list(a, 'reporters').take(4))
          DocSigner(name: r, title: 'Tutanak Düzenleyen Görevli'),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // ÖDDK-05: SINIF REHBER ÖĞRETMENİ ÖDDK / DİSİPLİN KURULUNA SEVK RAPORU
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'oddk_05_ogretmen_oddk_sevk_raporu',
      code: 'ÖDDK-05',
      categoryId: 'oddk_disiplin_surec_paketi',
      title:
          '5. Adım: Sınıf / Ders Öğretmeni ÖDDK / Disiplin Kuruluna Resmi Sevk Raporu (Md. 54/4)',
      subtitle:
          'Önceki sözlü uyarı, sözleşme ve veli görüşme belgeleriyle birlikte öğrencinin kurula sevk üst yazısı',
      legalBasis:
          'MEB İlköğretim Kurumları Yönetmeliği Md. 54/4 & Ortaöğretim Kurumları Yönetmeliği Md. 169',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.officialLetter,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.send_time_extension_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Sevk Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'targetClass',
          label: 'Öğrencinin Şubesi',
          type: DocFieldType.classSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'student',
          label: 'Sevk Edilen Öğrenci',
          type: DocFieldType.studentSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'teacher',
          label: 'Sevk Raporunu Hazırlayan Sınıf Rehber / Ders Öğretmeni',
          type: DocFieldType.staffSelect,
        ),
        const DocQuestionField(
          key: 'completedPriorSteps',
          label: 'Sevk Öncesi Tamamlanan ve Ek\'te Sunulan İşlemler (Md. 54 Kontrolü)',
          type: DocFieldType.multiCheck,
          options: [
            'Öğrenci ile birebir sözlü uyarı ve yapıcı farkındalık görüşmesi yapılmıştır (ÖDDK-01 Tutanak Ekli).',
            'Öğrenci ile MEB EK-9 Olumlu Davranış Geliştirme Sözleşmesi imzalanmış ve izleme süresi tanınmıştır (ÖDDK-02 Ekli).',
            'Öğrenci velisi okula davet edilerek İdare ve PDR Servisi katılımıyla önlem görüşmesi yapılmış / gelmeme tutanağı tutulmuştur (ÖDDK-03 Ekli).',
            'Sınıf içi oturma düzeni değişikliği, akran desteği ve olumlu sorumluluk verme çalışmaları uygulanmıştır.',
            'Okul Rehberlik ve Psikolojik Danışma Servisine yönlendirme yapılarak bireysel görüşme desteği sağlanmıştır.',
            'Doğrudan yaptırım gerektiren ağır disiplin vakıası nedeniyle olay tespit tutanağı ve deliller eksiksiz eklenmiştir (ÖDDK-04 Ekli).',
          ],
          defaultValue: [
            'Öğrenci ile birebir sözlü uyarı ve yapıcı farkındalık görüşmesi yapılmıştır (ÖDDK-01 Tutanak Ekli).',
            'Öğrenci ile MEB EK-9 Olumlu Davranış Geliştirme Sözleşmesi imzalanmış ve izleme süresi tanınmıştır (ÖDDK-02 Ekli).',
            'Öğrenci velisi okula davet edilerek İdare ve PDR Servisi katılımıyla önlem görüşmesi yapılmış / gelmeme tutanağı tutulmuştur (ÖDDK-03 Ekli).',
            'Doğrudan yaptırım gerektiren ağır disiplin vakıası nedeniyle olay tespit tutanağı ve deliller eksiksiz eklenmiştir (ÖDDK-04 Ekli).',
          ],
        ),
        const DocQuestionField(
          key: 'referralReason',
          label: 'Sevk Gerekçesi ve Son Yaşanan Davranış / Olay Özeti',
          type: DocFieldType.multiline,
          defaultValue:
              'Yukarıda belirtilen tüm koruyucu ve önleyici pedagojik çalışmalara rağmen öğrencinin sınıf/okul düzenini bozan ve akran güvenliğini olumsuz etkileyen davranışlarını sürdürdüğü tespit edilmiştir.',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Konu', 'Öğrencinin ÖDDK / Öğrenci Ödül ve Disiplin Kuruluna Sevki'),
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Sevk Tarihi', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
${ctx.schoolName.toUpperCase()} MÜDÜRLÜĞÜNE

Okulumuz ${_str(a, 'targetClass')} şubesi öğrencisi ${_str(a, 'student')} hakkında yürütülen sınıf içi rehberlik, davranış izleme ve tespit çalışmaları aşağıda sunulmuştur:

1. SEVK ÖNCESİ TAMAMLANAN AŞAMALAR VE EKLİ BELGELER:
${_numberedLines(_list(a, 'completedPriorSteps'))}

2. SEVK GEREKÇESİ VE AÇIKLAMA:
${_str(a, 'referralReason')}

MEB Okul Öncesi Eğitim ve İlköğretim Kurumları Yönetmeliğinin 54 ve 57 nci maddeleri / Ortaöğretim Kurumları Yönetmeliğinin 169 uncu maddesi hükümleri uyarınca durumun Öğrenci Davranışlarını Değerlendirme Kurulu (Ödül ve Disiplin Kurulu) tarafından incelenerek gerekli kararın alınması hususunda gereğini arz ederim.''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(a, 'teacher', ctx.currentUser?.fullName ?? 'Sınıf Rehber Öğretmeni'),
          title: 'Sevk Eden Sınıf / Ders Öğretmeni',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'HAVALE / İNCELENSİN'),
          isApproval: true,
        ),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // ÖDDK-06: OKUL MÜDÜRLÜĞÜ İNCELEME BAŞLATMA VE KURULA HAVALE ONAYI
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'oddk_06_mudurluk_inceleme_ve_kurula_havale',
      code: 'ÖDDK-06',
      categoryId: 'oddk_disiplin_surec_paketi',
      title:
          '6. Adım: Okul Müdürlüğü Disiplin İnceleme Başlatma ve ÖDDK / Kurula Havale Yazısı',
      subtitle:
          'Okul müdürünün olay dosyasını resmi sayı ile ÖDDK / Öğrenci Ödül ve Disiplin Kurulu Başkanlığına sevki ve PDR raporu istemi',
      legalBasis:
          'MEB İlköğretim Yönetmeliği Md. 57 & Ortaöğretim Yönetmeliği Md. 169–171',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.officialLetter,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.approval_rounded,
      questions: [
        const DocQuestionField(
          key: 'fileNo',
          label: 'Soruşturma / İnceleme Dosya Numarası',
          type: DocFieldType.text,
          defaultValue: '2026 / ÖDDK-01',
        ),
        DocQuestionField(
          key: 'date',
          label: 'Havale Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'boardName',
          label: 'Havale Edilen Kurul Başkanlığı',
          type: DocFieldType.dropdown,
          options: [
            'ÖĞRENCİ DAVRANIŞLARINI DEĞERLENDİRME KURULU (ÖDDK) BAŞKANLIĞINA',
            'OKUL ÖĞRENCİ ÖDÜL VE DİSİPLİN KURULU BAŞKANLIĞINA',
          ],
          defaultValue:
              'ÖĞRENCİ DAVRANIŞLARINI DEĞERLENDİRME KURULU (ÖDDK) BAŞKANLIĞINA',
        ),
        const DocQuestionField(
          key: 'targetClass',
          label: 'Öğrencinin Şubesi',
          type: DocFieldType.classSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'students',
          label: 'Hakkında İnceleme Başlatılan Öğrenci(ler)',
          type: DocFieldType.multiStudentSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'boardChair',
          label: 'Kurul Başkanı Müdür Başyardımcısı / Müdür Yardımcısı',
          type: DocFieldType.staffSelect,
        ),
        const DocQuestionField(
          key: 'instructions',
          label: 'Kurul Başkanlığınca Yürütülecek Yasal İşlem Talimatları',
          type: DocFieldType.multiCheck,
          options: [
            'Dosyanın Kurul gündemine alınarak mağdur ve görgü tanığı öğrencilerin pedagojik esaslara uygun yazılı beyanlarının alınması,',
            'Hakkında inceleme yapılan öğrenci(ler)e iddiaların açıkça bildirilerek yazılı (veya tutanaklı sözlü) savunma hakkının kullandırılması,',
            'Öğrenci velisinin süreç hakkında yazılı olarak bilgilendirilmesi ve görüşmeye davet edilmesi,',
            'Karar öncesinde Okul Rehberlik ve Psikolojik Danışma (PDR) Servisinden öğrenciye ilişkin yazılı vaka ve kanaat raporunun temin edilmesi,',
            'Varsa maddi zararın tespiti, özür ve akran uzlaşma olanaklarının değerlendirilmesi,',
            'İncelemenin mevzuatta öngörülen yasal süre içerisinde tamamlanarak gerekçeli kurul kararının Müdürlük Makamına sunulması,',
          ],
          defaultValue: [
            'Dosyanın Kurul gündemine alınarak mağdur ve görgü tanığı öğrencilerin pedagojik esaslara uygun yazılı beyanlarının alınması,',
            'Hakkında inceleme yapılan öğrenci(ler)e iddiaların açıkça bildirilerek yazılı (veya tutanaklı sözlü) savunma hakkının kullandırılması,',
            'Öğrenci velisinin süreç hakkında yazılı olarak bilgilendirilmesi ve görüşmeye davet edilmesi,',
            'Karar öncesinde Okul Rehberlik ve Psikolojik Danışma (PDR) Servisinden öğrenciye ilişkin yazılı vaka ve kanaat raporunun temin edilmesi,',
            'İncelemenin mevzuatta öngörülen yasal süre içerisinde tamamlanarak gerekçeli kurul kararının Müdürlük Makamına sunulması,',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Dosya No / Tarih', '${_str(a, "fileNo")} — ${_str(a, "date", _today())}'),
        MapEntry('Havale Edilen Birim', _str(a, 'boardName')),
        MapEntry('İlgili Öğrenci(ler)', '${_list(a, "students").join(", ")} (${_str(a, "targetClass")})'),
      ],
      composeBody: (a, ctx) => '''
${_str(a, 'boardName')}

İlgi: ${_str(a, 'date', _today())} tarihli olay tespit tutanağı ve sınıf/ders öğretmeni sevk raporu.

Okulumuz ${_str(a, 'targetClass')} şubesi öğrencisi/öğrencileri (${_list(a, 'students').join(', ')}) hakkında ilgi tutanak ve ekleriyle Müdürlüğümüze intikal eden davranış/disiplin dosyasının "${_str(a, 'fileNo')}" dosya numarası üzerinden incelenmesi uygun görülmüştür.

Kurul Başkanlığınızca ilgili MEB Kurum Yönetmeliği hükümleri doğrultusunda;
${_numberedLines(_list(a, 'instructions'))}

hususlarında gereğini rica ederim.''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(
            a,
            'boardChair',
            ctx.vicePrincipals.isNotEmpty
                ? ctx.vicePrincipals.first.fullName
                : 'Kurul Başkanı',
          ),
          title: 'Dosyayı Teslim Alan Kurul Başkanı',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx),
          isApproval: true,
        ),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // ÖDDK-07: MAĞDUR / ZARAR GÖREN / ŞİKÂYETÇİ ÖĞRENCİ İFADE TUTANAĞI
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'oddk_07_magdur_sikayetci_ifade_tutanagi',
      code: 'ÖDDK-07',
      categoryId: 'oddk_disiplin_surec_paketi',
      title:
          '7. Adım: Mağdur / Zarar Gören / Şikâyetçi Öğrenci Pedagojik İfade ve Bilgi Alma Tutanağı',
      subtitle:
          'Olaydan etkilenen veya şikâyetçi olan öğrencinin pedagojik güvencelerle yazılı/sözlü anlatım ve talep tutanağı',
      legalBasis:
          'MEB İlköğretim Yönetmeliği Md. 57 & Ortaöğretim Yönetmeliği Md. 171',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.healing_rounded,
      questions: [
        const DocQuestionField(
          key: 'fileNo',
          label: 'İlgili Dosya No',
          type: DocFieldType.text,
          defaultValue: '2026 / ÖDDK-01',
        ),
        const DocQuestionField(
          key: 'targetClass',
          label: 'Beyanı Alınan Öğrencinin Şubesi',
          type: DocFieldType.classSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'student',
          label: 'Mağdur / Şikâyetçi Öğrenci Seçimi',
          type: DocFieldType.studentSelect,
          required: true,
        ),
        DocQuestionField(
          key: 'date',
          label: 'Beyan Tarihi ve Saati',
          type: DocFieldType.text,
          defaultValue: '${_today()} - ${_nowTime()}',
        ),
        const DocQuestionField(
          key: 'incidentTopic',
          label: 'Olayın Tarihi, Yeri ve Konusu',
          type: DocFieldType.text,
          defaultValue: 'Okul koridorunda / dersliğinde yaşanan akran anlaşmazlığı olayı',
          required: true,
        ),
        const DocQuestionField(
          key: 'safeguards',
          label: 'Uygulanan Pedagojik Güvenceler (Seçili Maddeler Tutanağa İşlenir)',
          type: DocFieldType.multiCheck,
          options: [
            'Öğrencinin yaşı ve duygusal durumu gözetilerek sakin, güvenli ve gizliliğe uygun bir görüşme ortamı sağlandı.',
            'Görüşme sırasında öğrencinin örselenmemesi için Rehber Öğretmen / Psikolojik Danışman (veya sınıf öğretmeni) hazır bulundu.',
            'Yönlendirici veya baskılayıcı sorulardan kaçınılarak öğrencinin olayı kendi cümleleriyle anlatmasına imkan tanındı.',
            'Öğrencinin okuldaki güvenlik algısını ve psikolojik iyi oluşunu destekleyici PDR görüşmesi planlandı.',
            'Öğrencinin akran uzlaşması veya zarar tazmini konusundaki görüşü ayrıca soruldu.',
          ],
          defaultValue: [
            'Öğrencinin yaşı ve duygusal durumu gözetilerek sakin, güvenli ve gizliliğe uygun bir görüşme ortamı sağlandı.',
            'Görüşme sırasında öğrencinin örselenmemesi için Rehber Öğretmen / Psikolojik Danışman (veya sınıf öğretmeni) hazır bulundu.',
            'Yönlendirici veya baskılayıcı sorulardan kaçınılarak öğrencinin olayı kendi cümleleriyle anlatmasına imkan tanındı.',
          ],
        ),
        const DocQuestionField(
          key: 'statement',
          label:
              'Mağdur / Şikâyetçi Öğrencinin Beyanı (Boş bırakılırsa el yazısı için noktalı satırlar basılır)',
          type: DocFieldType.multiline,
          hint:
              'Öğrencinin anlatımını yazabilir veya boş bırakıp çıktıda kendi el yazısıyla doldurmasını sağlayabilirsiniz...',
        ),
        const DocQuestionField(
          key: 'interviewer',
          label: 'Beyanı Alan Kurul Başkanı / Üyesi',
          type: DocFieldType.staffSelect,
        ),
        const DocQuestionField(
          key: 'observer',
          label: 'Hazır Bulunan Rehber Öğretmen / Gözlemci Öğretmen',
          type: DocFieldType.staffSelect,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Dosya No / Sıfat', '${_str(a, "fileNo")} — Mağdur / Zarar Gören Öğrenci Beyanı'),
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Görüşme Zamanı', _str(a, 'date')),
        MapEntry('Olay Konusu', _str(a, 'incidentTopic')),
      ],
      composeBody: (a, ctx) {
        final st = _str(a, 'statement');
        return '''
MAĞDUR / ZARAR GÖREN ÖĞRENCİ PEDAGOJİK BİLGİ VE BEYAN TUTANAĞI

1. GÖRÜŞME USULÜ VE PEDAGOJİK GÜVENCELER:
${_numberedLines(_list(a, 'safeguards'))}

2. YÖNELTİLEN AÇIK UÇLU SORU:
"${_str(a, 'incidentTopic')}" olayı öncesinde, olay sırasında ve sonrasında yaşananları, kimlerin orada bulunduğunu ve varsa gördüğün maddi/manevi zararı kendi cümlelerinle anlatır mısın?

3. ÖĞRENCİNİN BEYANI:
${st.isNotEmpty ? st : _blankLines(8)}

Yukarıdaki beyanımı hiçbir etki altında kalmadan kendi özgür irademle anlattım/yazdım; okudum ve doğruluğunu imzamla onaylarım.''';
      },
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(a, 'student', 'Öğrenci'),
          title: 'Beyan Sahibi Öğrenci',
        ),
        DocSigner(
          name: _str(
            a,
            'observer',
            ctx.counselors.isNotEmpty
                ? ctx.counselors.first.fullName
                : 'Gözlemci Öğretmen',
          ),
          title: 'Gözlemci Rehber / Sınıf Öğretmeni',
        ),
        DocSigner(
          name: _str(
            a,
            'interviewer',
            ctx.vicePrincipals.isNotEmpty
                ? ctx.vicePrincipals.first.fullName
                : 'Kurul Başkanı',
          ),
          title: 'Beyanı Alan Kurul Başkanı / Üyesi',
        ),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // ÖDDK-08: GÖRGÜ TANIĞI (ÖĞRENCİ / ÖĞRETMEN / PERSONEL) İFADE TUTANAĞI
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'oddk_08_gorgu_tanigi_ifade_tutanagi',
      code: 'ÖDDK-08',
      categoryId: 'oddk_disiplin_surec_paketi',
      title:
          '8. Adım: Görgü Tanığı (Öğrenci / Öğretmen / Personel) Bilgi ve İfade Alma Tutanağı',
      subtitle:
          'Olayı bizzat gören tanıkların diğer tanıklardan ayrı olarak alınan tarafsız görgü ve bilgi alma tutanağı',
      legalBasis:
          'MEB İlköğretim Yönetmeliği Md. 57 & Ortaöğretim Yönetmeliği Md. 171',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.visibility_rounded,
      questions: [
        const DocQuestionField(
          key: 'fileNo',
          label: 'İlgili Dosya No',
          type: DocFieldType.text,
          defaultValue: '2026 / ÖDDK-01',
        ),
        const DocQuestionField(
          key: 'witnessKind',
          label: 'Görgü Tanığının Sıfatı',
          type: DocFieldType.dropdown,
          options: [
            'Görgü Tanığı Öğrenci',
            'Görgü Tanığı Nöbetçi / Ders Öğretmeni',
            'Görgü Tanığı Okul Personeli / Servis Rehberi / Güvenlik Görevlisi',
          ],
          defaultValue: 'Görgü Tanığı Öğrenci',
        ),
        const DocQuestionField(
          key: 'targetClass',
          label: 'Tanık Öğrenci ise Şubesi (Personel ise boş bırakabilirsiniz)',
          type: DocFieldType.classSelect,
        ),
        const DocQuestionField(
          key: 'studentWitness',
          label: 'Tanık Öğrenci Seçimi (Öğrenci ise)',
          type: DocFieldType.studentSelect,
        ),
        const DocQuestionField(
          key: 'manualWitnessName',
          label: 'Tanık Öğretmen / Personel Adı ve Görevi (Öğrenci değilse yazınız)',
          type: DocFieldType.text,
          hint: 'Örn: Ahmet DEMİR — Nöbetçi Öğretmen',
        ),
        DocQuestionField(
          key: 'date',
          label: 'İfade / Bilgi Alma Tarihi ve Saati',
          type: DocFieldType.text,
          defaultValue: '${_today()} - ${_nowTime()}',
        ),
        const DocQuestionField(
          key: 'incidentTopic',
          label: 'Tanıklığa Konu Olay Tarihi, Saati ve Yeri',
          type: DocFieldType.text,
          defaultValue: 'Okul içinde meydana gelen disiplin incelemesi konusu olay',
          required: true,
        ),
        const DocQuestionField(
          key: 'witnessRules',
          label: 'Görgü Tanığı Bilgi Alma İlkeleri',
          type: DocFieldType.multiCheck,
          options: [
            'Görgü tanığı, olaya karışan taraflardan ve diğer tanıklardan tamamen ayrı bir ortamda birebir dinlendi.',
            'Yalnızca bizzat gördüğü ve duyduğu somut vakıaları, duyum veya tahminden ayırarak anlatması gerektiği hatırlatıldı.',
            'Tanığın kimlik ve beyan gizliliğinin akran baskısına karşı korunacağı kendisine bildirildi.',
            'Tanık öğrenci olduğu için görüşmede pedagojik dil ve rehberlik ilkeleri gözetildi.',
          ],
          defaultValue: [
            'Görgü tanığı, olaya karışan taraflardan ve diğer tanıklardan tamamen ayrı bir ortamda birebir dinlendi.',
            'Yalnızca bizzat gördüğü ve duyduğu somut vakıaları, duyum veya tahminden ayırarak anlatması gerektiği hatırlatıldı.',
            'Tanığın kimlik ve beyan gizliliğinin akran baskısına karşı korunacağı kendisine bildirildi.',
          ],
        ),
        const DocQuestionField(
          key: 'statement',
          label:
              'Görgü Tanığının İfadesi (Boş bırakılırsa el yazısı için noktalı alan oluşturulur)',
          type: DocFieldType.multiline,
          hint:
              'Tanığın bizzat gördüğü ve duyduğu hususları yazınız veya çıktı üzerinde el yazısıyla doldurtunuz...',
        ),
        const DocQuestionField(
          key: 'interviewer',
          label: 'Bilgi Alan Kurul Başkanı / Üyesi',
          type: DocFieldType.staffSelect,
        ),
      ],
      buildMetaRows: (a, ctx) {
        final witnessName = _str(a, 'manualWitnessName').isNotEmpty
            ? _str(a, 'manualWitnessName')
            : '${_str(a, "studentWitness")} (${_str(a, "targetClass")})';
        return [
          MapEntry('Dosya No / İşlem', '${_str(a, "fileNo")} — Görgü Tanığı Bilgi Alma Tutanağı'),
          MapEntry('Görgü Tanığı ve Sıfatı', '$witnessName — ${_str(a, "witnessKind")}'),
          MapEntry('Tarih ve Saat', _str(a, 'date')),
          MapEntry('İlgili Olay', _str(a, 'incidentTopic')),
        ];
      },
      composeBody: (a, ctx) {
        final st = _str(a, 'statement');
        return '''
GÖRGÜ TANIĞI BİLGİ VE İFADE ALMA TUTANAĞI

1. USUL VE GİZLİLİK ESASLARI:
${_numberedLines(_list(a, 'witnessRules'))}

2. GÖRGÜ TANIĞINA YÖNELTİLEN SORU:
"${_str(a, 'incidentTopic')}" olayı sırasında nerede bulunuyordunuz? Olayın nasıl başladığını, tarafların söz ve davranışlarını bizzat gördüğünüz ve duyduğunuz şekliyle doğru ve tarafsız olarak anlatınız.

3. GÖRGÜ TANIĞININ BEYANI:
${st.isNotEmpty ? st : _blankLines(8)}

Olayla ilgili bizzat gördüklerim ve duyduklarım yukarıda belirttiğim gibidir. Beyanımı okudum ve doğruluğunu imzamla tasdik ederim.''';
      },
      buildSigners: (a, ctx) {
        final witnessName = _str(a, 'manualWitnessName').isNotEmpty
            ? _str(a, 'manualWitnessName').split('—').first.trim()
            : _str(a, 'studentWitness', 'Görgü Tanığı');
        return [
          DocSigner(name: witnessName, title: _str(a, 'witnessKind')),
          DocSigner(
            name: _str(
              a,
              'interviewer',
              ctx.vicePrincipals.isNotEmpty
                  ? ctx.vicePrincipals.first.fullName
                  : 'Kurul Başkanı',
            ),
            title: 'İfadeyi Alan Kurul Başkanı / Üyesi',
          ),
        ];
      },
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // ÖDDK-09: HAKKINDA İNCELEME YAPILAN ÖĞRENCİ SAVUNMA TUTANAĞI
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'oddk_09_ogrenci_yazili_savunma_tutanagi',
      code: 'ÖDDK-09',
      categoryId: 'oddk_disiplin_surec_paketi',
      title:
          '9. Adım: Hakkında İnceleme Yapılan Öğrenciye İsnat Bildirimi ve Savunma Tutanağı',
      subtitle:
          'Savunma alınmadan yaptırım verilemeyeceği ilkesi gereği öğrenci yazılı savunma veya savunmadan imtina tutanağı',
      legalBasis:
          'MEB İlköğretim Yönetmeliği Md. 57/2 & Ortaöğretim Yönetmeliği Md. 171 (Savunma Hakkı)',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.gavel_rounded,
      questions: [
        const DocQuestionField(
          key: 'fileNo',
          label: 'Soruşturma / ÖDDK Dosya No',
          type: DocFieldType.text,
          defaultValue: '2026 / ÖDDK-01',
        ),
        const DocQuestionField(
          key: 'targetClass',
          label: 'Öğrencinin Şubesi',
          type: DocFieldType.classSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'student',
          label: 'Savunması Alınan Öğrenci',
          type: DocFieldType.studentSelect,
          required: true,
        ),
        DocQuestionField(
          key: 'date',
          label: 'Savunma Tarihi ve Saati',
          type: DocFieldType.text,
          defaultValue: '${_today()} - ${_nowTime()}',
        ),
        const DocQuestionField(
          key: 'allegation',
          label: 'Öğrenciye Açıkça Bildirilen İddia / Fiil ve Yönetmelik Kapsamı',
          type: DocFieldType.multiline,
          defaultValue:
              'Okul içi düzen ve kurallara aykırı olarak tutanakla tespit edilen davranış/olay hakkında MEB Kurum Yönetmeliği ilgili maddesi kapsamında inceleme yürütülmektedir.',
          required: true,
        ),
        const DocQuestionField(
          key: 'defenseGuarantees',
          label: 'Kullandırılan Yasal Savunma Hakları',
          type: DocFieldType.multiCheck,
          options: [
            'Öğrenciye hakkında yürütülen incelemenin konusu, tarihi, yeri ve isnat edilen davranış açık ve anlaşılır biçimde bildirildi.',
            'Hiçbir baskı veya yönlendirme olmaksızın kendisini yazılı veya sözlü savunma hakkına sahip olduğu hatırlatıldı.',
            'Varsa lehine olan durumları, mazeretini, tahrik unsurunu veya tanıklarını bildirebileceği açıklandı.',
            'Yaptığı davranıştan dolayı pişmanlık duyup duymadığı ve zararı/kırgınlığı telafi etme isteği soruldu.',
            'Savunma vermekten kaçınması halinde durumun tutanak altına alınarak mevcut delillerle karar verileceği hatırlatıldı.',
          ],
          defaultValue: [
            'Öğrenciye hakkında yürütülen incelemenin konusu, tarihi, yeri ve isnat edilen davranış açık ve anlaşılır biçimde bildirildi.',
            'Hiçbir baskı veya yönlendirme olmaksızın kendisini yazılı veya sözlü savunma hakkına sahip olduğu hatırlatıldı.',
            'Varsa lehine olan durumları, mazeretini, tahrik unsurunu veya tanıklarını bildirebileceği açıklandı.',
            'Yaptığı davranıştan dolayı pişmanlık duyup duymadığı ve zararı/kırgınlığı telafi etme isteği soruldu.',
          ],
        ),
        const DocQuestionField(
          key: 'defenseText',
          label:
              'Öğrencinin Yazılı Savunması (Boş bırakılırsa öğrencinin kendi el yazısıyla doldurması için satırlar açılır)',
          type: DocFieldType.multiline,
          hint:
              'Öğrencinin savunmasını girebilir veya boş bırakıp çıktıda kendi el yazısıyla yazmasını sağlayabilirsiniz...',
        ),
        const DocQuestionField(
          key: 'chair',
          label: 'Savunmayı Alan Kurul Başkanı',
          type: DocFieldType.staffSelect,
        ),
        const DocQuestionField(
          key: 'member',
          label: 'Hazır Bulunan Kurul Üyesi Öğretmen',
          type: DocFieldType.staffSelect,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Dosya No / İşlem', '${_str(a, "fileNo")} — Öğrenci Yazılı Savunma Tutanağı'),
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Savunma Tarih / Saat', _str(a, 'date')),
      ],
      composeBody: (a, ctx) {
        final def = _str(a, 'defenseText');
        return '''
ÖĞRENCİ SAVUNMA ALMA TUTANAĞI

1. BİLDİRİLEN İDDİA / OLAY ÖZETİ:
${_str(a, 'allegation')}

2. YASAL SAVUNMA GÜVENCELERİ:
${_numberedLines(_list(a, 'defenseGuarantees'))}

3. ÖĞRENCİNİN SAVUNMASI:
Yukarıda tarafıma açıkça bildirilen olayla ilgili savunmam ve açıklamalarım aşağıdadır:

${def.isNotEmpty ? def : _blankLines(9)}

Savunma hakkımı özgür irademle kullandım; tutanağı okudum ve imzaladım.''';
      },
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(a, 'student', 'Öğrenci'),
          title: 'Savunma Veren Öğrenci',
        ),
        if (_str(a, 'member').isNotEmpty)
          DocSigner(name: _str(a, 'member'), title: 'Kurul Üyesi Öğretmen'),
        DocSigner(
          name: _str(
            a,
            'chair',
            ctx.vicePrincipals.isNotEmpty
                ? ctx.vicePrincipals.first.fullName
                : 'Kurul Başkanı',
          ),
          title: 'Kurul Başkanı (Md. Yrd.)',
        ),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // ÖDDK-10: VELİ BİLGİLENDİRME VE VELİ GÖRÜŞ / BEYAN TUTANAĞI
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'oddk_10_veli_bilgilendirme_ve_beyan_tutanagi',
      code: 'ÖDDK-10',
      categoryId: 'oddk_disiplin_surec_paketi',
      title:
          '10. Adım: Soruşturma Sürecinde Veli Bilgilendirme ve Veli Görüş / Beyan Tutanağı',
      subtitle:
          'İnceleme sürecinde okula davet edilen velinin bilgilendirilmesi, ailevi durum beyanı ve iş birliği taahhüdü',
      legalBasis:
          'MEB İlköğretim Yönetmeliği Md. 56–57 & Ortaöğretim Yönetmeliği Md. 168–171',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.supervisor_account_rounded,
      questions: [
        const DocQuestionField(
          key: 'fileNo',
          label: 'Dosya No',
          type: DocFieldType.text,
          defaultValue: '2026 / ÖDDK-01',
        ),
        const DocQuestionField(
          key: 'targetClass',
          label: 'Öğrencinin Şubesi',
          type: DocFieldType.classSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'student',
          label: 'Öğrenci Seçimi',
          type: DocFieldType.studentSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'parentName',
          label: 'Görüşülen Veli Adı Soyadı ve Yakınlık Derecesi',
          type: DocFieldType.text,
          hint: 'Örn: Fatma DEMİR (Annesi)',
          required: true,
        ),
        DocQuestionField(
          key: 'date',
          label: 'Görüşme Tarihi ve Saati',
          type: DocFieldType.text,
          defaultValue: '${_today()} - ${_nowTime()}',
        ),
        const DocQuestionField(
          key: 'sharedPoints',
          label: 'Veliye Aktarılan Hususlar',
          type: DocFieldType.multiCheck,
          options: [
            'Öğrencinin karıştığı olay, yürütülen ÖDDK / Disiplin Kurulu inceleme süreci ve ilgili yönetmelik hükümleri veliye açıklandı.',
            'Kurulun temel amacının öğrenciyi kazanmak, hatalı davranışı düzeltmek ve okul güvenliğini korumak olduğu vurgulandı.',
            'Öğrencinin son dönemdeki ailevi, sağlık veya duygusal durumuna ilişkin hafifletici/açıklayıcı bir husus olup olmadığı veliye soruldu.',
            'Varsa oluşan maddi zararın karşılanması (tazmini) ve taraflar arasında onarıcı özür/uzlaşma süreci hakkında bilgi verildi.',
            'Alınacak kurul kararının ayrıca yazılı olarak tebliğ edileceği ve yasal itiraz haklarının saklı olduğu belirtildi.',
          ],
          defaultValue: [
            'Öğrencinin karıştığı olay, yürütülen ÖDDK / Disiplin Kurulu inceleme süreci ve ilgili yönetmelik hükümleri veliye açıklandı.',
            'Kurulun temel amacının öğrenciyi kazanmak, hatalı davranışı düzeltmek ve okul güvenliğini korumak olduğu vurgulandı.',
            'Öğrencinin son dönemdeki ailevi, sağlık veya duygusal durumuna ilişkin hafifletici/açıklayıcı bir husus olup olmadığı veliye soruldu.',
            'Alınacak kurul kararının ayrıca yazılı olarak tebliğ edileceği ve yasal itiraz haklarının saklı olduğu belirtildi.',
          ],
        ),
        const DocQuestionField(
          key: 'parentStatement',
          label: 'Velinin Görüşü, Açıklaması ve Taahhüdü',
          type: DocFieldType.multiline,
          defaultValue:
              'Veli, olay hakkında bilgilendirildiğini, öğrencisiyle evde gerekli yapıcı görüşmeyi yapacağını, okul yönetimi ve rehberlik servisiyle tam iş birliği içinde olacağını beyan etmiştir.',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Dosya No', _str(a, 'fileNo')),
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Görüşülen Veli', _str(a, 'parentName')),
        MapEntry('Tarih / Saat', _str(a, 'date')),
      ],
      composeBody: (a, ctx) => '''
ÖDDK / DİSİPLİN SÜRECİ VELİ BİLGİLENDİRME VE BEYAN TUTANAĞI

1. VELİYE BİLGİ VERİLEN HUSUSLAR:
${_numberedLines(_list(a, 'sharedPoints'))}

2. ÖĞRENCİ VELİSİNİN GÖRÜŞ VE BEYANI:
${_str(a, 'parentStatement')}

İşbu tutanak veli bilgilendirme ve görüş alma işleminin belgelendirilmesi amacıyla iki nüsha düzenlenerek imza altına alınmıştır.''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(a, 'parentName').split('(').first.trim(),
          title: 'Bilgilendirilen Öğrenci Velisi',
        ),
        DocSigner(
          name: ctx.vicePrincipals.isNotEmpty
              ? ctx.vicePrincipals.first.fullName
              : ctx.principalName,
          title: 'Kurul Başkanı / Müdür Yardımcısı',
        ),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // ÖDDK-11: OKUL REHBERLİK VE PDR SERVİSİ VAKA İNCELEME RAPORU (ZORUNLU)
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'oddk_11_pdr_vaka_inceleme_kanaat_raporu',
      code: 'ÖDDK-11',
      categoryId: 'oddk_disiplin_surec_paketi',
      title:
          '11. Adım: Okul Rehberlik (PDR) Servisi Vaka İnceleme ve Psiko-Sosyal Kanaat Raporu (GİZLİ)',
      subtitle:
          'ÖDDK ve Disiplin Kurulu kararından önce alınması mevzuatça zorunlu olan rehberlik ön inceleme ve nedenleri araştırma raporu',
      legalBasis:
          'MEB İlköğretim Yönetmeliği Md. 56–57, Ortaöğretim Md. 168–171 & RPDH Yönetmeliği',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.psychology_rounded,
      questions: [
        const DocQuestionField(
          key: 'fileNo',
          label: 'İlgili Kurul Dosya No',
          type: DocFieldType.text,
          defaultValue: '2026 / ÖDDK-01 (GİZLİ)',
        ),
        const DocQuestionField(
          key: 'targetClass',
          label: 'Öğrencinin Şubesi',
          type: DocFieldType.classSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'student',
          label: 'Değerlendirilen Öğrenci',
          type: DocFieldType.studentSelect,
          required: true,
        ),
        DocQuestionField(
          key: 'date',
          label: 'Rapor Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'counselor',
          label: 'Raporu Düzenleyen Rehber Öğretmen / Psikolojik Danışman',
          type: DocFieldType.staffSelect,
        ),
        const DocQuestionField(
          key: 'psychosocialFactors',
          label: 'Psiko-Sosyal Değerlendirme ve Davranışın Altında Yatan Etkenler',
          type: DocFieldType.multiCheck,
          options: [
            'Öğrenci ile bireysel görüşme yapılmış; gelişim dönemi özellikleri, dürtü kontrolü ve duygu düzenleme becerileri değerlendirilmiştir.',
            'Öğrencinin daha önce disiplin yaptırımı bulunmadığı ve olayın anlık akran geriliminden kaynaklandığı gözlemlenmiştir.',
            'Öğrencinin yaptığı davranışın sonuçlarını kavradığı, empati kurabildiği ve samimi pişmanlık ifade ettiği gözlenmiştir.',
            'Akademik zorlanma, dikkat dağınıklığı veya akran grubunda kabul görme ihtiyacının davranış üzerinde etkili olduğu değerlendirilmektedir.',
            'Aile içi iletişim dinamikleri veya yakın dönemli yaşam olaylarının öğrencinin duygusal tepkilerini etkilediği gözlenmiştir.',
            'Öğrencinin özel eğitim / BEP / sağlık durumu dikkate alınarak pedagojik uyarlama ve bireysel izleme ihtiyacı bulunmaktadır.',
            'Öfke kontrolü, çatışma çözme ve sosyal beceri alanında yapılandırılmış psikolojik danışma/rehberlik takibine alınması planlanmıştır.',
            'Öğrencinin okul içi kulüp, spor veya sorumluluk çalışmalarına yönlendirilmesinin aidiyet duygusunu güçlendireceği değerlendirilmektedir.',
          ],
          defaultValue: [
            'Öğrenci ile bireysel görüşme yapılmış; gelişim dönemi özellikleri, dürtü kontrolü ve duygu düzenleme becerileri değerlendirilmiştir.',
            'Öğrencinin yaptığı davranışın sonuçlarını kavradığı, empati kurabildiği ve samimi pişmanlık ifade ettiği gözlenmiştir.',
            'Öfke kontrolü, çatışma çözme ve sosyal beceri alanında yapılandırılmış psikolojik danışma/rehberlik takibine alınması planlanmıştır.',
          ],
        ),
        const DocQuestionField(
          key: 'pdrOpinion',
          label: 'Kurula Sunulan Pedagojik Görüş ve Öneri Özeti',
          type: DocFieldType.multiline,
          defaultValue:
              'Öğrencinin yaşı, gelişim özellikleri ve üstün yararı gözetildiğinde; davranışın düzeltilmesinde rehberlik temelli izleme, olumlu sorumluluk verme ve okul-aile iş birliği tedbirlerinin ön planda tutulması pedagojik açıdan uygun değerlendirilmektedir.',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Gizlilik Derecesi', 'GİZLİ — ÖDDK / ÖĞRENCİ ÖDÜL VE DİSİPLİN KURULU BAŞKANLIĞINA'),
        MapEntry('Dosya No / Tarih', '${_str(a, "fileNo")} — ${_str(a, "date", _today())}'),
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
      ],
      composeBody: (a, ctx) => '''
OKUL REHBERLİK VE PSİKOLOJİK DANIŞMA SERVİSİ ÖN İNCELEME VE KANAAT RAPORU (GİZLİ)

Kurulunuzca yürütülen inceleme kapsamında ${_str(a, 'targetClass')} şubesi öğrencisi ${_str(a, 'student')} ile yapılan görüşme ve gelişimsel değerlendirme bulguları mesleki etik ve gizlilik sınırları çerçevesinde aşağıda sunulmuştur:

1. GELİŞİMSEL VE PSİKO-SOSYAL GÖZLEM BULGULARI:
${_numberedLines(_list(a, 'psychosocialFactors'))}

2. PEDAGOJİK KANAAT VE ÖNERİLER:
${_str(a, 'pdrOpinion')}

İşbu rapor yalnızca ilgili Kurulun değerlendirmesine sunulmak üzere gizlilik kaydıyla düzenlenmiştir.''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(
            a,
            'counselor',
            ctx.counselors.isNotEmpty
                ? ctx.counselors.first.fullName
                : 'Rehber Öğretmen / Psikolojik Danışman',
          ),
          title: 'Rehber Öğretmen / Psikolojik Danışman',
        ),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // ÖDDK-12: ÖDDK / DİSİPLİN KURULU TOPLANTI ÇAĞRISI VE GÜNDEM TEBLİĞİ
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'oddk_12_kurul_toplanti_cagrisi_ve_teblig',
      code: 'ÖDDK-12',
      categoryId: 'oddk_disiplin_surec_paketi',
      title:
          '12. Adım: ÖDDK / Disiplin Kurulu Resmi Toplantı Çağrısı ve Gündem İmza Sirküsü',
      subtitle:
          'Kurul başkanı, seçilmiş öğretmen üyeler ve OAB veli temsilcisinin toplantıya resmi davet ve gündem tebliğ çizelgesi',
      legalBasis:
          'MEB İlköğretim Yönetmeliği Md. 58–59 & Ortaöğretim Yönetmeliği Md. 185–187',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.circularSignatureTable,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.notifications_active_rounded,
      usesStaffSignatureSelector: true,
      questions: [
        const DocQuestionField(
          key: 'boardType',
          label: 'Toplanacak Kurul',
          type: DocFieldType.dropdown,
          options: [
            'Öğrenci Davranışlarını Değerlendirme Kurulu (ÖDDK)',
            'Okul Öğrenci Ödül ve Disiplin Kurulu',
          ],
          defaultValue: 'Öğrenci Davranışlarını Değerlendirme Kurulu (ÖDDK)',
        ),
        DocQuestionField(
          key: 'meetingDate',
          label: 'Toplantı Tarihi ve Saati',
          type: DocFieldType.text,
          defaultValue: '${_today()} - Saat 15:15',
        ),
        const DocQuestionField(
          key: 'place',
          label: 'Toplantı Yeri',
          type: DocFieldType.text,
          defaultValue: 'Müdür Yardımcılığı / Kurul Toplantı Odası',
        ),
        const DocQuestionField(
          key: 'fileNo',
          label: 'Görüşülecek Dosya Numarası',
          type: DocFieldType.text,
          defaultValue: '2026 / ÖDDK-01',
        ),
        const DocQuestionField(
          key: 'agendaItems',
          label: 'Kurul Toplantı Gündem Maddeleri',
          type: DocFieldType.multiCheck,
          options: [
            'Açılış, yoklama ve gizlilik ilkesinin hatırlatılması',
            'İlgili soruşturma/inceleme dosyasındaki olay tutanağı ve delillerin okunması',
            'Mağdur, görgü tanığı ve öğrenci yazılı savunma tutanaklarının incelenmesi',
            'Sınıf rehber öğretmeni sevk raporu ve Okul PDR Servisi vaka kanaat raporunun değerlendirilmesi',
            'Yönetmelik uyarınca hafifletici/ağırlaştırıcı nedenlerin, iyi halin ve onarıcı tedbirlerin müzakere edilmesi',
            'Oylama yapılarak gerekçeli kurul kararının yazılması ve imzalanması',
            'Kapanış',
          ],
          defaultValue: [
            'Açılış, yoklama ve gizlilik ilkesinin hatırlatılması',
            'İlgili soruşturma/inceleme dosyasındaki olay tutanağı ve delillerin okunması',
            'Mağdur, görgü tanığı ve öğrenci yazılı savunma tutanaklarının incelenmesi',
            'Sınıf rehber öğretmeni sevk raporu ve Okul PDR Servisi vaka kanaat raporunun değerlendirilmesi',
            'Oylama yapılarak gerekçeli kurul kararının yazılması ve imzalanması',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Kurul Adı', _str(a, 'boardType')),
        MapEntry('Toplantı Tarih / Saat', _str(a, 'meetingDate')),
        MapEntry('Toplantı Yeri / Dosya', '${_str(a, "place")} — ${_str(a, "fileNo")}'),
      ],
      composeBody: (a, ctx) => '''
KURUL ÜYELERİNE RESMİ TOPLANTI ÇAĞRISI VE GÜNDEM TEBLİĞİ

Kurumumuz "${_str(a, 'boardType')}", "${_str(a, 'fileNo')}" sayılı dosyayı görüşüp karara bağlamak üzere ${_str(a, 'meetingDate')} tarihinde ${_str(a, 'place')} adresinde aşağıda belirtilen gündemle toplanacaktır.

GÜNDEM:
${_numberedLines(_list(a, 'agendaItems'))}

Kurul asil üyelerinin (mazereti bulunanların yerine yedek üyelerin) ve ilgili temsilcilerin belirtilen gün ve saatte hazır bulunmaları hususunda tebliğ ve imza çizelgesi aşağıdadır:''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: ctx.vicePrincipals.isNotEmpty
              ? ctx.vicePrincipals.first.fullName
              : 'Kurul Başkanı',
          title: 'Kurul Başkanı (Md. Yrd.)',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'ONAY'),
          isApproval: true,
        ),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // ÖDDK-13: AKRAN UZLAŞMA, ÖZÜR VE MADDİ ZARAR GİDERME TUTANAĞI
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'oddk_13_akran_uzlasma_zarar_tazmin_tutanagi',
      code: 'ÖDDK-13',
      categoryId: 'oddk_disiplin_surec_paketi',
      title:
          '13. Adım: Onarıcı Disiplin, Samimi Özür, Akran Uzlaşma ve Maddi Zarar Giderme Tutanağı',
      subtitle:
          'Kurul kararında hafifletici neden / yaptırıma yer olmadığına esas teşkil eden barışma veya okul malı hasar tazmin tutanağı',
      legalBasis:
          'MEB İlköğretim Yönetmeliği Md. 55–56 & Ortaöğretim Yönetmeliği Md. 167–168 (Zararın Ödettirilmesi & İyi Hal)',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.diversity_1_rounded,
      questions: [
        const DocQuestionField(
          key: 'targetClass',
          label: 'Şube Seçimi',
          type: DocFieldType.classSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'students',
          label: 'Uzlaşan / Zararı Gideren Öğrenci(ler)',
          type: DocFieldType.multiStudentSelect,
          required: true,
        ),
        DocQuestionField(
          key: 'date',
          label: 'Mutabakat Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'restorativeActions',
          label: 'Gerçekleşen Onarıcı Disiplin / Uzlaşma / Zarar Tazmin Maddeleri',
          type: DocFieldType.multiCheck,
          options: [
            'Olaya karışan öğrenciler rehber öğretmen ve idare eşliğinde gönüllü olarak bir araya gelerek karşılıklı özür dilemiş ve barışmıştır.',
            'Öğrenciler benzer bir kırgınlık veya çatışmanın tekrarlanmaması konusunda karşılıklı iyi niyet sözü vermiştir.',
            'Okul demirbaşında / sınıf eşyasında meydana gelen maddi hasar öğrenci velisi tarafından aynen onarılmış / yenisiyle değiştirilmiştir.',
            'Arkadaşının zarar gören ders materyali / kişisel eşyası veli bilgisi dahilinde eksiksiz tazmin edilmiştir.',
            'Öğrenci, okul ortamına olumlu katkı sunmak amacıyla kütüphane/çevre düzeni gibi eğitsel bir sosyal sorumluluk görevini gönüllü üstlenmiştir.',
            'İşbu olumlu tutum ve zararın giderilmesi durumu, hafifletici neden olarak değerlendirilmek üzere ÖDDK / Disiplin Kurulu dosyasına eklenmiştir.',
          ],
          defaultValue: [
            'Olaya karışan öğrenciler rehber öğretmen ve idare eşliğinde gönüllü olarak bir araya gelerek karşılıklı özür dilemiş ve barışmıştır.',
            'Öğrenciler benzer bir kırgınlık veya çatışmanın tekrarlanmaması konusunda karşılıklı iyi niyet sözü vermiştir.',
            'İşbu olumlu tutum ve zararın giderilmesi durumu, hafifletici neden olarak değerlendirilmek üzere ÖDDK / Disiplin Kurulu dosyasına eklenmiştir.',
          ],
        ),
        const DocQuestionField(
          key: 'damageDetail',
          label: 'Giderilen Maddi Hasar / Ek Uzlaşma Notu (Varsa)',
          type: DocFieldType.text,
          defaultValue: 'Taraflar arasında tam uzlaşma ve okul iklimine uyum mutabakatı sağlanmıştır.',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('İşlem Türü', 'Akran Uzlaşma ve Onarıcı Telafi / Zarar Giderme Tutanağı'),
        MapEntry('Öğrenci(ler) / Şube', '${_list(a, "students").join(", ")} (${_str(a, "targetClass")})'),
        MapEntry('Tarih', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
AKRAN UZLAŞMA, ÖZÜR VE MADDİ ZARAR GİDERME MUTABAKAT TUTANAĞI

Eğitim ortamında barışçıl okul ikliminin korunması ve onarıcı rehberlik yaklaşımı doğrultusunda ${_str(a, 'date', _today())} tarihinde yapılan görüşmede aşağıdaki hususlar gerçekleşmiştir:

1. SAĞLANAN UZLAŞMA VE TELAFİ ADIMLARI:
${_numberedLines(_list(a, 'restorativeActions'))}

2. AÇIKLAMA:
${_str(a, 'damageDetail')}

İşbu tutanak tarafların özgür iradesiyle düzenlenerek imza altına alınmıştır.''',
      buildSigners: (a, ctx) => [
        for (final s in _list(a, 'students').take(2))
          DocSigner(name: s.split('(').first.trim(), title: 'Öğrenci'),
        if (ctx.counselors.isNotEmpty)
          DocSigner(
            name: ctx.counselors.first.fullName,
            title: 'Uzlaştırıcı Rehber Öğretmen / PDR',
          ),
        DocSigner(
          name: ctx.vicePrincipals.isNotEmpty
              ? ctx.vicePrincipals.first.fullName
              : ctx.principalName,
          title: 'Müdür Yardımcısı / Kurul Başkanı',
          isApproval: true,
        ),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // ÖDDK-14: KAPSAMLI ÖDDK / DİSİPLİN KURULU GEREKÇELİ KARAR TUTANAĞI
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'oddk_14_kurul_gerekceli_karar_tutanagi',
      code: 'ÖDDK-14',
      categoryId: 'oddk_disiplin_surec_paketi',
      title:
          '14. Adım: ÖDDK / Öğrenci Disiplin Kurulu Kapsamlı Müzakere ve Gerekçeli Karar Tutanağı',
      subtitle:
          'MEB İlköğretim Md. 55-60 ve Ortaöğretim Md. 164-173 tüm alt bentleri, hafifletici nedenler ve oy birliği/çokluğu nihai kararı',
      legalBasis:
          'MEB İlköğretim Yönetmeliği Md. 55–60 & Ortaöğretim Yönetmeliği Md. 164–173',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.balance_rounded,
      questions: [
        const DocQuestionField(
          key: 'decisionNo',
          label: 'Kurul Karar Sayısı ve Dosya No',
          type: DocFieldType.text,
          defaultValue: 'Karar No: 2026/04 (Dosya: 2026/ÖDDK-01)',
        ),
        DocQuestionField(
          key: 'date',
          label: 'Karar Tarihi ve Saati',
          type: DocFieldType.text,
          defaultValue: '${_today()} - 15:30',
        ),
        const DocQuestionField(
          key: 'boardName',
          label: 'Kararı Veren Kurul',
          type: DocFieldType.dropdown,
          options: [
            'Öğrenci Davranışlarını Değerlendirme Kurulu (İlköğretim Md. 55)',
            'Okul Öğrenci Ödül ve Disiplin Kurulu (Ortaöğretim Md. 164)',
          ],
          defaultValue:
              'Öğrenci Davranışlarını Değerlendirme Kurulu (İlköğretim Md. 55)',
        ),
        const DocQuestionField(
          key: 'targetClass',
          label: 'Öğrencinin Şubesi',
          type: DocFieldType.classSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'student',
          label: 'Hakkında Karar Verilen Öğrenci',
          type: DocFieldType.studentSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'reviewedDocs',
          label: 'Kurulca İncelenen Dosya Evrakları (Usul Tamamlık Kontrolü)',
          type: DocFieldType.multiCheck,
          options: [
            'Sözlü uyarı tutanağı, EK-9 Öğrenci Sözleşmesi ve Veli önlem/gelmeme tutanağı (Md. 54 aşamaları)',
            'Ayrıntılı olay tespit tutanağı, maddi deliller ve güvenlik kamerası inceleme kaydı',
            'Mağdur/zarar gören öğrenci beyanı ile görgü tanıklarının ifadeleri',
            'Hakkında inceleme yapılan öğrencinin usulüne uygun alınan yazılı savunması ve veli beyanı',
            'Okul Rehberlik ve Psikolojik Danışma (PDR) Servisi vaka inceleme ve kanaat raporu',
            'Sınıf rehber öğretmeni görüşü, öğrencinin geçmiş davranış/başarı durumu ve uzlaşma/zarar tazmin tutanağı',
          ],
          defaultValue: [
            'Ayrıntılı olay tespit tutanağı, maddi deliller ve güvenlik kamerası inceleme kaydı',
            'Mağdur/zarar gören öğrenci beyanı ile görgü tanıklarının ifadeleri',
            'Hakkında inceleme yapılan öğrencinin usulüne uygun alınan yazılı savunması ve veli beyanı',
            'Okul Rehberlik ve Psikolojik Danışma (PDR) Servisi vaka inceleme ve kanaat raporu',
          ],
        ),
        const DocQuestionField(
          key: 'mitigatingFactors',
          label: 'Değerlendirilen İyi Hal, Pedagojik ve Hafifletici Hususlar (Md. 56 / Md. 168)',
          type: DocFieldType.multiCheck,
          options: [
            'Öğrencinin daha önce herhangi bir disiplin yaptırımı / cezası almamış olması',
            'Öğrencinin yaşı, gelişim özellikleri ve çocuk/ergenlik dönemi hassasiyeti',
            'Davranışından dolayı samimi pişmanlık duyması, özür dilemesi ve akranıyla uzlaşması',
            'Meydana gelen maddi zararın öğrenci/velisi tarafından giderilmiş (tazmin edilmiş) olması',
            'Olayın meydana gelişinde haksız tahrik veya anlık tepki unsurunun bulunması',
            'Derslerdeki genel gayreti ve PDR Servisi izleme sürecine iş birliğiyle katılması',
            'Hafifletici neden uygulanmaksızın fiilin karşılığı olan asıl yaptırımın uygulanması gerektiği kanaatine varılmıştır',
          ],
          defaultValue: [
            'Öğrencinin daha önce herhangi bir disiplin yaptırımı / cezası almamış olması',
            'Öğrencinin yaşı, gelişim özellikleri ve çocuk/ergenlik dönemi hassasiyeti',
            'Davranışından dolayı samimi pişmanlık duyması, özür dilemesi ve akranıyla uzlaşması',
          ],
        ),
        const DocQuestionField(
          key: 'finalVerdict',
          label: 'Kurulun Nihai Kararı / Yaptırım Türü',
          type: DocFieldType.dropdown,
          options: [
            'Yaptırım / Ceza Verilmesine Yer Olmadığına — PDR Rehberlik Takibi ve Veli İş Birliği Uygulanmasına',
            'İlköğretim Md. 55/1-a Uyarınca "UYARMA" Yaptırımı Verilmesine (Yazılı Bildirim, e-Okul Siciline İşlenmez)',
            'İlköğretim Md. 55/1-b Uyarınca "KINAMA" Yaptırımı Verilmesine (İyi Hal İndirimi Değerlendirilerek)',
            'İlköğretim Md. 55/1-c Uyarınca "OKUL DEĞİŞTİRME" Yaptırım Teklifinin İlçe ÖDDK\'ya Gönderilmesine',
            'Ortaöğretim Md. 164/1 Uyarınca "KINAMA" Cezası Verilmesine (-10 Davranış Puanı)',
            'Ortaöğretim Md. 164/2 Uyarınca "OKULDAN 1–5 GÜN KISA SÜRELİ UZAKLAŞTIRMA" Cezası Verilmesine (-20 Puan)',
            'Ortaöğretim Md. 164/3 Uyarınca "OKUL DEĞİŞTİRME" Teklifinin İlçe Disiplin Kuruluna Sunulmasına (-40 Puan)',
            'Ortaöğretim Md. 164/4 Uyarınca "ÖRGÜN EĞİTİM DIŞINA ÇIKARMA" Teklifinin İl Disiplin Kuruluna Sunulmasına (-80 Puan)',
          ],
          defaultValue:
              'İlköğretim Md. 55/1-a Uyarınca "UYARMA" Yaptırımı Verilmesine (Yazılı Bildirim, e-Okul Siciline İşlenmez)',
        ),
        const DocQuestionField(
          key: 'voteType',
          label: 'Oylama Sonucu',
          type: DocFieldType.dropdown,
          options: ['Oy Birliği İle', 'Oy Çokluğu İle'],
          defaultValue: 'Oy Birliği İle',
        ),
        const DocQuestionField(
          key: 'customReasoning',
          label: 'Gerekçeli Karar Özeti ve Ek Tedbir Notu',
          type: DocFieldType.multiline,
          defaultValue:
              'Dosya kapsamındaki tüm bilgi, belge, tanık beyanları, öğrenci savunması ve PDR kanaat raporu birlikte değerlendirildiğinde; eğitici ve caydırıcı denge gözetilerek yukarıdaki karar tesis edilmiştir.',
        ),
        const DocQuestionField(
          key: 'boardChair',
          label: 'Kurul Başkanı (Müdür Başyardımcısı / Müdür Yardımcısı)',
          type: DocFieldType.staffSelect,
        ),
        const DocQuestionField(
          key: 'boardMembers',
          label: 'Kurul Üyesi Öğretmenler (Seçilmiş Üyeler + Sınıf Öğrt. / OAB Temsilcisi)',
          type: DocFieldType.multiStaffSelect,
          required: true,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Kurul Adı', _str(a, 'boardName')),
        MapEntry('Karar Sayısı / Tarihi', '${_str(a, "decisionNo")} — ${_str(a, "date")}'),
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Hüküm ve Oylama', '${_str(a, "finalVerdict")} (${_str(a, "voteType")})'),
      ],
      composeBody: (a, ctx) => '''
GEREKÇELİ KURUL KARAR TUTANAĞI

1. İNCELENEN SORUŞTURMA DOSYASI BELGELERİ:
${_numberedLines(_list(a, 'reviewedDocs'))}

2. OLAYIN MÜZAKERESİ VE DEĞERLENDİRİLEN HAFİFLETİCİ / PEDAGOJİK HUSUSLAR:
${_numberedLines(_list(a, 'mitigatingFactors'))}

${_str(a, 'customReasoning')}

3. HÜKÜM / KURUL KARARI:
Yapılan müzakere ve açık oylama sonucunda ${_str(a, 'targetClass')} şubesi öğrencisi ${_str(a, 'student')} hakkında ${_str(a, 'voteType')};
"${_str(a, 'finalVerdict')}"
yönünde karar verilmiştir.

4. ONAY, TEBLİĞ VE İTİRAZ YOLU:
İşbu kararın Okul Müdürü onayını müteakip öğrenci velisine yazılı olarak tebliğ edilmesine, tebliğ tarihinden itibaren 5 (beş) iş günü içinde bir üst kurula / okul müdürlüğüne yazılı itiraz hakkının bulunduğunun bildirilmesine ve öğrencinin Okul Rehberlik Servisince izlenmesine karar verildi.''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'boardMembers').take(4))
          DocSigner(name: m, title: 'Kurul Üyesi'),
        DocSigner(
          name: _str(
            a,
            'boardChair',
            ctx.vicePrincipals.isNotEmpty
                ? ctx.vicePrincipals.first.fullName
                : 'Kurul Başkanı',
          ),
          title: 'Kurul Başkanı (Md. Yrd.)',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'UYGUNDUR / ONAY'),
          isApproval: true,
        ),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // ÖDDK-15: KURUL KARARI VELİ RESMİ SONUÇ TEBLİGATI & 5 İŞ GÜNÜ İTİRAZ BİLDİRİMİ
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'oddk_15_karar_veli_sonuc_tebligati',
      code: 'ÖDDK-15',
      categoryId: 'oddk_disiplin_surec_paketi',
      title:
          '15. Adım: ÖDDK / Disiplin Kurulu Kararı Veli Resmi Tebligatı ve İtiraz Hakkı Bildirimi',
      subtitle:
          'Alınan kurul kararının veliye yazılı/elden tebliği, 5 iş günü yasal itiraz süresi bildirimi ve kesilebilir tebellüğ pusulası',
      legalBasis:
          'MEB İlköğretim Yönetmeliği Md. 59–60 & Ortaöğretim Yönetmeliği Md. 173–175',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.officialLetter,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.mark_email_read_rounded,
      questions: [
        const DocQuestionField(
          key: 'docNo',
          label: 'Sayı / Tebliğ No',
          type: DocFieldType.text,
          defaultValue: 'ÖDDK-KARAR / 2026-04',
        ),
        DocQuestionField(
          key: 'date',
          label: 'Tebligat Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'targetClass',
          label: 'Öğrencinin Şubesi',
          type: DocFieldType.classSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'student',
          label: 'Öğrenci Seçimi',
          type: DocFieldType.studentSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'parentName',
          label: 'Tebliğ Yapılacak Veli Adı Soyadı',
          type: DocFieldType.text,
          hint: 'Örn: Sayın Hasan YILMAZ',
          required: true,
        ),
        const DocQuestionField(
          key: 'decisionSummary',
          label: 'Tebliğ Edilen Kurul Karar Tarih, Sayısı ve Özeti',
          type: DocFieldType.multiline,
          defaultValue:
              'Okulumuz Öğrenci Davranışlarını Değerlendirme (Ödül ve Disiplin) Kurulunun 2026/04 sayılı kararı ile öğrencimiz hakkında ilgili yönetmelik hükmü uyarınca yaptırım ve rehberlik izleme tedbiri kararlaştırılmıştır.',
          required: true,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Sayı / Tarih', '${_str(a, "docNo")} — ${_str(a, "date", _today())}'),
        MapEntry('Konu', 'Kurul Kararının Tebliği (GİZLİ / VELİYE ÖZEL)'),
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
      ],
      composeBody: (a, ctx) => '''
SAYIN ${_str(a, 'parentName', 'ÖĞRENCİ VELİSİ').toUpperCase()}
(${_str(a, 'student')} Velisi)

Velisi bulunduğunuz okulumuz ${_str(a, 'targetClass')} şubesi öğrencisi ${_str(a, 'student')} hakkında yürütülen inceleme sonucunda alınan ve Müdürlüğümüzce onaylanan kurul kararı aşağıda bilgilerinize tebliğ olunur:

KARAR ÖZETİ:
${_str(a, 'decisionSummary')}

YASAL İTİRAZ SÜRESİ VE REHBERLİK İŞ BİRLİĞİ BİLDİRİMİ:
İlgili MEB Kurum Yönetmeliği hükümleri uyarınca, işbu kararın tarafınıza tebliğ edildiği tarihten itibaren 5 (beş) iş günü içerisinde Okul Müdürlüğümüz aracılığıyla veya doğrudan İlçe Öğrenci Davranışlarını Değerlendirme / Disiplin Kuruluna yazılı olarak itirazda bulunma hakkınız mevcuttur. Öğrencimizin olumlu davranış gelişiminin desteklenmesi sürecinde Okul Rehberlik Servisimizle iş birliğinizin devamını önemle rica ederim.

- - - - - - - - - - - - - - - - - - - - ✂ KESİNİZ (VELİ TEBELLÜĞ BELGESİ — DOSYAYA KONULACAKTIR) - - - - - - - - - - - - - - - - - - - -
Velisi bulunduğum ${_str(a, 'student')} (${_str(a, 'targetClass')}) hakkındaki "${_str(a, 'docNo')}" sayılı ÖDDK / Disiplin Kurulu karar tebligatını kapalı zarf / elden teslim aldım. 5 iş günü yasal itiraz hakkım konusunda bilgilendirildim.
Tebellüğ Tarihi: .... / .... / 202..   Saat: ....:....   Veli Adı Soyadı ve İmzası: ..................................................''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx),
          isApproval: true,
        ),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // ÖDDK-16: DAVRANIŞ İZLEME, YIL SONU YAPTIRIM/CEZA SİLME VE DİZİ PUSULASI
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'oddk_16_izleme_ceza_kaldirma_ve_dizi_pusulasi',
      code: 'ÖDDK-16',
      categoryId: 'oddk_disiplin_surec_paketi',
      title:
          '16. Adım: Yaptırım Sonrası İzleme, Yıl Sonu Ceza Kaldırma (Silme) ve Dosya Dizi Pusulası',
      subtitle:
          'Olumlu davranış geliştiren öğrencinin yaptırımının yıl sonu kurulca kaldırılması ve soruşturma dosyası tam evrak kontrol listesi',
      legalBasis:
          'MEB İlköğretim Yönetmeliği Md. 55–61 & Ortaöğretim Yönetmeliği Md. 178',
      scopes: const [
        DocRegulationScope.ortakMevzuat,
        DocRegulationScope.ilkogretimOkulOncesi,
        DocRegulationScope.ortaogretimLise,
      ],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.task_alt_rounded,
      questions: [
        const DocQuestionField(
          key: 'docMode',
          label: 'Düzenlenecek Kapanış Belgesi Türü',
          type: DocFieldType.dropdown,
          options: [
            '1) Ders Yılı Sonu Yaptırım / Disiplin Cezası Kaldırma (Silme) ve Davranış Puanı İade Kararı',
            '2) ÖDDK / Disiplin Soruşturma Dosyası Resmi Dizi Pusulası (Tam Evrak Kontrol ve Arşiv Kapak Formu)',
          ],
          defaultValue:
              '1) Ders Yılı Sonu Yaptırım / Disiplin Cezası Kaldırma (Silme) ve Davranış Puanı İade Kararı',
        ),
        DocQuestionField(
          key: 'date',
          label: 'Tarih',
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
          label: 'İlgili Öğrenci',
          type: DocFieldType.studentSelect,
        ),
        const DocQuestionField(
          key: 'fileCheckItems',
          label: 'Dosyada Bulunan Belgeler / Olumlu Gelişim Göstergeleri',
          type: DocFieldType.multiCheck,
          options: [
            '1. Öğretmen Sözlü Uyarı ve Yapıcı Görüşme Tutanağı (ÖDDK-01)',
            '2. MEB EK-9 Öğrenci Olumlu Davranış Geliştirme Sözleşmesi (ÖDDK-02)',
            '3. Sözleşme Sonrası Veli Önlem Görüşme / Gelmeme Tutanağı (ÖDDK-03)',
            '4. Ayrıntılı Olay Tespit ve Güvenlik Kamerası İnceleme Tutanağı (ÖDDK-04)',
            '5. Sınıf Rehber Öğretmeni Sevk Raporu ve Müdürlük Havale Onayı (ÖDDK-05 & ÖDDK-06)',
            '6. Mağdur Öğrenci ve Görgü Tanığı İfade Tutanakları (ÖDDK-07 & ÖDDK-08)',
            '7. Öğrenci Yazılı Savunma ve Veli Bilgilendirme Tutanağı (ÖDDK-09 & ÖDDK-10)',
            '8. Okul Rehberlik (PDR) Servisi Vaka İnceleme Kanaat Raporu (ÖDDK-11)',
            '9. Kurul Toplantı Çağrısı, Uzlaşma Tutanağı ve Gerekçeli Karar (ÖDDK-12, 13, 14)',
            '10. İmzalı Veli Karar Tebligatı / Tebellüğ Pusulası (ÖDDK-15)',
            'Öğrencinin yaptırım sonrası süreçte okul kurallarına tam uyum sağladığı ve olumlu davranış geliştirdiği PDR ve sınıf rehber öğretmenince teyit edilmiştir.',
            'Yıl sonu Öğretmenler Kurulu / ŞÖK değerlendirmesiyle yaptırımın e-Okul / dosya kayıtlarından kaldırılması ve davranış puanının iadesi uygun görülmüştür.',
          ],
          defaultValue: [
            '1. Öğretmen Sözlü Uyarı ve Yapıcı Görüşme Tutanağı (ÖDDK-01)',
            '2. MEB EK-9 Öğrenci Olumlu Davranış Geliştirme Sözleşmesi (ÖDDK-02)',
            '4. Ayrıntılı Olay Tespit ve Güvenlik Kamerası İnceleme Tutanağı (ÖDDK-04)',
            '6. Mağdur Öğrenci ve Görgü Tanığı İfade Tutanakları (ÖDDK-07 & ÖDDK-08)',
            '7. Öğrenci Yazılı Savunma ve Veli Bilgilendirme Tutanağı (ÖDDK-09 & ÖDDK-10)',
            '8. Okul Rehberlik (PDR) Servisi Vaka İnceleme Kanaat Raporu (ÖDDK-11)',
            '9. Kurul Toplantı Çağrısı, Uzlaşma Tutanağı ve Gerekçeli Karar (ÖDDK-12, 13, 14)',
            '10. İmzalı Veli Karar Tebligatı / Tebellüğ Pusulası (ÖDDK-15)',
            'Öğrencinin yaptırım sonrası süreçte okul kurallarına tam uyum sağladığı ve olumlu davranış geliştirdiği PDR ve sınıf rehber öğretmenince teyit edilmiştir.',
            'Yıl sonu Öğretmenler Kurulu / ŞÖK değerlendirmesiyle yaptırımın e-Okul / dosya kayıtlarından kaldırılması ve davranış puanının iadesi uygun görülmüştür.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Belge Türü', _str(a, 'docMode')),
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Tarih / Dönem', '${_str(a, "date", _today())} — ${ctx.academicYear}'),
      ],
      composeBody: (a, ctx) {
        final isRemoval = _str(a, 'docMode').startsWith('1');
        return '''
${isRemoval ? 'YIL SONU YAPTIRIM / DİSİPLİN CEZASI KALDIRMA VE DAVRANIŞ İZLEME KARARI' : 'ÖDDK / DİSİPLİN SORUŞTURMA DOSYASI RESMİ DİZİ PUSULASI'}

Okulumuz ${_str(a, 'targetClass')} şubesi öğrencisi ${_str(a, 'student')} hakkında yürütülen davranış değerlendirme / disiplin dosyasına ilişkin kontrol ve sonuç maddeleri aşağıda kayıt altına alınmıştır:

${_numberedLines(_list(a, 'fileCheckItems'))}

${isRemoval ? 'SONUÇ KARARI:\nYukarıda belirtilen olumlu gelişim gözlemleri doğrultusunda öğrencinin almış olduğu yaptırım/disiplin cezasının ilgili yönetmelik hükümleri uyarınca kaldırılmasına (silinmesine) ve varsa düşülen davranış puanının iade edilmesine oy birliği ile karar verilmiştir.' : 'Yukarıda sıra numarasıyla listelenen evrakların tamamı eksiksiz olarak soruşturma dosyasında mevcut olup kurum arşivinde gizlilik derecesiyle muhafaza altına alınmıştır.'}''';
      },
      buildSigners: (a, ctx) => [
        DocSigner(
          name: ctx.vicePrincipals.isNotEmpty
              ? ctx.vicePrincipals.first.fullName
              : 'Kurul Başkanı',
          title: 'ÖDDK / Disiplin Kurulu Başkanı',
        ),
        if (ctx.counselors.isNotEmpty)
          DocSigner(
            name: ctx.counselors.first.fullName,
            title: 'Okul Rehber Öğretmeni / PDR',
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
