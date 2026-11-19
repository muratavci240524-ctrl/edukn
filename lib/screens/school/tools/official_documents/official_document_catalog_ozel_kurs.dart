import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../models/school/official_document_model.dart';

/// 5580 Sayılı Özel Öğretim Kurumları Kanunu, MEB Özel Öğretim Kurumları Yönetmeliği
/// (RG: 20/03/2012 - 28239) ve Özel Öğretim Kursları / Standartlar Yönergesi Evrakları
class OfficialDocumentCatalogOzelKurs {
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
        : 'Kurum / Okul Müdürü';
    if (prefix.isEmpty ||
        base.toUpperCase().contains(prefix.toUpperCase())) {
      return base;
    }
    return '$prefix / $base';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 12. KATEGORİ TANIMI (ÖZEL ÖĞRETİM KURUMLARI VE ÖZEL ÖĞRETİM KURSLARI)
  // ═══════════════════════════════════════════════════════════════════════════
  static const OfficialDocCategory category = OfficialDocCategory(
    id: 'ozel_ogretim_kurs_ozel',
    order: 13,
    title: '12. Özel Öğretim Kurumları ve Özel Öğretim Kursları Evrakları',
    subtitle:
        'Kayıt Sözleşmesi, Kıstelyevm İade, %3 Ücretsiz Öğrenci (EK-7), Bursluluk, Çalışma İzni, Ücret İlanı, Etüt & Denetim',
    audience: DocAudience.admin,
    icon: Icons.apartment_rounded,
    color: Color(0xFF9333EA),
    scopes: [DocRegulationScope.ozelOgretimKurs],
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // BAŞLIK 12 ŞABLONLARI: 5580 S.K. & ÖZEL ÖĞRETİM KURUMLARI / KURSLARI YÖNETMELİĞİ
  // ═══════════════════════════════════════════════════════════════════════════
  static final List<OfficialDocTemplate> templates = [
    // 12.1 MEB Standart Özel Okul / Özel Öğretim Kursu Kayıt Sözleşmesi
    OfficialDocTemplate(
      id: 'ozel_ogretim_kayit_sozlesmesi',
      code: '12.1',
      categoryId: 'ozel_ogretim_kurs_ozel',
      title: 'Özel Okul / Özel Öğretim Kursu Standart Öğrenci-Kursiyer Kayıt Sözleşmesi',
      subtitle:
          '5580 S.K. ve Yönetmelik Md. 53-55 uyumlu eğitim/bilim grubu sözleşmesi, ücret, indirim, taksit ve fesih şartları',
      legalBasis:
          '5580 Sayılı Kanun Md. 13 & MEB Özel Öğretim Kurumları Yönetmeliği Md. 53–56',
      scopes: const [DocRegulationScope.ozelOgretimKurs],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.officialLetter,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.description_outlined,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Sözleşme Düzenlenme Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'contractNo',
          label: 'Sözleşme Sıra No',
          type: DocFieldType.text,
          defaultValue: 'SZL-2026/001',
        ),
        const DocQuestionField(
          key: 'institutionType',
          label: 'Kurum / Program Türü',
          type: DocFieldType.dropdown,
          options: [
            'Özel Öğretim Kursu (Bilim Grubu Kurs Programı)',
            'Özel Okul (Anaokulu / İlkokul / Ortaokul / Lise)',
            'Özel Muhtelif Kurs / Yabancı Dil / Kişisel Gelişim Kursu',
            'Özel Öğrenci Etüt / Sosyal Etkinlik ve Gelişim Merkezi',
          ],
          defaultValue: 'Özel Öğretim Kursu (Bilim Grubu Kurs Programı)',
        ),
        const DocQuestionField(
          key: 'studentName',
          label: 'Öğrenci / Kursiyer Adı Soyadı ve T.C. Kimlik No',
          type: DocFieldType.text,
          hint: 'Örn: Elif YILDIRIM — T.C.: 12345678901',
          required: true,
        ),
        const DocQuestionField(
          key: 'parentInfo',
          label: 'Veli / Ödeyen Adı Soyadı, T.C. No ve Telefonu',
          type: DocFieldType.text,
          hint: 'Örn: Murat YILDIRIM — T.C.: 10987654321 — Tel: 05xx xxx xx xx',
        ),
        const DocQuestionField(
          key: 'programScope',
          label: 'Kayıt Olunan Sınıf / Bilim Grubu ve Toplam Ders Saati',
          type: DocFieldType.text,
          defaultValue:
              '12. Sınıf / Mezun Sayısal Bilim Grupları (Matematik, Fizik, Kimya, Biyoloji, Türkçe) — Toplam 540 Ders Saati',
        ),
        const DocQuestionField(
          key: 'announcedFee',
          label: 'MEB İlan Edilen Liste Eğitim Ücreti ve Uygulanan Burs/İndirim',
          type: DocFieldType.text,
          defaultValue: 'İlan Ücreti: ............... TL | Uygulanan İndirim/Burs: %....',
        ),
        const DocQuestionField(
          key: 'netFeeAndPlan',
          label: 'KDV Dahil Net Eğitim Ücreti, Ek Hizmetler ve Taksit Ödeme Planı',
          type: DocFieldType.multiline,
          defaultValue:
              'KDV Dahil Net Eğitim Ücreti: ............... TL\nYemek / Etüt / Yayın Hizmeti (İsteğe Bağlı): ............... TL\nÖdeme Şekli: Peşinat ............... TL + .... Eşit Taksit (Her ayın 5\'i ile 10\'u arası banka/POS yoluyla)',
        ),
        const DocQuestionField(
          key: 'founderRep',
          label: 'Kurucu Temsilcisi Adı Soyadı (Varsa)',
          type: DocFieldType.text,
          defaultValue: '',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Sözleşme No / Tarih', '${_str(a, "contractNo")} — ${_str(a, "date", _today())}'),
        MapEntry('Kurum Türü', _str(a, 'institutionType')),
        MapEntry('Öğrenci / Kursiyer', _str(a, 'studentName')),
        MapEntry('Veli / Yasal Temsilci', _str(a, 'parentInfo')),
        MapEntry('Program ve Süre', _str(a, 'programScope')),
      ],
      composeBody: (a, ctx) => '''
ÖZEL ÖĞRETİM KURUMLARI STANDART ÖĞRENCİ / KURSİYER KAYIT SÖZLEŞMESİ

MADDE 1 - TARAFLAR:
İşbu kayıt sözleşmesi; bir tarafta "${ctx.schoolName}" (Adres: ${ctx.address.isNotEmpty ? ctx.address : "${ctx.district}/${ctx.city}"}) ile diğer tarafta öğrenci/kursiyer (${_str(a, 'studentName')}) ve velisi/yasal temsilcisi (${_str(a, 'parentInfo')}) arasında 5580 sayılı Özel Öğretim Kurumları Kanunu ve MEB Özel Öğretim Kurumları Yönetmeliği hükümlerine uygun olarak akdedilmiştir.

MADDE 2 - EĞİTİM PROGRAMI VE SÜRESİ:
Öğrenci/kursiyer, ${ctx.academicYear} öğretim döneminde kurumumuz bünyesinde "${_str(a, 'programScope')}" programına kayıt olmuştur. Eğitim-öğretim faaliyetleri MEB onaylı çerçeve öğretim programları ve çalışma takvimine uygun yürütülür.

MADDE 3 - EĞİTİM ÜCRETİ, BURS/İNDİRİM VE ÖDEME ŞARTLARI:
• ${_str(a, 'announcedFee')}
• ${_str(a, 'netFeeAndPlan')}
İlan edilen ücretlerin üzerinde hiçbir ad altında ek ücret talep edilemez; tüm tahsilatlar resmi banka hesabı veya fatura/belge karşılığı yapılır.

MADDE 4 - AYRILMA, KAYIT İPTALİ VE ÜCRET İADESİ ESASLARI (YÖNETMELİK MD. 56):
a) Öğretim yılı / kurs programı başlamadan ayrılanlara, yıllık/toplam öğretim ücretinin yüzde onu (%10) dışındaki kısmı iade edilir.
b) Öğretim yılı / kurs programı başladıktan sonra ayrılanlara ise yıllık/toplam öğretim ücretinin yüzde onu (%10) ile öğrenim gördüğü günlere / ders saatlerine göre hesaplanan (kıstelyevm) miktarın dışındaki kısmı en geç bir ay içinde iade edilir.
c) Zorunlu nakil, resmi sağlık kurulu raporu veya kurumun kapanması gibi mevzuatta sayılan haklı hallerde %10 kesinti uygulanmaz.

MADDE 5 - TARAFLARIN HAK VE YÜKÜMLÜLÜKLERİ:
Kurum; güvenli, hijyenik ve MEB Standartlar Yönergesine uygun fiziki ortam sağlamak, yoklama ve gelişim bilgisini veliyle düzenli paylaşmakla yükümlüdür. Öğrenci/kursiyer ve veli; kurum iç disiplin kurallarına, devam-devamsızlık esaslarına ve ödeme vadelerine uymayı kabul ve taahhüt eder.

İşbu 5 (beş) maddelik sözleşme ${_str(a, 'date', _today())} tarihinde iki (2) nüsha olarak tanzim ve imza edilmiş olup bir nüshası elden veliye/kursiyere teslim edilmiştir.''',
      buildSigners: (a, ctx) {
        final founder = _str(a, 'founderRep');
        return [
          DocSigner(
            name: _str(a, 'parentInfo').split('—').first.trim().isNotEmpty
                ? _str(a, 'parentInfo').split('—').first.trim()
                : 'Veli / Reşit Kursiyer',
            title: 'Bir Nüshasını Elden Aldım (Veli / Kursiyer)',
          ),
          if (founder.isNotEmpty)
            DocSigner(name: founder, title: 'Kurucu / Kurucu Temsilcisi'),
          DocSigner(
            name: ctx.principalName,
            title: _authorityTitle(ctx),
            isApproval: founder.isEmpty,
          ),
        ];
      },
    ),

    // 12.2 Kayıt İptali, Kurumdan Ayrılma ve Kıstelyevm Ücret İade Hesaplama Tutanağı
    OfficialDocTemplate(
      id: 'ozel_ogretim_kayit_iptal_ucret_iade',
      code: '12.2',
      categoryId: 'ozel_ogretim_kurs_ozel',
      title: 'Kayıt İptali, Kurumdan Ayrılma ve Kıstelyevm Ücret İade Mutabakat Tutanağı',
      subtitle:
          'Yönetmelik Md. 56 uyarınca %10 kesinti + öğrenim görülen gün/saat hesabı, iade IBAN mutabakatı ve e-Özel silme formu',
      legalBasis: 'MEB Özel Öğretim Kurumları Yönetmeliği Md. 56',
      scopes: const [DocRegulationScope.ozelOgretimKurs],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.calculate_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Ayrılış / İptal Başvuru Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'studentName',
          label: 'Öğrenci / Kursiyer Adı Soyadı ve T.C. No',
          type: DocFieldType.text,
          required: true,
        ),
        const DocQuestionField(
          key: 'parentName',
          label: 'Başvuru Sahibi Veli / Kursiyer Adı Soyadı',
          type: DocFieldType.text,
        ),
        const DocQuestionField(
          key: 'cancelReason',
          label: 'Ayrılma Zamanı ve Mevzuat Kapsamı (Md. 56)',
          type: DocFieldType.dropdown,
          options: [
            'Eğitim/Kurs Dönemi Başlamadan Ayrılma (%10 Kesinti Uygulanır)',
            'Eğitim/Kurs Dönemi Başladıktan Sonra Ayrılma (%10 + Görülen Gün/Ders Saati Bedeli Düşülür)',
            'İl Dışı İkamet Değişikliği / Resmi Sağlık Kurulu Raporu Nedeniyle Haklı Ayrılma (%10 Kesintisiz)',
          ],
          defaultValue:
              'Eğitim/Kurs Dönemi Başladıktan Sonra Ayrılma (%10 + Görülen Gün/Ders Saati Bedeli Düşülür)',
        ),
        const DocQuestionField(
          key: 'financialCalc',
          label: 'Sözleşme Tutarı, Tahsil Edilen Tutar, Yasal Kesinti ve İade Edilecek Net Tutar',
          type: DocFieldType.multiline,
          defaultValue:
              '1. Sözleşme Net Bedeli: ............... TL\n2. Bugüne Kadar Tahsil Edilen: ............... TL\n3. Yasal %10 + Öğrenim Görülen Gün/Saat Kıstelyevm Tutarı: ............... TL\n4. Veliye İade Edilecek / Mahsup Edilecek Net Tutar: ............... TL',
        ),
        const DocQuestionField(
          key: 'ibanInfo',
          label: 'İade Yapılacak Banka ve Veli IBAN Bilgisi',
          type: DocFieldType.text,
          defaultValue: 'TR.. .... .... .... .... .... .. (Sözleşme sahibi veli hesabına)',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('İşlem Tarihi', _str(a, 'date', _today())),
        MapEntry('Öğrenci / Kursiyer', _str(a, 'studentName')),
        MapEntry('Ayrılma Statüsü', _str(a, 'cancelReason')),
        MapEntry('İade IBAN', _str(a, 'ibanInfo')),
      ],
      composeBody: (a, ctx) => '''
KAYIT İPTALİ, İLİŞİK KESME VE ÜCRET İADE HESAPLAMA TUTANAĞI

Kurumumuzda kayıtlı bulunan ${_str(a, 'studentName')} adlı öğrenci/kursiyerin kaydının veli/kursiyer yazılı talebi üzerine "${_str(a, 'cancelReason')}" kapsamında iptal edilmesi ve MEBBİS (e-Özel / e-Okul) sisteminden kaydının düşürülmesi kararlaştırılmıştır.

MEB ÖZEL ÖĞRETİM KURUMLARI YÖNETMELİĞİ MD. 56 HESAP DÖKÜMÜ:
${_str(a, 'financialCalc')}

Yukarıda hesaplanan iade/mahsup tutarı hususunda taraflar tam mutabakata varmış olup, iade ödemesinin yasal süresi içinde yukarıda belirtilen IBAN hesabına aktarılması ve varsa vadesi gelmemiş senet/çek/ödeme talimatlarının iptal edilerek veliye teslim edilmesi imza altına alınmıştır.''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(a, 'parentName', 'Veli / Kursiyer'),
          title: 'Mutabık Kalan Veli / Kursiyer',
        ),
        const DocSigner(
          name: 'Muhasebe / Mali İşler Yetkilisi',
          title: 'Hesap Kontrol ve İade Sorumlusu',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'ONAY'),
          isApproval: true,
        ),
      ],
    ),

    // 12.3 Ücretsiz Okuyacak Öğrenci / Kursiyer (%3 Kanuni Kontenjan & EK-7) Komisyon Tutanağı
    OfficialDocTemplate(
      id: 'ozel_ogretim_ucretsiz_ogrenci_ek7_komisyonu',
      code: '12.3',
      categoryId: 'ozel_ogretim_kurs_ozel',
      title: 'Ücretsiz Okuyacak Öğrenci / Kursiyer (%3 Kontenjan & EK-7) Değerlendirme Komisyonu Tutanağı',
      subtitle:
          '5580 S.K. Md. 13 ve Yönetmelik Md. 57-61 uyarınca şehit/gazi önceliği ve EK-7 puanlama asil/yedek tespit tutanağı',
      legalBasis:
          '5580 Sayılı Kanun Md. 13 & MEB Özel Öğretim Kurumları Yönetmeliği Md. 57–61 (EK-7 / EK-8)',
      scopes: const [DocRegulationScope.ozelOgretimKurs],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.volunteer_activism_outlined,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Değerlendirme Komisyonu Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'quotaSummary',
          label: 'Kayıtlı Toplam Öğrenci/Kursiyer Sayısı ve %3 Zorunlu Ücretsiz Kontenjan',
          type: DocFieldType.text,
          defaultValue: 'Toplam Öğrenci/Kursiyer: 200 | En Az %3 Zorunlu Ücretsiz Kontenjan: 6 Öğrenci',
        ),
        const DocQuestionField(
          key: 'selectedList',
          label: 'Ücretsiz Okuma Hakkı Kazanan Asil ve Yedek Öğrenci Özeti',
          type: DocFieldType.multiline,
          defaultValue:
              '1. Öncelikli Başvurular (Şehit/Vazife Malulü ve Korunma Kararı Olan Çocuklar): Eksiksiz yerleştirilmiştir.\n2. Genel Başvurular (EK-7 Formu ve EK-8 Değerlendirme Kılavuzu Puan Sıralaması): En yüksek puandan başlanarak asil ve yedek liste oluşturulmuştur.',
        ),
        const DocQuestionField(
          key: 'members',
          label: 'Değerlendirme Komisyonu Üyeleri (Kurucu Temsilcisi, Müdür ve 2 Öğretmen)',
          type: DocFieldType.multiStaffSelect,
        ),
        const DocQuestionField(
          key: 'decisions',
          label: 'Alınan Komisyon Kararları',
          type: DocFieldType.multiCheck,
          options: [
            '5580 sayılı Kanunun 13 üncü maddesi gereğince kurumumuzda öğrenim gören öğrenci/kursiyer sayısının %3\'ünden az olmamak üzere ücretsiz öğrenci kontenjanının eksiksiz kullandırılmasına karar verildi.',
            'Harp veya vazife malulü sayılanların ilk ve ortaöğretim çağındaki çocukları ile 2828 ve 5395 sayılı Kanunlar kapsamında korunma, bakım veya barınma kararı verilen çocukların öncelikli olarak ücretsiz kontenjana yerleştirilmesine karar verildi.',
            'Diğer başvuruların Yönetmelik EK-7 "Ücretsiz Okuyacak Öğrenci ve Kursiyer Başvuru Formu" beyanları ve resmi gelir belgeleri üzerinden EK-8 puanlama cetveline göre sıralanmasına karar verildi.',
            'Kesinleşen ücretsiz öğrenci/kursiyer listesinin süresi içinde MEBBİS Özel Öğretim Kurumları Modülüne işlenmesine ve İlçe Milli Eğitim Müdürlüğüne sunulmasına karar verildi.',
            'Gerçeğe aykırı beyanda bulunduğu sonradan tespit edilenlerin ücretsiz okuma hakkının Yönetmelik Md. 60 uyarınca iptal edileceğinin velilere tebliğine karar verildi.',
          ],
          defaultValue: [
            '5580 sayılı Kanunun 13 üncü maddesi gereğince kurumumuzda öğrenim gören öğrenci/kursiyer sayısının %3\'ünden az olmamak üzere ücretsiz öğrenci kontenjanının eksiksiz kullandırılmasına karar verildi.',
            'Harp veya vazife malulü sayılanların ilk ve ortaöğretim çağındaki çocukları ile 2828 ve 5395 sayılı Kanunlar kapsamında korunma, bakım veya barınma kararı verilen çocukların öncelikli olarak ücretsiz kontenjana yerleştirilmesine karar verildi.',
            'Diğer başvuruların Yönetmelik EK-7 "Ücretsiz Okuyacak Öğrenci ve Kursiyer Başvuru Formu" beyanları ve resmi gelir belgeleri üzerinden EK-8 puanlama cetveline göre sıralanmasına karar verildi.',
            'Kesinleşen ücretsiz öğrenci/kursiyer listesinin süresi içinde MEBBİS Özel Öğretim Kurumları Modülüne işlenmesine ve İlçe Milli Eğitim Müdürlüğüne sunulmasına karar verildi.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Komisyon', 'Ücretsiz Okuyacak Öğrenci/Kursiyer Değerlendirme Komisyonu'),
        MapEntry('Tarih / Dönem', '${_str(a, "date", _today())} — ${ctx.academicYear}'),
        MapEntry('Kontenjan Hesabı', _str(a, 'quotaSummary')),
      ],
      composeBody: (a, ctx) => '''
ÜCRETSİZ OKUYACAK ÖĞRENCİ VE KURSİYER DEĞERLENDİRME KOMİSYONU TUTANAĞI (MD. 57-61)

DEĞERLENDİRME ÖZETİ:
${_str(a, 'selectedList')}

KOMİSYON KARARLARI:
${_numberedLines(_list(a, 'decisions'))}

İşbu tutanak ve eki puanlama cetvelleri denetime hazır şekilde kurum ücretsiz öğrenci dosyasında muhafaza edilmek üzere imza altına alınmıştır.''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(4))
          DocSigner(name: m, title: 'Değerlendirme Komisyonu Üyesi'),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'Komisyon Başkanı'),
          isApproval: true,
        ),
      ],
    ),

    // 12.4 Kurumsal Bursluluk / Kabul Sınavı Komisyon Kararı ve İlçe MEM Bildirim Yazısı
    OfficialDocTemplate(
      id: 'ozel_ogretim_bursluluk_sinavi_komisyonu',
      code: '12.4',
      categoryId: 'ozel_ogretim_kurs_ozel',
      title: 'Bursluluk Sınavı Şartnamesi, Komisyon Kararı ve İlçe MEM Bildirim Yazısı',
      subtitle:
          'Yönetmelik Md. 62 uyarınca ücretsiz sınav taahhüdü, burs oranları (%3\'ten hariç) ve İlçe MEM bildirim yazısı',
      legalBasis: 'MEB Özel Öğretim Kurumları Yönetmeliği Md. 62',
      scopes: const [DocRegulationScope.ozelOgretimKurs],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.officialLetter,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.emoji_events_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Yazı / Karar Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'docNo',
          label: 'Sayı',
          type: DocFieldType.text,
          defaultValue: 'ÖÖK-BRS / 2026-04',
        ),
        const DocQuestionField(
          key: 'examDates',
          label: 'Bursluluk Sınavı Uygulama Tarih(ler)i ve Seansları',
          type: DocFieldType.text,
          defaultValue: '10-11 Ocak 2027 (Seanslar: 10:00 ve 14:00)',
        ),
        const DocQuestionField(
          key: 'targetGrades',
          label: 'Sınava Katılacak Sınıf Düzeyleri',
          type: DocFieldType.text,
          defaultValue: '4, 5, 6, 7, 8, 9, 10 ve 11. Sınıf Öğrencileri',
        ),
        const DocQuestionField(
          key: 'scholarshipScale',
          label: 'Verilecek Başarı Bursu Dilimleri ve Öğrenci Kontenjanları',
          type: DocFieldType.multiline,
          defaultValue:
              'Her sınıf düzeyinde; 1-3. öğrencilere %100 Eğitim Bursu, 4-10. öğrencilere %75, 11-25. öğrencilere %50, 26-50. öğrencilere %25 Başarı Bursu verilecektir.',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Sayı / Tarih', '${_str(a, "docNo")} — ${_str(a, "date", _today())}'),
        MapEntry('Konu', 'Kurumsal Bursluluk Sınavı Uygulama ve Burs Şartları Bildirimi'),
        MapEntry('Sınav Tarihleri', _str(a, 'examDates')),
        MapEntry('Kapsanan Sınıflar', _str(a, 'targetGrades')),
      ],
      composeBody: (a, ctx) => '''
${ctx.district.isNotEmpty ? "${ctx.district.toUpperCase()} " : ""}İLÇE MİLLİ EĞİTİM MÜDÜRLÜĞÜNE
(Özel Öğretim Kurumları Şubesi)

MEB Özel Öğretim Kurumları Yönetmeliğinin 62 nci maddesi hükümleri çerçevesinde kurumumuz "${ctx.schoolName}" bünyesinde gelecek eğitim-öğretim dönemi için başarılı öğrencileri desteklemek amacıyla bursluluk sınavı düzenlenmesi planlanmıştır.

BURSLULUK SINAVI VE BURS UYGULAMA ESASLARI:
1. Sınav Tarih ve Seansları: ${_str(a, 'examDates')}
2. Katılımcı Sınıf Seviyeleri: ${_str(a, 'targetGrades')}
3. Sınav Ücreti: Sınava başvuran aday öğrencilerden başvuru veya sınav adı altında hiçbir ücret alınmayacaktır.
4. Burs Oranları ve Kapsamı:
${_str(a, 'scholarshipScale')}
5. Mevzuat Uyumu: Bu sınav sonucunda verilecek eğitim bursları, 5580 sayılı Kanunun 13 üncü maddesi gereğince ayrılan %3 zorunlu ücretsiz öğrenci kontenjanından tamamen bağımsız ve ek olarak uygulanacaktır. Tanıtım ve duyurularda yanıltıcı ifadelere ve öğrenci kişisel verilerinin izinsiz paylaşımına kesinlikle yer verilmeyecektir.

Sınav şartnamesi ve komisyon kararımız ekte sunulmuş olup bilgilerinize ve gereğine arz ederim.''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx),
          isApproval: true,
        ),
      ],
    ),

    // 12.5 Kurum Başarı / Kurucu Bursu Tahsis Belgesi ve Veli Burs Taahhütnamesi
    OfficialDocTemplate(
      id: 'ozel_ogretim_burs_taahhutnamesi',
      code: '12.5',
      categoryId: 'ozel_ogretim_kurs_ozel',
      title: 'Öğrenci / Kursiyer Burs Tahsis Belgesi ve Burs Devamlılık Taahhütnamesi',
      subtitle:
          'Tanımlanan başarı, spor/sanat veya kurucu bursunun kapsamı, süresi ve devam şartlarını içeren resmi belge',
      legalBasis: 'MEB Özel Öğretim Kurumları Yönetmeliği Md. 62–63',
      scopes: const [DocRegulationScope.ozelOgretimKurs],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.card_membership_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Düzenlenme Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'studentName',
          label: 'Burs Tahsis Edilen Öğrenci / Kursiyer Adı Soyadı ve Sınıfı',
          type: DocFieldType.text,
          required: true,
        ),
        const DocQuestionField(
          key: 'scholarshipType',
          label: 'Burs Türü ve Oranı',
          type: DocFieldType.text,
          defaultValue: '%50 Akademik Başarı Bursu (Yalnızca Öğrenim Ücretini Kapsar)',
        ),
        const DocQuestionField(
          key: 'duration',
          label: 'Bursun Geçerlilik Süresi',
          type: DocFieldType.dropdown,
          options: [
            'Kayıtlı Bulunduğu Öğretim Yılı / Kurs Dönemi Boyunca (1 Yıl)',
            'Bulunduğu Öğrenim Kademesi Sonuna Kadar (Mezuniyete Kadar)',
          ],
          defaultValue:
              'Kayıtlı Bulunduğu Öğretim Yılı / Kurs Dönemi Boyunca (1 Yıl)',
        ),
        const DocQuestionField(
          key: 'parentName',
          label: 'Veli Adı Soyadı',
          type: DocFieldType.text,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Öğrenci / Kursiyer', _str(a, 'studentName')),
        MapEntry('Tahsis Edilen Burs', _str(a, 'scholarshipType')),
        MapEntry('Geçerlilik Süresi', _str(a, 'duration')),
        MapEntry('Tarih', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
KURUMSAL BURS TAHSİS BELGESİ VE VELİ TAAHHÜTNAMESİ

1. Kurumumuz Burs Değerlendirme Komisyonu kararıyla ${_str(a, 'studentName')} adlı öğrenci/kursiyerimize "${_str(a, 'scholarshipType')}" tahsis edilmiştir.
2. Söz konusu burs "${_str(a, 'duration')}" süresince geçerlidir; aksi yazılı olarak belirtilmedikçe yemek, servis, kıyafet ve yayın giderlerini kapsamaz.
3. MEB Özel Öğretim Kurumları Yönetmeliğinin 62 ve 63 üncü maddeleri uyarınca burs verilen öğrencilerden bursun geçerli olduğu süre içinde başarı şartı nedeniyle burs kesintisi yapılamaz; ancak okul değiştirme/örgün eğitim dışına çıkarma disiplin cezası alınması veya kurumdan kendi isteğiyle ayrılma durumunda sözleşme hükümleri uygulanır.
4. İşbu belge kayıt sözleşmesinin ayrılmaz eki olarak iki nüsha düzenlenmiştir.''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(a, 'parentName', 'Öğrenci Velisi'),
          title: 'Okudum, Tebellüğ Ettim (Veli)',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'Kurum Onayı'),
          isApproval: true,
        ),
      ],
    ),

    // 12.6 Eğitim Personeli Çalışma İzin Onayı Teklifi, Göreve Başlama ve Ayrılış Bildirim Yazısı
    OfficialDocTemplate(
      id: 'ozel_ogretim_personel_calisma_izni_yazisi',
      code: '12.6',
      categoryId: 'ozel_ogretim_kurs_ozel',
      title: 'Eğitim Personeli Çalışma İzin Onayı Teklifi / Göreve Başlama / Ayrılış Üst Yazısı',
      subtitle:
          '5580 S.K. Md. 8-9 uyarınca İlçe MEM\'e sunulan Çalışma İzin Teklifi, Göreve Başlama veya Ayrılış Bildirimi',
      legalBasis:
          '5580 Sayılı Kanun Md. 8–9 & MEB Özel Öğretim Kurumları Yönetmeliği Md. 25–43',
      scopes: const [DocRegulationScope.ozelOgretimKurs],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.officialLetter,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.assignment_ind_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Resmi Yazı Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'docNo',
          label: 'Sayı',
          type: DocFieldType.text,
          defaultValue: 'ÖÖK-PER / 2026-12',
        ),
        const DocQuestionField(
          key: 'actionType',
          label: 'İlçe MEM\'e Sunulacak İşlem Türü',
          type: DocFieldType.dropdown,
          options: [
            '1) Eğitim Personeli Çalışma İzin Onayı Teklif Yazısı (Yeni Atama / Yenileme)',
            '2) Çalışma İzni Onaylanan Personelin Göreve Başlama Bildirimi',
            '3) İstifa / Sözleşme Feshi / Süre Bitimi Görevden Ayrılış Bildirimi',
          ],
          defaultValue:
              '1) Eğitim Personeli Çalışma İzin Onayı Teklif Yazısı (Yeni Atama / Yenileme)',
        ),
        const DocQuestionField(
          key: 'staffInfo',
          label: 'Personelin Adı Soyadı ve T.C. Kimlik Numarası',
          type: DocFieldType.text,
          hint: 'Örn: Selin DEMİR — T.C.: 23456789012',
          required: true,
        ),
        const DocQuestionField(
          key: 'dutyAndBranch',
          label: 'Atanacağı / Yürüttüğü Görev Unvanı, Alanı ve Haftalık Ders Saati',
          type: DocFieldType.text,
          defaultValue: 'Asıl Görevli Matematik Öğretmeni — Haftalık 20 Ders Saati + 20 Saat Ek Ders',
        ),
        DocQuestionField(
          key: 'actionDate',
          label: 'Sözleşme / Başlama veya Ayrılış Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Sayı / Tarih', '${_str(a, "docNo")} — ${_str(a, "date", _today())}'),
        MapEntry('İşlem Konusu', _str(a, 'actionType')),
        MapEntry('Personel Kimlik', _str(a, 'staffInfo')),
        MapEntry('Görev ve Alan', _str(a, 'dutyAndBranch')),
      ],
      composeBody: (a, ctx) {
        final mode = _str(a, 'actionType');
        final staff = _str(a, 'staffInfo');
        final duty = _str(a, 'dutyAndBranch');
        final actDate = _str(a, 'actionDate', _today());
        final districtHeader = ctx.district.isNotEmpty
            ? '${ctx.district.toUpperCase()} İLÇE MİLLİ EĞİTİM MÜDÜRLÜĞÜNE'
            : 'İLÇE MİLLİ EĞİTİM MÜDÜRLÜĞÜNE';

        if (mode.startsWith('2')) {
          return '''
$districtHeader
(Özel Öğretim Kurumları Şubesi)

Müdürlüğünüz / Valilik Makamının çalışma izin onayına istinaden kurumumuz "${ctx.schoolName}" bünyesine "$duty" olarak atanan $staff, $actDate tarihi itibarıyla kurumumuzdaki görevine fiilen başlamış olup SGK işe giriş bildirgesi ve MEBBİS Özel Öğretim Kurumları Modülü kayıt işlemleri tamamlanmıştır.

Bilgilerinize ve gereğine arz ederim.

EK: SGK İşe Giriş Bildirgesi ve İmzalı Göreve Başlama Tutanağı (1 Sayfa)''';
        }
        if (mode.startsWith('3')) {
          return '''
$districtHeader
(Özel Öğretim Kurumları Şubesi)

Kurumumuz "${ctx.schoolName}" bünyesinde "$duty" olarak görev yapmakta olan $staff, $actDate tarihi itibarıyla (istifa / karşılıklı fesih / sözleşme süresi bitimi nedeniyle) kurumumuzdaki görevinden ayrılmıştır.

5580 sayılı Özel Öğretim Kurumları Kanunu ve ilgili Yönetmeliğin 43 üncü maddesi gereğince ilgilinin çalışma izninin iptali ve MEBBİS kayıtlarından ilişiğinin kesilmesi hususunda bilgilerinizi ve gereğini arz ederim.

EK: Dilekçe / Fesih Bildirimi ve SGK İşten Ayrılış Bildirgesi''';
        }
        return '''
$districtHeader
(Özel Öğretim Kurumları Şubesi)

5580 sayılı Özel Öğretim Kurumları Kanununun 8 inci maddesi ve MEB Özel Öğretim Kurumları Yönetmeliğinin 25-27 nci maddeleri uyarınca; kurumumuz "${ctx.schoolName}" bünyesinde "$duty" görevinde çalıştırılmak üzere iş sözleşmesi imzalanan $staff adına Çalışma İzin Onayı düzenlenmesi için gerekli atama dosyası MEBBİS modülüne işlenmiş ve ekte sunulmuştur.

Gereğini bilgilerinize arz ederim.

EKLER:
1. MEB Standart İş Sözleşmesi (3 Nüsha)
2. Diploma / Pedagojik Formasyon Onaylı Örneği
3. Adli Sicil ve Arşiv Kaydı Belgesi
4. Görev Yapmasına Engel Olmadığına Dair Sağlık Raporu ve SGK Hizmet Dökümü''';
      },
      buildSigners: (a, ctx) => [
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx),
          isApproval: true,
        ),
      ],
    ),

    // 12.7 Yıllık Eğitim / Kurs Ücret Tespit ve İlan Tutanağı (Mayıs Dönemi)
    OfficialDocTemplate(
      id: 'ozel_ogretim_yillik_ucret_ilan_tutanagi',
      code: '12.7',
      categoryId: 'ozel_ogretim_kurs_ozel',
      title: 'Yıllık Eğitim / Kurs Ücretlerinin Tespiti ve Kamuoyu İlan Tutanağı (Md. 53-54)',
      subtitle:
          'Mayıs ayı sonuna kadar belirlenen gelecek yıl kademe/grup ücretleri, indirim kalemleri ve MEBBİS ilan tutanağı',
      legalBasis: 'MEB Özel Öğretim Kurumları Yönetmeliği Md. 53–54',
      scopes: const [DocRegulationScope.ozelOgretimKurs],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.price_check_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Ücret Tespit ve İlan Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'targetYear',
          label: 'Ücretlerin Geçerli Olacağı Öğretim Yılı',
          type: DocFieldType.text,
          defaultValue: '2027-2028 Eğitim ve Öğretim Yılı',
        ),
        const DocQuestionField(
          key: 'feeTableText',
          label: 'İlan Edilen Kademe / Bilim Grubu Yıllık Ücret Tablosu (KDV Dahil)',
          type: DocFieldType.multiline,
          defaultValue:
              '• Ara Sınıflar Devam Öğrencileri: MEB Yönetmeliği Md. 53 yasal artış oranı sınırları dahilinde belirlenmiştir.\n• Başlangıç Sınıfları / Yeni Kayıt Kurs Programları: ............... TL (KDV Dahil)\n• İsteğe Bağlı Ek Hizmetler (Yemek / Kahvaltı / Etüt / Yayın): ............... TL',
        ),
        const DocQuestionField(
          key: 'discountRules',
          label: 'Uygulanacak Kurumsal İndirim Oranları',
          type: DocFieldType.text,
          defaultValue:
              'Peşin Ödeme İndirimi: %10 | Kardeş İndirimi: %10 | Kamu / Eğitim Çalışanı İndirimi: %10',
        ),
        const DocQuestionField(
          key: 'founderName',
          label: 'Kurucu / Kurucu Temsilcisi Adı Soyadı',
          type: DocFieldType.text,
          defaultValue: 'Kurucu Temsilcisi',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Geçerlilik Dönemi', _str(a, 'targetYear')),
        MapEntry('Tespit ve İlan Tarihi', _str(a, 'date', _today())),
        MapEntry('İndirim Kalemleri', _str(a, 'discountRules')),
      ],
      composeBody: (a, ctx) => '''
ÖZEL ÖĞRETİM KURUMLARI YILLIK ÜCRET TESPİT VE İLAN TUTANAĞI

5580 sayılı Özel Öğretim Kurumları Kanununun 12 ve 13 üncü maddeleri ile MEB Özel Öğretim Kurumları Yönetmeliğinin 53 ve 54 üncü maddeleri hükümleri uyarınca; kurumumuz "${ctx.schoolName}" bünyesinde "${_str(a, 'targetYear')}" döneminde uygulanacak öğrenim/kurs ücretleri aşağıda tespit ve ilan edilmiştir:

1. ÜCRET TARİFESİ:
${_str(a, 'feeTableText')}

2. İNDİRİM UYGULAMALARI:
${_str(a, 'discountRules')}

3. MEBBİS BİLDİRİMİ VE İLAN:
Belirlenen ücretlerin yasal süresi içinde MEBBİS Özel Öğretim Kurumları Modülüne işlenmesine, bir örneğinin İlçe Milli Eğitim Müdürlüğüne sunulmasına ve kurum ilan panosu ile resmi internet sayfasında veli/kursiyerlerin görebileceği şekilde yayınlanmasına karar verilmiştir.''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(a, 'founderName', 'Kurucu Temsilcisi'),
          title: 'Kurucu / Kurucu Temsilcisi',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx),
          isApproval: true,
        ),
      ],
    ),

    // 12.8 Özel Öğretim Kursu Bilim Grubu Programı, 16 Kişilik Kontenjan ve Seviye/Grup Tutanağı
    OfficialDocTemplate(
      id: 'ozel_kurs_bilim_grubu_seviye_tutanagi',
      code: '12.8',
      categoryId: 'ozel_ogretim_kurs_ozel',
      title: 'Özel Öğretim Kursu Bilim Grubu Planlama, Kontenjan ve Seviye Tespit Tutanağı',
      subtitle:
          'MEB onaylı bilim grubu programları, azami 16 kişilik derslik kontenjan uyumu ve grup/kur yerleştirme tutanağı',
      legalBasis:
          'MEB Özel Öğretim Kurumları Yönetmeliği & Özel Öğretim Kursları Çerçeve Programı',
      scopes: const [DocRegulationScope.ozelOgretimKurs],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.groups_3_rounded,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Toplantı / Planlama Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'scienceGroups',
          label: 'Kurumda Uygulanan MEB Onaylı Bilim Grupları',
          type: DocFieldType.text,
          defaultValue:
              'Türk Dili ve Edebiyatı, Matematik, Fizik, Kimya, Biyoloji, Tarih, Coğrafya',
        ),
        const DocQuestionField(
          key: 'members',
          label: 'Zümre / Grup Planlama Öğretmenleri',
          type: DocFieldType.multiStaffSelect,
        ),
        const DocQuestionField(
          key: 'decisions',
          label: 'Alınan Grup Planlama ve Mevzuat Kararları',
          type: DocFieldType.multiCheck,
          options: [
            'Kurum açma izninde onaylı bulunan bilim grubu çerçeve programları dışında hiçbir ders veya faaliyete yer verilmemesine karar verildi.',
            'Özel Öğretim Kurumları Standartlar Yönergesi uyarınca derslik kontenjanlarının yerleşim planındaki kapasiteyi ve azami 16 kursiyer sınırını kesinlikle aşmayacak şekilde oluşturulmasına karar verildi.',
            'Hazırbulunuşluk ve seviye belirleme uygulaması sonuçlarına göre öğrencilerin öğrenme hızlarına uygun homojen gruplara yerleştirilmesine ve her grup için MEBBİS ders programının tanımlanmasına karar verildi.',
            'Haftalık ders programlarının ve görevli öğretmen çalışma izinli isim listelerinin her derslik kapısına asılmasına, kurs defterlerinin günlük işlenmesine karar verildi.',
            'Üst üste devamsızlık yapan kursiyerlerin velilerinin aynı gün SMS/telefon yoluyla bilgilendirilmesine ve eksik konular için birebir soru çözüm / etüt randevusu oluşturulmasına karar verildi.',
          ],
          defaultValue: [
            'Kurum açma izninde onaylı bulunan bilim grubu çerçeve programları dışında hiçbir ders veya faaliyete yer verilmemesine karar verildi.',
            'Özel Öğretim Kurumları Standartlar Yönergesi uyarınca derslik kontenjanlarının yerleşim planındaki kapasiteyi ve azami 16 kursiyer sınırını kesinlikle aşmayacak şekilde oluşturulmasına karar verildi.',
            'Hazırbulunuşluk ve seviye belirleme uygulaması sonuçlarına göre öğrencilerin öğrenme hızlarına uygun homojen gruplara yerleştirilmesine ve her grup için MEBBİS ders programının tanımlanmasına karar verildi.',
            'Haftalık ders programlarının ve görevli öğretmen çalışma izinli isim listelerinin her derslik kapısına asılmasına, kurs defterlerinin günlük işlenmesine karar verildi.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Onaylı Bilim Grupları', _str(a, 'scienceGroups')),
        MapEntry('Planlama Tarihi', '${_str(a, "date", _today())} — ${ctx.academicYear}'),
      ],
      composeBody: (a, ctx) => '''
ÖZEL ÖĞRETİM KURSU BİLİM GRUBU VE SEVİYE GRUPLARI PLANLAMA TUTANAĞI

${ctx.academicYear} öğretim döneminde "${ctx.schoolName}" bünyesinde eğitim alacak öğrenci/kursiyerlerin MEB Özel Öğretim Kursları Çerçeve Programına uygun grup, kontenjan ve akademik takip esasları aşağıda kararlaştırılmıştır:

ALINAN KARARLAR:
${_numberedLines(_list(a, 'decisions'))}''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(5))
          DocSigner(name: m, title: 'Bilim Grubu Öğretmeni'),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'Kurum Müdürü / ONAY'),
          isApproval: true,
        ),
      ],
    ),

    // 12.9 Kursiyer / Öğrenci Birebir Etüt ve Akademik Telafi İmza Çizelgesi
    OfficialDocTemplate(
      id: 'ozel_kurs_birebir_etut_imza_cizelgesi',
      code: '12.9',
      categoryId: 'ozel_ogretim_kurs_ozel',
      title: 'Kursiyer / Öğrenci Birebir Etüt, Soru Çözüm ve Telafi Katılım İmza Çizelgesi',
      subtitle:
          'Deneme sınavı sonrası eksik kazanımlar için planlanan birebir/grup etüt yoklama ve öğrenci imza tablosu',
      legalBasis:
          'Özel Öğretim Kurumları Yönetmeliği & Kurumsal Akademik Takip Yönergesi',
      scopes: const [
        DocRegulationScope.ozelOgretimKurs,
        DocRegulationScope.ortakMevzuat,
      ],
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.circularSignatureTable,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.edit_calendar_rounded,
      customStudentTableHeaders: const [
        'S.No',
        'Grup / No',
        'Öğrenci / Kursiyer Adı',
        'Branş / Eksik Kazanım Konusu',
        'Tarih & Saat',
        'Katılım İmzası',
      ],
      customStudentRowBuilder: (i, s, a) => [
        '${i + 1}',
        '${s.className} / ${s.studentNo}',
        s.fullName,
        (a['studyTopic'] ?? '').toString(),
        (a['dateAndTime'] ?? '').toString(),
        '',
      ],
      questions: [
        const DocQuestionField(
          key: 'targetClasses',
          label: 'Etüde Alınan Grup / Şube Seçimi',
          type: DocFieldType.multiClassSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'branch',
          label: 'Etüt Dersi / Bilim Grubu',
          type: DocFieldType.branchSelect,
        ),
        const DocQuestionField(
          key: 'studyTopic',
          label: 'Çalışılan Eksik Konu / Kazanım Başlığı',
          type: DocFieldType.text,
          defaultValue: 'Deneme Analizi Eksik Kazanım Telafisi',
        ),
        DocQuestionField(
          key: 'dateAndTime',
          label: 'Uygulama Tarihi ve Saati',
          type: DocFieldType.text,
          defaultValue: '${_today()} (16:30 - 17:50)',
        ),
        const DocQuestionField(
          key: 'teacher',
          label: 'Etüdü Yapan Öğretmen',
          type: DocFieldType.staffSelect,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Ders / Bilim Grubu', _str(a, 'branch', 'Genel')),
        MapEntry('Konu / Kazanım', _str(a, 'studyTopic')),
        MapEntry('Tarih ve Saat', _str(a, 'dateAndTime')),
        MapEntry('Uygulayıcı Öğretmen', _str(a, 'teacher', ctx.currentUser?.fullName ?? 'Branş Öğretmeni')),
      ],
      composeBody: (a, ctx) => '''
BİREBİR / GRUP AKADEMİK ETÜT VE TELAFI ÇALIŞMASI YOKLAMA TUTANAĞI

Ölçme ve değerlendirme analizleri sonucunda belirlenen eksik konu ve kazanımların tamamlanması amacıyla gerçekleştirilen etüt çalışmasına katılan öğrenci/kursiyer yoklama çizelgesi aşağıdadır:''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(a, 'teacher', ctx.currentUser?.fullName ?? 'Öğretmen'),
          title: 'Etüt Öğretmeni',
        ),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'KONTROL / ONAY'),
          isApproval: true,
        ),
      ],
    ),

    // 12.10 MEB Müfettiş / İlçe MEM Kurum Denetimi Hazırlık ve Mevzuat Uygunluk Kontrol Tutanağı
    OfficialDocTemplate(
      id: 'ozel_ogretim_denetim_hazirlik_tutanagi',
      code: '12.10',
      categoryId: 'ozel_ogretim_kurs_ozel',
      title: 'MEB Maarif Müfettişleri / İlçe MEM Denetimi Öz Kontrol ve Mevzuat Uygunluk Tutanağı',
      subtitle:
          '5580 S.K. Md. 11 ve Standartlar Yönergesi kapsamında ruhsat, yerleşim planı, kamera, çalışma izni ve mali dosya kontrolü',
      legalBasis:
          '5580 Sayılı Kanun Md. 11 & MEB Özel Öğretim Kurumları Standartlar Yönergesi',
      scopes: const [DocRegulationScope.ozelOgretimKurs],
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.fact_check_outlined,
      questions: [
        DocQuestionField(
          key: 'date',
          label: 'Kurum İçi Öz Denetim Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'inspectors',
          label: 'Öz Denetimi Yapan İdareci / Birim Sorumluları',
          type: DocFieldType.multiStaffSelect,
        ),
        const DocQuestionField(
          key: 'checks',
          label: 'Kontrol Edilerek Uygunluğu Doğrulanan Zorunlu Denetim Başlıkları',
          type: DocFieldType.multiCheck,
          options: [
            'Kurum Açma İzni ile İş Yeri Açma ve Çalışma Ruhsatı ve onaylı yerleşim planı uyumu kontrol edildi; izinsiz bölme/oda değişikliği bulunmadığı doğrulandı.',
            'Kurumda görev yapan tüm yönetici, öğretmen ve uzman öğreticilerin geçerli Çalışma İzin Onayları ile SGK kayıtlarının birebir uyumlu olduğu doğrulandı.',
            'Bina giriş-çıkış, koridor ve bahçe güvenlik kameralarının (kör nokta kalmayacak şekilde, derslik içi hariç) çalışır durumda olduğu ve en az 30 günlük kayıt sakladığı kontrol edildi.',
            'Yangın algılama sistemi, yangın tüpleri dolum tarihleri, acil çıkış kapıları (dışa açılır panik barlı), İSG risk analizi ve acil durum planlarının güncel olduğu doğrulandı.',
            'Öğrenci/kursiyer standart kayıt sözleşmeleri, yıllık ücret ilan tutanağı ve %3 ücretsiz okutulan öğrenci (EK-7) dosyasının eksiksiz olduğu kontrol edildi.',
            'Sınıf/kurs ders defterlerinin günlük kazanımlara uygun imzalandığı, yoklama fişlerinin tutulduğu ve kurumsal tabela/ilanlarda MEB adını yanıltıcı ibare bulunmadığı doğrulandı.',
            'Atatürk Köşesi, Türk Bayrağı, İstiklal Marşı ve Gençliğe Hitabe standartlarının MEB Kurum Tanıtım Yönetmeliğine uygun olduğu kontrol edildi.',
            'Derslik kontenjanlarının (Özel Öğretim Kurslarında azami 16 kursiyer) ve derslik kapısı öğretmen/program çizelgelerinin yerleşim planıyla tam uyumlu olduğu doğrulandı.',
            'Eğitim personeli özlük dosyalarının, iş sözleşmelerinin, adli sicil ve sağlık raporlarının güncel olarak arşivlendiği kontrol edildi.',
            'Ücret tahsilatlarının banka/fatura karşılığı yürütüldüğü ve MEBBİS ücret ilan bildirimlerinin zamanında yapıldığı doğrulandı.',
            'Kurum kütüphanesi / çalışma salonu, rehberlik birimi, mescit ve lavabo/hijyen alanlarının Standartlar Yönergesine uygun olduğu kontrol edildi.',
          ],
          defaultValue: [
            'Kurum Açma İzni ile İş Yeri Açma ve Çalışma Ruhsatı ve onaylı yerleşim planı uyumu kontrol edildi; izinsiz bölme/oda değişikliği bulunmadığı doğrulandı.',
            'Kurumda görev yapan tüm yönetici, öğretmen ve uzman öğreticilerin geçerli Çalışma İzin Onayları ile SGK kayıtlarının birebir uyumlu olduğu doğrulandı.',
            'Bina giriş-çıkış, koridor ve bahçe güvenlik kameralarının (kör nokta kalmayacak şekilde, derslik içi hariç) çalışır durumda olduğu ve en az 30 günlük kayıt sakladığı kontrol edildi.',
            'Yangın algılama sistemi, yangın tüpleri dolum tarihleri, acil çıkış kapıları (dışa açılır panik barlı), İSG risk analizi ve acil durum planlarının güncel olduğu doğrulandı.',
            'Öğrenci/kursiyer standart kayıt sözleşmeleri, yıllık ücret ilan tutanağı ve %3 ücretsiz okutulan öğrenci (EK-7) dosyasının eksiksiz olduğu kontrol edildi.',
            'Sınıf/kurs ders defterlerinin günlük kazanımlara uygun imzalandığı, yoklama fişlerinin tutulduğu ve kurumsal tabela/ilanlarda MEB adını yanıltıcı ibare bulunmadığı doğrulandı.',
          ],
        ),
        const DocQuestionField(
          key: 'actionNote',
          label: 'Varsa Tespit Edilen Eksiklik ve Tamamlama Termin Tarihi',
          type: DocFieldType.text,
          defaultValue: 'Tüm birimler mevzuata uygun ve denetime hazır durumdadır.',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Denetim Türü', '5580 S.K. Kurum İçi Mevzuat Öz Denetim Kontrolü'),
        MapEntry('Kontrol Tarihi', _str(a, 'date', _today())),
        MapEntry('Genel Durum', _str(a, 'actionNote')),
      ],
      composeBody: (a, ctx) => '''
KURUM İÇİ MEVZUAT UYGUNLUK VE DENETİM HAZIRLIK TUTANAĞI

5580 sayılı Özel Öğretim Kurumları Kanunu, MEB Özel Öğretim Kurumları Yönetmeliği ve Özel Öğretim Kurumları Standartlar Yönergesi hükümleri doğrultusunda "${ctx.schoolName}" bünyesinde ${_str(a, 'date', _today())} tarihinde gerçekleştirilen öz denetim bulguları aşağıdadır:

DOĞRULANAN KONTROL KALEMLERİ:
${_numberedLines(_list(a, 'checks'))}

SONUÇ VE EYLEM NOTU:
${_str(a, 'actionNote')}''',
      buildSigners: (a, ctx) => [
        for (final i in _list(a, 'inspectors').take(3))
          DocSigner(name: i, title: 'Kontrol Eden Birim Sorumlusu'),
        DocSigner(
          name: ctx.principalName,
          title: _authorityTitle(ctx, 'Kurum Müdürü'),
          isApproval: true,
        ),
      ],
    ),

    // 12.11 Veli / Kursiyer KVKK Aydınlatma, Görsel/Medya ve İletişim Açık Rıza Beyanı
    OfficialDocTemplate(
      id: 'ozel_ogretim_kvkk_acik_riza_formu',
      code: '12.11',
      categoryId: 'ozel_ogretim_kurs_ozel',
      title: '6698 Sayılı KVKK Aydınlatma Metni, İletişim ve Görsel Paylaşım Açık Rıza Formu',
      subtitle:
          'Öğrenci/kursiyer sınav verisi, SMS bilgilendirme ve etkinlik fotoğraf/video paylaşımı için toplu veya tekil veli rıza pusulası',
      legalBasis:
          '6698 Sayılı Kişisel Verilerin Korunması Kanunu & MEB Sosyal Medya Kullanım Kılavuzu',
      scopes: const [
        DocRegulationScope.ozelOgretimKurs,
        DocRegulationScope.ortakMevzuat,
      ],
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.bulkParentSlip,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.privacy_tip_rounded,
      questions: [
        const DocQuestionField(
          key: 'targetClasses',
          label: 'Formun Basılacağı Şube / Grup(lar)',
          type: DocFieldType.multiClassSelect,
          required: true,
        ),
        DocQuestionField(
          key: 'eventDate',
          label: 'Belge Tarihi',
          type: DocFieldType.date,
          defaultValue: _today(),
        ),
        const DocQuestionField(
          key: 'slipsPerPage',
          label: 'Sayfa Yerleşimi',
          type: DocFieldType.dropdown,
          options: [
            'Her A4 Sayfasında 1 Tam Belge',
            'Her A4 Sayfasında 2 Kesimli Belge (Kağıt Tasarruflu)',
          ],
          defaultValue: 'Her A4 Sayfasında 1 Tam Belge',
        ),
      ],
      composeBody: (a, ctx) => '''
6698 SAYILI KVKK KAPSAMINDA VELİ / KURSİYER AYDINLATMA VE AÇIK RIZA BEYANI

Veri Sorumlusu "${ctx.schoolName}" tarafından; velisi bulunduğum {{SINIF}} şubesi {{NO}} numaralı öğrencimiz {{OGRENCI_ADI}}'na ait kimlik, iletişim, yoklama, rehberlik ve sınav/ölçme değerlendirme verilerinin eğitim-öğretim süreçlerinin yürütülmesi ve yasal MEB bildirimlerinin yapılması amacıyla 6698 sayılı Kanunun 5. ve 6. maddelerine uygun olarak işlendiği hususunda aydınlatıldım.

TERCİHE BAĞLI AÇIK RIZA KONULARI (Lütfen uygun kutucuğu işaretleyiniz):
[   ] KABUL EDİYORUM   [   ] KABUL ETMİYORUM — Öğrencimin devamsızlık, sınav sonucu, ödev ve kurumsal duyuru bilgilerinin tarafıma SMS / Mobil Uygulama / WhatsApp kanallarıyla iletilmesine açık rıza veriyorum.
[   ] KABUL EDİYORUM   [   ] KABUL ETMİYORUM — Öğrencimin okul/kurum içi bilimsel, sanatsal, sportif etkinlik ve törenlerde çekilen pedagojik ilkelere uygun grup fotoğraf/videolarının kurum resmi web sitesi ve kurumsal sosyal medya hesaplarında paylaşılmasına açık rıza veriyorum.''',
    ),
  ];
}

