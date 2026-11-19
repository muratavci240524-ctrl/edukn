import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../models/school/official_document_model.dart';
import 'official_document_catalog_ilkogretim.dart';
import 'official_document_catalog_oddk_disiplin.dart';
import 'official_document_catalog_ortaogretim.dart';
import 'official_document_catalog_ozel_kurs.dart';

/// 13 Ana Başlık ve Tüm MEB İlköğretim / Ortaöğretim / Özel Öğretim Kursları / ÖDDK Matbu Evrak Şablonları
class OfficialDocumentCatalog {
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
      return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
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

  // ═══════════════════════════════════════════════════════════════════════════
  // 9 ANA BAŞLIK (MEB YÖNETMELİKLERİNE TAM UYUMLU KATEGORİLER)
  // ═══════════════════════════════════════════════════════════════════════════
  static const List<OfficialDocCategory> categories = [
    // BÖLÜM A: İDARİ KURULLAR, KOMİSYONLAR VE DENETİM EVRAKLARI
    OfficialDocCategory(
      id: 'idari_kurul_komisyon',
      order: 1,
      title: '1. Eğitim-Öğretim Kurulları ve Zorunlu Komisyonlar',
      subtitle: 'Öğretmenler Kurulu, ŞÖK, Zümre Başkanları, PDR, BEP, ÖDDK/Disiplin, Sosyal Etkinlik ve Devamsızlık Kurulları',
      audience: DocAudience.admin,
      icon: Icons.groups_2_rounded,
      color: Color(0xFF1E3A8A),
    ),
    OfficialDocCategory(
      id: 'idari_mali_guvenlik_denetim',
      order: 2,
      title: '2. Mali İşler, Taşınır, Kantin, Servis ve İSG Denetim Komisyonları',
      subtitle: 'Satın Alma, Muayene-Kabul, Demirbaş Sayım, Kantin & Servis Denetim, Tahliye Tatbikatı ve OAB',
      audience: DocAudience.admin,
      icon: Icons.assured_workload_rounded,
      color: Color(0xFF0F766E),
    ),
    OfficialDocCategory(
      id: 'idari_personel_yazi',
      order: 3,
      title: '3. Personel Görevlendirme, Nöbet, Tebliğ ve İdari Yazılar',
      subtitle: 'Görevlendirme, İmza Sirküsü, Nöbet Talimatnamesi, DYK/Etüt Onayı, İzin, Görev Yeri ve Savunma Yazıları',
      audience: DocAudience.admin,
      icon: Icons.badge_rounded,
      color: Color(0xFF0369A1),
    ),
    OfficialDocCategory(
      id: 'idari_disiplin_kaza',
      order: 4,
      title: '4. Öğrenci Disiplin, Olay, Kaza, Devamsızlık ve Teslim Evrakları',
      subtitle: 'Olay/Disiplin Tutanağı, İfade Formu, Okul İçi Kaza, Devamsızlık Tebligatı, Yasaklı Eşya ve Evrak Teslim',
      audience: DocAudience.admin,
      icon: Icons.gavel_rounded,
      color: Color(0xFFB91C1C),
    ),
    OfficialDocumentCatalogOddkDisiplin.category,
    OfficialDocCategory(
      id: 'idari_gezi_toren',
      order: 6,
      title: '5. Gezi, Tören, Yarışma ve Veli İzin Evrakları',
      subtitle: 'Toplu Veli Muvafakatnamesi, Gezi Kafile Onayı, Resmi Tören Programı ve Yarışma Katılım Onayı',
      audience: DocAudience.common,
      icon: Icons.tour_rounded,
      color: Color(0xFFD97706),
    ),

    // BÖLÜM B: ÖĞRETMEN EVRAKLARI
    OfficialDocCategory(
      id: 'ogretmen_zumre_akademik',
      order: 7,
      title: '6. Zümre, Ortak Sınav, BEP ve Akademik Ders Evrakları',
      subtitle: 'Branş Zümre Tutanağı, Sınav Analiz & Telafi, Proje Dağıtım, Öğretmen BEP Planı ve Uygulamalı Sınav',
      audience: DocAudience.teacher,
      icon: Icons.menu_book_rounded,
      color: Color(0xFF4F46E5),
    ),
    OfficialDocCategory(
      id: 'ogretmen_sinif_veli',
      order: 8,
      title: '7. Sınıf Rehberlik, Veli Toplantısı ve Öğrenci Takip Evrakları',
      subtitle: 'Veli Toplantısı Paketi, Veli Görüşme, Sınıf İçi Tespit, Başkanlık Seçimi ve Sınıf Rehberlik Planı',
      audience: DocAudience.teacher,
      icon: Icons.record_voice_over_rounded,
      color: Color(0xFF0284C7),
    ),
    OfficialDocCategory(
      id: 'ogretmen_nobet_kulup_rehberlik',
      order: 9,
      title: '8. Nöbet, Sosyal Kulüp, Toplum Hizmeti ve Rehberlik Sevk',
      subtitle: 'Nöbet Vukuat Tutanağı, Öğrenci Kulüp Dosyası, Toplum Hizmeti Raporu ve Gizli PDR Sevk Formu',
      audience: DocAudience.teacher,
      icon: Icons.fact_check_rounded,
      color: Color(0xFF7C3AED),
    ),

    // BÖLÜM C: ORTAK LİSTE & KART OTOMASYONU
    OfficialDocCategory(
      id: 'ortak_liste_kart',
      order: 10,
      title: '9. Dinamik Liste, Sınav Salonu Yoklama ve Kart Üretici',
      subtitle: 'Özel Sütunlu Kontrol/İmza Listesi, Ortak Sınav Salonu Tutanağı, Kitap Dağıtım, QR Yaka Kartı ve Kapı Listesi',
      audience: DocAudience.common,
      icon: Icons.grid_on_rounded,
      color: Color(0xFF059669),
    ),

    // BÖLÜM D: MEB YÖNETMELİKLERİNE ÖZEL (İLKÖĞRETİM • ORTAÖĞRETİM • ÖZEL ÖĞRETİM & KURS) EVRAKLARI
    OfficialDocumentCatalogIlkogretim.category,
    OfficialDocumentCatalogOrtaogretim.category,
    OfficialDocumentCatalogOzelKurs.category,
  ];

  static List<OfficialDocCategory> get safeCategories => categories;

  static OfficialDocTemplate? findById(String id) {
    for (final t in templates) {
      if (t.id == id) return t;
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TÜM MATBU EVRAK ŞABLONLARI (MEB YÖNETMELİKLERİNE UYGUN KAPSAMLI KATALOG)
  // ═══════════════════════════════════════════════════════════════════════════
  static final List<OfficialDocTemplate> templates = [
    // ─────────────────────────────────────────────────────────────────────────
    // BAŞLIK 1: EĞİTİM-ÖĞRETİM KURULLARI VE ZORUNLU KOMİSYONLAR (İDARİ)
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'ogretmenler_kurulu_tutanagi',
      code: '1.1',
      categoryId: 'idari_kurul_komisyon',
      title: 'Öğretmenler Kurulu Toplantı Tutanağı & İmza Sirküsü',
      subtitle: 'Sene başı, dönem başı, sene sonu veya olağanüstü kurul gündemi, mevzuat kararları ve imza listesi',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.groups_rounded,
      questions: [
        const DocQuestionField(
          key: 'meetingPeriod',
          label: 'Kurul Dönemi / Türü',
          type: DocFieldType.dropdown,
          options: [
            'Sene Başı (1. Dönem Başı) Öğretmenler Kurulu',
            '2. Dönem Başı Öğretmenler Kurulu',
            'Sene Sonu Değerlendirme Öğretmenler Kurulu',
            'Olağanüstü Öğretmenler Kurulu',
          ],
          defaultValue: 'Sene Başı (1. Dönem Başı) Öğretmenler Kurulu',
        ),
        DocQuestionField(key: 'date', label: 'Toplantı Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'time', label: 'Toplantı Saati', type: DocFieldType.time, defaultValue: '10:00'),
        const DocQuestionField(
          key: 'place',
          label: 'Toplantı Yeri',
          type: DocFieldType.text,
          defaultValue: 'Okul Konferans Salonu / Öğretmenler Odası',
        ),
        const DocQuestionField(
          key: 'scribes',
          label: 'Tutanak Yazmanı Öğretmen(ler)',
          type: DocFieldType.multiStaffSelect,
          helperText: 'Kurul yazmanı olarak seçilen öğretmenleri belirleyin',
        ),
        const DocQuestionField(
          key: 'agenda',
          label: 'MEB Mevzuatı Gündem Maddeleri (Seçiniz veya Özel Madde Ekleyiniz)',
          type: DocFieldType.multiCheck,
          options: [
            'Açılış, yoklama, Ulu Önder Mustafa Kemal Atatürk ve eğitim şehitleri adına saygı duruşu, İstiklal Marşı ve yazman seçimi',
            '1739 sayılı Milli Eğitim Temel Kanunu genel/özel amaçları ile MEB Kurum Yönetmeliği ve yeni mevzuat değişikliklerinin okunması',
            'Bir önceki eğitim-öğretim yılı / dönem kurul kararlarının, akademik başarı ve devamsızlık verilerinin değerlendirilmesi',
            'MEB Eğitim ve Öğretim Yılı Çalışma Takvimi ile Türkiye Yüzyılı Maarif Modeli uygulama esaslarının görüşülmesi',
            'Sınıf/alan zümre toplantıları, ünitelendirilmiş yıllık planlar ve ders defterlerinin doldurulma esaslarının belirlenmesi',
            'MEB Yazılı ve Uygulamalı Sınavlar Yönergesi uyarınca ortak sınavlar, konu-kazanım dağılım tabloları ve analiz süreçleri',
            'Okul bünyesinde kurulması zorunlu kurul, komisyon ve ekiplerde görev alacak öğretmenlerin seçimi ve görev dağılımı',
            'Kaynaştırma/bütünleştirme öğrencileri, BEP Geliştirme Birimi çalışmaları ve destek eğitim odası planlamaları',
            'Rehberlik ve psikolojik danışma hizmetleri, sınıf rehberlik planları, akran zorbalığı ve şiddetin önlenmesi tedbirleri',
            'Öğrenci devam-devamsızlık erken uyarı takibi, derse zamanında giriş-çıkış ve kılık-kıyafet yönetmeliği uygulamaları',
            'Öğretmen nöbet görev esasları, servis/giriş-çıkış güvenliği, 6331 sayılı İSG Kanunu ve afet/acil durum tahliye planları',
            'Sosyal kulüpler, toplum hizmeti çalışmaları, belirli gün ve haftalar ile tören kutlama takviminin planlanması',
            'Destekleme ve Yetiştirme Kursları (DYK), okul içi etüt, proje (TÜBİTAK, TEKNOFEST, eTwinning) ve okuma kültürü çalışmaları',
            'Tasarruf tedbirleri, Sıfır Atık Projesi, okul demirbaşlarının ve etkileşimli tahtaların korunması esasları',
            'Veli toplantıları, ev ziyaretleri ve okul-veli iletişim kanallarının resmi çerçevede yürütülmesi',
            'İlkokullarda Yetiştirme Programı (İYEP) / Lise Sorumluluk Sınavları ve kazanım telafi eylem planlarının görüşülmesi',
            'Okul kantini, yemekhane ve öğrenci servis araçlarının aylık denetim esaslarının görüşülmesi',
            'Öğrenci Davranışlarını Değerlendirme (ÖDDK) / Ödül ve Disiplin ile Onur Kurulu önleyici çalışma ilkelerinin belirlenmesi',
            '6698 sayılı KVKK kapsamında öğrenci verilerinin ve sosyal medya görsel paylaşımlarının korunması esasları',
            'Dilek ve temennilerin dinlenmesi, kapanış',
          ],
          defaultValue: [
            'Açılış, yoklama, Ulu Önder Mustafa Kemal Atatürk ve eğitim şehitleri adına saygı duruşu, İstiklal Marşı ve yazman seçimi',
            '1739 sayılı Milli Eğitim Temel Kanunu genel/özel amaçları ile MEB Kurum Yönetmeliği ve yeni mevzuat değişikliklerinin okunması',
            'Bir önceki eğitim-öğretim yılı / dönem kurul kararlarının, akademik başarı ve devamsızlık verilerinin değerlendirilmesi',
            'MEB Eğitim ve Öğretim Yılı Çalışma Takvimi ile Türkiye Yüzyılı Maarif Modeli uygulama esaslarının görüşülmesi',
            'Sınıf/alan zümre toplantıları, ünitelendirilmiş yıllık planlar ve ders defterlerinin doldurulma esaslarının belirlenmesi',
            'MEB Yazılı ve Uygulamalı Sınavlar Yönergesi uyarınca ortak sınavlar, konu-kazanım dağılım tabloları ve analiz süreçleri',
            'Okul bünyesinde kurulması zorunlu kurul, komisyon ve ekiplerde görev alacak öğretmenlerin seçimi ve görev dağılımı',
            'Kaynaştırma/bütünleştirme öğrencileri, BEP Geliştirme Birimi çalışmaları ve destek eğitim odası planlamaları',
            'Öğrenci devam-devamsızlık erken uyarı takibi, derse zamanında giriş-çıkış ve kılık-kıyafet yönetmeliği uygulamaları',
            'Öğretmen nöbet görev esasları, servis/giriş-çıkış güvenliği, 6331 sayılı İSG Kanunu ve afet/acil durum tahliye planları',
            'Dilek ve temennilerin dinlenmesi, kapanış',
          ],
        ),
        const DocQuestionField(
          key: 'decisions',
          label: 'Alınan Öğretmenler Kurulu Kararları',
          type: DocFieldType.multiCheck,
          options: [
            'Ünitelendirilmiş yıllık ders planlarının ve zümre tutanaklarının Türkiye Yüzyılı Maarif Modeli ve güncel öğretim programlarına uygun hazırlanarak ders yılının ilk haftasında idareye teslim edilmesine karar verildi.',
            'Ortak yazılı ve uygulamalı sınavların MEB Ölçme ve Değerlendirme Yönetmeliği doğrultusunda konu-kazanım dağılım tablolarına göre yapılmasına; sınav sonrası kazanım analizleri yapılarak baraj altı kalan kazanımlar için telafi/eylem planı uygulanmasına karar verildi.',
            'Öğrenci yoklamalarının her dersin ilk 5 dakikasında eksiksiz alınmasına, e-Okul/okul otomasyonuna günlük işlenmesine ve üst üste devamsızlık yapan öğrencilerin velilerinin sınıf rehber öğretmeni ve idarece aynı gün bilgilendirilmesine karar verildi.',
            'Özel eğitim / kaynaştırma raporu bulunan öğrenciler için BEP Geliştirme Birimi kararları doğrultusunda her branşta bireyselleştirilmiş eğitim planı (BEP) hazırlanmasına ve sınavlarda gerekli tedbirlerin alınmasına karar verildi.',
            'Nöbetçi öğretmenlerin ilk dersten en az 20/30 dakika önce görev yerinde bulunmasına, teneffüslerde sorumlu oldukları kat/bahçe alanından ayrılmamasına ve gün sonunda nöbet defterini/vukuat durumunu nöbetçi idareye bildirmesine karar verildi.',
            'Sınıf rehber öğretmenlerince her dönem en az bir genel veli toplantısı düzenlenmesine; bireysel veli görüşmelerinin mutlaka resmi "Veli Görüşme Tutanağı" ile kayıt altına alınmasına karar verildi.',
            'Akran zorbalığının önlenmesi, dijital bağımlılıkla mücadele ve olumlu okul iklimi kapsamında Rehberlik Servisi koordinasyonunda koruyucu-önleyici sınıf etkinlikleri yürütülmesine karar verildi.',
            'Okul bünyesinde zorunlu olan ÖDDK/Disiplin, Rehberlik Yürütme, Sosyal Etkinlikler, Kantin Denetim, Satın Alma, Muayene-Kabul ve Eser İnceleme komisyonlarının oluşturularak görev tebliğlerinin yapılmasına karar verildi.',
            'Sosyal kulüp ve toplum hizmeti çalışmalarının Sosyal Etkinlikler Yönetmeliğine uygun olarak yıllık plana bağlanmasına ve e-Okul Sosyal Etkinlik Modülüne düzenli işlenmesine karar verildi.',
            'Derslerde cep telefonu, akıllı saat vb. dikkat dağıtıcı cihazların mevzuat çerçevesinde kapalı/muhafaza altında tutulmasına ve kılık-kıyafet kurallarının tüm öğretmenlerce ortak tutumla takip edilmesine karar verildi.',
            'Enerji, su ve kırtasiye kullanımında kamu tasarruf tedbirlerine riayet edilmesine, etkileşimli tahta ve laboratuvar malzemelerinin ders bitiminde güvenli şekilde kapatılmasına karar verildi.',
            'Her gün ilk ders saatinde ve hafta sonu bayrak törenlerinde öğrencilerin okuma kültürü ve milli-manevi değerler bilincini destekleyici etkinliklere etkin katılımının sağlanmasına karar verildi.',
            'Olumsuz öğrenci davranışlarında kurula sevkten önce MEB Yönetmeliği Md. 54 uyarınca sözlü uyarı, EK-9 öğrenci sözleşmesi ve veli görüşmesi adımlarının eksiksiz işletilmesine karar verildi.',
            'Sınıf ders defterlerinin kazanım/öğrenme çıktısı açıklamalarıyla günlük yazılıp imzalanmasına; nöbetçi idarecilerce haftalık kontrol edilmesine karar verildi.',
            'Yazılı sınav kağıtlarının değerlendirilmesinde zümrece hazırlanan ayrıntılı puanlama anahtarının kullanılmasına ve sınav sonuçlarının yasal 10 iş günü içinde öğrencilere duyurularak e-Okul\'a işlenmesine karar verildi.',
            '6698 sayılı Kişisel Verilerin Korunması Kanunu uyarınca veli açık rızası bulunmayan hiçbir öğrenci görselinin veya kişisel bilgisinin dijital mecralarda paylaşılmamasına karar verildi.',
            'Okul kütüphanesinin ve sınıf kitaplıklarının aktif kullandırılmasına; eser seçimi komisyonu onayı bulunmayan yardımcı materyal ve yayınların sınıflara sokulmamasına karar verildi.',
            'Deprem, yangın ve acil durum tahliye planlarının tüm sınıflarda öğrencilere uygulamalı anlatılmasına ve dönem içinde habersiz tahliye tatbikatı yapılmasına karar verildi.',
          ],
          defaultValue: [
            'Ünitelendirilmiş yıllık ders planlarının ve zümre tutanaklarının Türkiye Yüzyılı Maarif Modeli ve güncel öğretim programlarına uygun hazırlanarak ders yılının ilk haftasında idareye teslim edilmesine karar verildi.',
            'Ortak yazılı ve uygulamalı sınavların MEB Ölçme ve Değerlendirme Yönetmeliği doğrultusunda konu-kazanım dağılım tablolarına göre yapılmasına; sınav sonrası kazanım analizleri yapılarak baraj altı kalan kazanımlar için telafi/eylem planı uygulanmasına karar verildi.',
            'Öğrenci yoklamalarının her dersin ilk 5 dakikasında eksiksiz alınmasına, e-Okul/okul otomasyonuna günlük işlenmesine ve üst üste devamsızlık yapan öğrencilerin velilerinin sınıf rehber öğretmeni ve idarece aynı gün bilgilendirilmesine karar verildi.',
            'Özel eğitim / kaynaştırma raporu bulunan öğrenciler için BEP Geliştirme Birimi kararları doğrultusunda her branşta bireyselleştirilmiş eğitim planı (BEP) hazırlanmasına ve sınavlarda gerekli tedbirlerin alınmasına karar verildi.',
            'Nöbetçi öğretmenlerin ilk dersten en az 20/30 dakika önce görev yerinde bulunmasına, teneffüslerde sorumlu oldukları kat/bahçe alanından ayrılmamasına ve gün sonunda nöbet defterini/vukuat durumunu nöbetçi idareye bildirmesine karar verildi.',
            'Sınıf rehber öğretmenlerince her dönem en az bir genel veli toplantısı düzenlenmesine; bireysel veli görüşmelerinin mutlaka resmi "Veli Görüşme Tutanağı" ile kayıt altına alınmasına karar verildi.',
          ],
        ),
        const DocQuestionField(
          key: 'extraNotes',
          label: 'Kurulda Görüşülen Özel Hususlar / Ek Karar Notu (Opsiyonel)',
          type: DocFieldType.multiline,
          hint: 'Toplantıda söz alan öğretmen görüşleri veya okula özgü ek karar varsa yazabilirsiniz...',
        ),
        const DocQuestionField(
          key: 'includeStaffSignatureTable',
          label: 'Tutanak Sonuna Tüm Öğretmen İmza Sirküsü Eklensin mi?',
          type: DocFieldType.yesNo,
          defaultValue: true,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Eğitim-Öğretim Yılı', '${ctx.academicYear} (${ctx.activeTermLabel})'),
        MapEntry('Kurul Türü', _str(a, 'meetingPeriod', 'Öğretmenler Kurulu')),
        MapEntry('Toplantı Tarih / Saat', '${_str(a, "date", _today())} - ${_str(a, "time", "10:00")}'),
        MapEntry('Toplantı Yeri', _str(a, 'place', 'Öğretmenler Odası')),
        MapEntry('Kurul Başkanı', '${ctx.principalName} (${ctx.principalTitle})'),
      ],
      composeBody: (a, ctx) {
        final period = _str(a, 'meetingPeriod', 'Öğretmenler Kurulu');
        final date = _str(a, 'date', _today());
        final time = _str(a, 'time', '10:00');
        final place = _str(a, 'place', 'Öğretmenler Odası');
        final scribes = _list(a, 'scribes');
        final agenda = _list(a, 'agenda');
        final decisions = _list(a, 'decisions');
        final extra = _str(a, 'extraNotes');

        final buf = StringBuffer();
        buf.writeln(
          'Millî Eğitim Bakanlığı Eğitim Kurumları Yönetmeliği ilgili hükümleri doğrultusunda; ${ctx.academicYear} Eğitim ve Öğretim Yılı ${ctx.schoolName} "$period" toplantısı, $date tarihinde saat $time\'da $place adresinde ${ctx.principalTitle} ${ctx.principalName} başkanlığında idareci ve öğretmenlerin çoğunluk katılımıyla gerçekleştirilmiştir.',
        );
        buf.writeln(
          'Yoklamanın yapılması, saygı duruşu ve İstiklal Marşı\'nın okunmasının ardından gündem maddeleri kurulun onayına sunulmuş ve oy birliği ile kabul edilmiştir.',
        );
        if (scribes.isNotEmpty) {
          buf.writeln('Kurul tutanak yazmanlığına ${scribes.join(" ve ")} seçilmiştir.');
        }
        buf.writeln('\nGÜNDEM MADDELERİ:');
        buf.writeln(_numberedLines(agenda));
        buf.writeln('\nGÜNDEM MADDELERİNİN GÖRÜŞÜLMESİ:');
        buf.writeln(
          'Gündem maddeleri sırasıyla kurul üyelerinin görüş ve değerlendirmelerine açılmıştır. 1739 sayılı Milli Eğitim Temel Kanunu\'nun genel amaç ve temel ilkeleri, güncel öğretim programları, ölçme-değerlendirme uygulamaları, öğrenci devam ve davranış takibi, özel eğitim/BEP süreçleri, rehberlik hizmetleri ile okul güvenliği ve işleyiş esasları ayrıntılı biçimde müzakere edilmiştir.',
        );
        if (extra.isNotEmpty) {
          buf.writeln('\nÖZEL GÖRÜŞMELER VE DEĞERLENDİRMELER:\n$extra');
        }
        buf.writeln('\nALINAN ÖĞRETMENLER KURULU KARARLARI:');
        buf.writeln(_numberedLines(decisions, prefix: 'Karar '));
        buf.writeln(
          '\nGündemde görüşülecek başka madde kalmadığından yeni dönemin tüm öğrenci, öğretmen ve velilerimize başarı getirmesi temennisiyle toplantıya son verilmiş olup işbu tutanak imza altına alınmıştır.',
        );
        return buf.toString().trim();
      },
      buildSigners: (a, ctx) {
        final scribes = _list(a, 'scribes');
        return [
          for (final s in scribes) DocSigner(name: s, title: 'Yazman Öğretmen'),
          DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'Kurul Başkanı'), isApproval: scribes.isNotEmpty),
        ];
      },
    ),

    OfficialDocTemplate(
      id: 'sok_toplanti_tutanagi',
      code: '1.2',
      categoryId: 'idari_kurul_komisyon',
      title: 'Şube Öğretmenler Kurulu (ŞÖK) Toplantı Tutanağı',
      subtitle: 'Seçilen şubenin tüm ders öğretmenleri, bireysel öğrenci analizi, BEP/rehberlik ve başarı kararları',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.meeting_room_rounded,
      questions: [
        const DocQuestionField(key: 'targetClass', label: 'Şube Seçimi', type: DocFieldType.classSelect, required: true),
        const DocQuestionField(
          key: 'termLabel',
          label: 'Toplantı Dönemi',
          type: DocFieldType.dropdown,
          options: [
            '1. Dönem Şube Öğretmenler Kurulu (ŞÖK)',
            '2. Dönem Şube Öğretmenler Kurulu (ŞÖK)',
            'Sene Sonu Öğrenci Başarı / Sınıf Geçme ŞÖK Toplantısı',
            'Olağanüstü Davranış ve Akademik Değerlendirme ŞÖK Toplantısı',
          ],
          defaultValue: '1. Dönem Şube Öğretmenler Kurulu (ŞÖK)',
        ),
        DocQuestionField(key: 'date', label: 'Toplantı Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'time', label: 'Toplantı Saati', type: DocFieldType.time, defaultValue: '15:30'),
        const DocQuestionField(key: 'chairPerson', label: 'Kurul Başkanı (Müdür / Müdür Yardımcısı)', type: DocFieldType.staffSelect),
        const DocQuestionField(
          key: 'sokTeachers',
          label: 'Şubeye Derse Giren Tüm Öğretmenler ve Rehberlik (Otomatik Seçili)',
          type: DocFieldType.multiCheck,
          helperText: 'Şubenin normal ders, kurlu ders (İngilizce vb.), haftalık ders programı ve rehber öğretmenlerinin tamamı otomatik seçili gelir ve PDF sonunda İmza Sirküsü Tablosuna aktarılır.',
        ),
        const DocQuestionField(
          key: 'includeSokSignatureTable',
          label: 'Tutanak Sonuna ŞÖK Öğretmen İmza Sirküsü Tablosu Eklensin mi?',
          type: DocFieldType.yesNo,
          defaultValue: true,
        ),
        const DocQuestionField(
          key: 'focusStudents',
          label: 'Akademik / Devamsızlık / Davranış Yönünden Görüşülen Öğrenciler',
          type: DocFieldType.multiStudentSelect,
          helperText: 'Yukarıdan seçilen şubenin öğrencileri otomatik listelenir',
        ),
        const DocQuestionField(
          key: 'agenda',
          label: 'ŞÖK Gündem Maddeleri',
          type: DocFieldType.multiCheck,
          options: [
            'Açılış, yoklama ve bir önceki ŞÖK kararlarının gözden geçirilmesi',
            'Şubenin genel akademik başarı düzeyi, ortak yazılı ve deneme sınav sonuçlarının ders bazlı analizi',
            'Öğrencilerin kişilik, sağlık, sosyal-ekonomik durumları ve ailevi özelliklerinin değerlendirilmesi',
            'Akademik başarısı düşük ve öğrenme güçlüğü yaşayan öğrenciler için yapılacak destek/etüt çalışmaları',
            'Kaynaştırma/bütünleştirme öğrencilerinin BEP hedefleri ve sınıf içi uyarlamalarının değerlendirilmesi',
            'Şubedeki devam-devamsızlık durumu, derse hazırlık, ödev alışkanlığı ve kılık-kıyafet uyumu',
            'Akran ilişkileri, sınıf içi iletişim, olumlu davranış geliştirme ve rehberlik servisi iş birliği',
            'Özel yetenekli, kronik rahatsızlığı olan veya sosyo-ekonomik açıdan desteklenmesi gereken öğrencilerin durumu',
            'Üst öğrenime hazırlık (LGS / YKS), kitap okuma alışkanlığı ve verimli ders çalışma becerilerinin değerlendirilmesi',
            'Dijital ekran süresi, sosyal medya kullanımı ve siber zorbalığa karşı sınıf içi koruyucu önlemler',
            'Şubede örnek davranış gösteren ve ödüllendirilmesi (Onur Belgesi vb.) teklif edilen öğrencilerin belirlenmesi',
            'Veli-öğretmen iletişiminin güçlendirilmesi, dilek ve kapanış',
          ],
          defaultValue: [
            'Açılış, yoklama ve bir önceki ŞÖK kararlarının gözden geçirilmesi',
            'Şubenin genel akademik başarı düzeyi, ortak yazılı ve deneme sınav sonuçlarının ders bazlı analizi',
            'Akademik başarısı düşük ve öğrenme güçlüğü yaşayan öğrenciler için yapılacak destek/etüt çalışmaları',
            'Şubedeki devam-devamsızlık durumu, derse hazırlık, ödev alışkanlığı ve kılık-kıyafet uyumu',
            'Akran ilişkileri, sınıf içi iletişim, olumlu davranış geliştirme ve rehberlik servisi iş birliği',
          ],
        ),
        const DocQuestionField(
          key: 'generalEvaluation',
          label: 'Şubenin Genel Akademik ve Davranışsal Görünümü',
          type: DocFieldType.dropdown,
          options: [
            'Şubenin genel akademik başarısı iyi düzeyde olup derse katılım, ödev sorumluluğu ve sınıf kurallarına uyum olumludur.',
            'Şubenin akademik başarısı orta düzeyde olup özellikle sayısal ve okuduğunu anlama becerilerinde düzenli tekrar ve etüt desteğine ihtiyaç duyulmaktadır.',
            'Şubede derse odaklanma, ders materyali getirme, ödev takibi ve akademik motivasyon konularında tüm branş öğretmenlerinin ortak tutum ve yakın izleme yürütmesi gerekmektedir.',
          ],
          defaultValue:
              'Şubenin akademik başarısı orta düzeyde olup özellikle sayısal ve okuduğunu anlama becerilerinde düzenli tekrar ve etüt desteğine ihtiyaç duyulmaktadır.',
        ),
        const DocQuestionField(
          key: 'decisions',
          label: 'Alınan Şube Öğretmenler Kurulu (ŞÖK) Kararları',
          type: DocFieldType.multiCheck,
          options: [
            'Akademik başarısı baraj altında kalan ve kazanım eksiği bulunan öğrencilerin bireysel/grup etüt ve DYK çalışmalarına yönlendirilmesine karar verildi.',
            'Ödev takibi zayıf veya derse materyal eksikliğini alışkanlık haline getiren öğrencilerin velileriyle sınıf rehber öğretmeni tarafından birebir görüşme yapılarak tutanak altına alınmasına karar verildi.',
            'Sınıf içi dikkat dağınıklığı ve akran etkileşimi dikkate alınarak sınıf oturma planının ders öğretmenlerinin görüşüyle güncellenmesine karar verildi.',
            'Rehberlik ve Psikolojik Danışma Servisi iş birliği ile şubede verimli ders çalışma teknikleri, zaman yönetimi ve sınav kaygısı oturumu uygulanmasına karar verildi.',
            'Şubedeki tüm ders öğretmenlerinin sınıf kuralları, derse zamanında giriş ve söz alarak konuşma konularında ortak ve tutarlı pedagojik yaklaşım sergilemesine karar verildi.',
            'Devamsızlık eğilimi gösteren öğrencilerin günlük takip edilerek velileriyle erken uyarı görüşmesi yapılmasına karar verildi.',
            'Kaynaştırma/BEP kapsamındaki öğrencilerin bireysel gelişim hızlarına uygun görev ve ölçme araçlarıyla desteklenmesine karar verildi.',
            'Akademik ve davranışsal açıdan olumlu gelişim gösteren öğrencilerin sınıf içinde ve veli nezdinde takdir edilerek motive edilmesine karar verildi.',
            'Üst öğrenime geçiş (LGS/YKS) hedefleri doğrultusunda deneme sınavı kazanım analizlerinin her sınav sonrası branş öğretmenlerince şubede değerlendirilmesine karar verildi.',
            'Olumsuz davranış eğilimi görülen öğrencilerde ders öğretmenlerinin sınıf rehber öğretmeni ile eşgüdümlü hareket ederek sözlü uyarı ve EK-9 davranış sözleşmesi sürecini işletmesine karar verildi.',
            'Okuma kültürünü ve okuduğunu anlama becerisini geliştirmek amacıyla tüm derslerde metin yorumlama ve akademik kelime çalışmalarına yer verilmesine karar verildi.',
            'Sağlık sorunu, alerji veya özel durumu bulunan öğrenciler konusunda şubeye derse giren tüm öğretmenlerin gizlilik ilkesiyle bilgilendirilmesine karar verildi.',
            'Sosyal içe kapanıklık gözlenen öğrencilerin kulüp, grup çalışması ve sınıf içi görevlerle akran grubuna dahil edilmesine karar verildi.',
          ],
          defaultValue: [
            'Akademik başarısı baraj altında kalan ve kazanım eksiği bulunan öğrencilerin bireysel/grup etüt ve DYK çalışmalarına yönlendirilmesine karar verildi.',
            'Ödev takibi zayıf veya derse materyal eksikliğini alışkanlık haline getiren öğrencilerin velileriyle sınıf rehber öğretmeni tarafından birebir görüşme yapılarak tutanak altına alınmasına karar verildi.',
            'Sınıf içi dikkat dağınıklığı ve akran etkileşimi dikkate alınarak sınıf oturma planının ders öğretmenlerinin görüşüyle güncellenmesine karar verildi.',
            'Rehberlik ve Psikolojik Danışma Servisi iş birliği ile şubede verimli ders çalışma teknikleri, zaman yönetimi ve sınav kaygısı oturumu uygulanmasına karar verildi.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Şube / Dönem', '${_str(a, "targetClass", "-")} / ${_str(a, "termLabel", "1. Dönem ŞÖK")}'),
        MapEntry('Tarih / Saat', '${_str(a, "date", _today())} - ${_str(a, "time", "15:30")}'),
        MapEntry('Kurul Başkanı', _str(a, 'chairPerson', ctx.principalName)),
      ],
      composeBody: (a, ctx) {
        final cls = _str(a, 'targetClass', 'İlgili');
        final term = _str(a, 'termLabel', '1. Dönem ŞÖK Toplantısı');
        final date = _str(a, 'date', _today());
        final time = _str(a, 'time', '15:30');
        final chair = _str(a, 'chairPerson', ctx.principalName);
        final agenda = _list(a, 'agenda');
        final eval = _str(a, 'generalEvaluation');
        final students = _list(a, 'focusStudents');
        final decisions = _list(a, 'decisions');
        final selectedTeachers = _list(a, 'sokTeachers');
        final branchTeachers = a.containsKey('sokTeachers')
            ? selectedTeachers
            : (ctx.classTeachersByClass[cls] ?? const []);

        final buf = StringBuffer();
        buf.writeln(
          'MEB Eğitim Kurumları Yönetmeliği ilgili maddesi gereğince; ${ctx.academicYear} Eğitim ve Öğretim Yılı ${ctx.schoolName} $cls Şubesi "$term", $date tarihinde saat $time\'da $chair başkanlığında şubede derse giren öğretmenler ve rehberlik temsilcisinin katılımıyla toplanmıştır.',
        );
        if (branchTeachers.isNotEmpty) {
          buf.writeln('\nŞUBEYE DERSE GİREN ÖĞRETMENLER:\n${branchTeachers.join(", ")}');
        }
        if (agenda.isNotEmpty) {
          buf.writeln('\nGÜNDEM MADDELERİ:\n${_numberedLines(agenda)}');
        }
        buf.writeln('\nŞUBENİN GENEL AKADEMİK VE DAVRANIŞSAL DEĞERLENDİRMESİ:\n$eval');
        if (students.isNotEmpty) {
          buf.writeln(
            '\nÖZEL OLARAK DESTEKLENECEK VE YAKINDAN İZLENECEK ÖĞRENCİLER:\n${_numberedLines(students)}',
          );
        }
        buf.writeln('\nALINAN ŞUBE ÖĞRETMENLER KURULU KARARLARI:');
        buf.writeln(_numberedLines(decisions, prefix: 'Karar '));
        buf.writeln(
          '\nAlınan kararların şube rehber öğretmeni, tüm ders öğretmenleri ve okul rehberlik servisi eşgüdümünde titizlikle uygulanmasına oy birliği ile karar verilmiştir.',
        );
        return buf.toString().trim();
      },
      buildSigners: (a, ctx) {
        final chair = _str(a, 'chairPerson', ctx.principalName).trim();
        final effectiveChair = chair.isNotEmpty ? chair : ctx.principalName;
        return [
          DocSigner(
            name: effectiveChair,
            title: effectiveChair == ctx.principalName
                ? _authorityTitle(ctx)
                : 'ŞÖK Başkanı',
            isApproval: true,
          ),
        ];
      },
    ),

    OfficialDocTemplate(
      id: 'zumre_baskanlari_kurulu',
      code: '1.3',
      categoryId: 'idari_kurul_komisyon',
      title: 'Okul Sınıf / Alan Zümre Başkanları Kurulu Tutanağı',
      subtitle: 'Branşlar arası eşgüdüm, ortak sınav takvimi, proje dağılımı ve akademik standart kararları',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.account_tree_rounded,
      questions: [
        DocQuestionField(key: 'date', label: 'Toplantı Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'time', label: 'Toplantı Saati', type: DocFieldType.time, defaultValue: '13:30'),
        const DocQuestionField(
          key: 'heads',
          label: 'Katılan Zümre Başkanları',
          type: DocFieldType.multiStaffSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'decisions',
          label: 'Alınan Zümre Başkanları Eşgüdüm Kararları',
          type: DocFieldType.multiCheck,
          options: [
            'Disiplinler arası ortak konu ve becerilerin eş zamanlı işlenmesi için zümreler arası aylık iş birliği yapılmasına karar verildi.',
            'Ortak yazılı sınavlar ile kurumsal deneme sınavlarının aynı günde iki dersi geçmeyecek şekilde sınav takvimine bağlanmasına karar verildi.',
            'Açık uçlu yazılı sınav sorularının il/okul konu-kazanım dağılım tablolarına ve üst düzey düşünme becerilerine uygun hazırlanmasına karar verildi.',
            'Öğrencilere verilecek proje ve performans görevlerinin ders yükü dengesi gözetilerek takvimlendirilmesine ve değerlendirme ölçeklerinin (rubrik) önceden duyurulmasına karar verildi.',
            'Tüm branşlarda okuduğunu anlama, akademik sözvarlığı ve grafik/tablo yorumlama becerilerini destekleyen etkinliklere yer verilmesine karar verildi.',
            'Laboratuvar, kütüphane, bilişim sınıfı ve spor salonu kullanım çizelgelerinin zümre ihtiyaçlarına göre planlanmasına karar verildi.',
            'TÜBİTAK, TEKNOFEST ve ilçe/il yarışmalarına zümreler arası disiplinler üstü öğrenci takımlarıyla katılım sağlanmasına karar verildi.',
            'Sınav analiz sonuçlarında okul ortalamasının altında kalan ortak kazanımlar için eylem planı hazırlanarak bir sonraki kurulda değerlendirilmesine karar verildi.',
            'Türkçe ve yabancı dil derslerinde dinleme-konuşma uygulamalı sınavları ile diğer derslerdeki performans değerlendirmelerinin şeffaf dereceli puanlama anahtarlarıyla yürütülmesine karar verildi.',
            'Kaynaştırma/bütünleştirme öğrencilerinin BEP sınav sorularının tüm zümrelerce öğrencinin bireysel performans düzeyine uygun olarak sadeleştirilmesine karar verildi.',
            'Milli bayramlar, belirli gün ve haftalar ile değerler eğitimi temalarının tüm zümre yıllık planlarında eşgüdümlü şekilde işlenmesine karar verildi.',
            'Destekleme ve Yetiştirme Kursları (DYK) ile okul içi etütlerde zümrelerce ortak kazanım tarama yapraklarının kullanılmasına karar verildi.',
            'Öğrencilerin bilimsel etik, kaynak gösterme ve akademik dürüstlük bilinci kazanmaları için tüm proje ödevlerinde ortak rehberlik yapılmasına karar verildi.',
          ],
          defaultValue: [
            'Disiplinler arası ortak konu ve becerilerin eş zamanlı işlenmesi için zümreler arası aylık iş birliği yapılmasına karar verildi.',
            'Ortak yazılı sınavlar ile kurumsal deneme sınavlarının aynı günde iki dersi geçmeyecek şekilde sınav takvimine bağlanmasına karar verildi.',
            'Açık uçlu yazılı sınav sorularının il/okul konu-kazanım dağılım tablolarına ve üst düzey düşünme becerilerine uygun hazırlanmasına karar verildi.',
            'Öğrencilere verilecek proje ve performans görevlerinin ders yükü dengesi gözetilerek takvimlendirilmesine ve değerlendirme ölçeklerinin (rubrik) önceden duyurulmasına karar verildi.',
            'Tüm branşlarda okuduğunu anlama, akademik sözvarlığı ve grafik/tablo yorumlama becerilerini destekleyen etkinliklere yer verilmesine karar verildi.',
          ],
        ),
        const DocQuestionField(
          key: 'includeStaffSignatureTable',
          label: 'Tutanak Sonuna Katılımcı İmza Sirküsü Eklensin mi?',
          type: DocFieldType.yesNo,
          defaultValue: false,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Eğitim-Öğretim Yılı', '${ctx.academicYear} (${ctx.activeTermLabel})'),
        MapEntry('Toplantı Tarihi / Saati', '${_str(a, "date", _today())} - ${_str(a, "time", "13:30")}'),
        MapEntry('Kurul Başkanı', '${ctx.principalName} (${ctx.principalTitle})'),
      ],
      composeBody: (a, ctx) {
        final heads = _list(a, 'heads');
        final decisions = _list(a, 'decisions');
        return '''
MEB Eğitim Kurumları Sınıf ve Alan Zümreleri Yönergesi hükümleri uyarınca; ${ctx.academicYear} Eğitim ve Öğretim Yılı ${ctx.schoolName} Okul Zümre Başkanları Kurulu, ${_str(a, 'date', _today())} tarihinde saat ${_str(a, 'time', '13:30')}'da toplanarak öğretim programlarının eşgüdümlü uygulanması, zümreler arası iş birliği, ortak sınav standartları ve akademik gelişim hedeflerini görüşmüştür.

KATILAN SINIF / ALAN ZÜMRE BAŞKANLARI:
${heads.isEmpty ? 'Tüm Branş Zümre Başkanları' : _numberedLines(heads)}

GÖRÜŞMELER VE ALINAN EŞGÜDÜM KARARLARI:
${_numberedLines(decisions, prefix: 'Karar ')}

İşbu tutanak zümre başkanlarınca okunarak imza altına alınmış ve Okul Müdürlüğünün onayına sunulmuştur.''';
      },
      buildSigners: (a, ctx) => [
        for (final h in _list(a, 'heads').take(6)) DocSigner(name: h, title: 'Zümre Başkanı'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'Uygundur'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'pdr_yurutme_komisyonu_tutanagi',
      code: '1.4',
      categoryId: 'idari_kurul_komisyon',
      title: 'Rehberlik ve Psikolojik Danışma Hizmetleri Yürütme Komisyonu Tutanağı',
      subtitle: 'MEB Rehberlik Yönetmeliği zorunlu komisyonu: okul özel hedefleri, risk haritası ve önleyici çalışmalar',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.psychology_alt_rounded,
      questions: [
        const DocQuestionField(
          key: 'termType',
          label: 'Toplantı Dönemi',
          type: DocFieldType.dropdown,
          options: [
            '1. Dönem Başı RPDH Yürütme Komisyonu Toplantısı',
            '2. Dönem Başı RPDH Yürütme Komisyonu Toplantısı',
            'Sene Sonu RPDH Değerlendirme Komisyonu Toplantısı',
          ],
          defaultValue: '1. Dönem Başı RPDH Yürütme Komisyonu Toplantısı',
        ),
        DocQuestionField(key: 'date', label: 'Toplantı Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'members', label: 'Komisyon Üyeleri (İdareci, Psikolojik Danışman, Sınıf Rehber Temsilcileri)', type: DocFieldType.multiStaffSelect, required: true),
        const DocQuestionField(
          key: 'localGoals',
          label: 'Belirlenen Ulusal / Yerel ve Okul Özel Rehberlik Hedefleri',
          type: DocFieldType.multiCheck,
          options: [
            'Akran zorbalığını önleme, empati ve barışçıl çatışma çözme becerilerinin geliştirilmesi',
            'Teknoloji / ekran bağımlılığı ve siber güvenlik konusunda öğrenci ve veli farkındalığının artırılması',
            'Akademik motivasyon, hedef belirleme, üst öğrenime (LGS / YKS) hazırlık ve kariyer rehberliği',
            'Okula yeni başlayan öğrencilerin oryantasyon (uyum) sürecinin desteklenmesi',
            'Sınav kaygısı, stres yönetimi ve psikolojik sağlamlığın güçlendirilmesi',
            'Devamsızlık riski taşıyan ve dezavantajlı öğrencilerin erken tespiti ve psiko-sosyal takibi',
            'İhmal ve istismardan korunma, mahremiyet bilinci ve güvenli kişisel sınırlar farkındalığının kazandırılması',
            'Öfke kontrolü, dürtü yönetimi ve sosyal-duygusal becerilerin sınıf rehberlik etkinlikleriyle desteklenmesi',
            'Özel gereksinimli (BEP) ve özel yetenekli öğrencilerin okula aidiyet ve sosyal kabul süreçlerinin güçlendirilmesi',
            'Tütün, teknoloji ve davranışsal bağımlılıklara karşı Yeşilay (TBM) tabanlı önleyici rehberlik çalışmaları yürütülmesi',
          ],
          defaultValue: [
            'Akran zorbalığını önleme, empati ve barışçıl çatışma çözme becerilerinin geliştirilmesi',
            'Teknoloji / ekran bağımlılığı ve siber güvenlik konusunda öğrenci ve veli farkındalığının artırılması',
            'Akademik motivasyon, hedef belirleme, üst öğrenime (LGS / YKS) hazırlık ve kariyer rehberliği',
          ],
        ),
        const DocQuestionField(
          key: 'decisions',
          label: 'Alınan Komisyon Kararları',
          type: DocFieldType.multiCheck,
          options: [
            'Okul Rehberlik ve Psikolojik Danışma Programının belirlenen genel, yerel ve özel hedefler doğrultusunda hazırlanarak e-Rehberlik sistemine işlenmesine karar verildi.',
            'Sınıf rehber öğretmenlerince Sınıf Risk Haritası ve Öğrenci Tanıma Formlarının (ÖTF) gizlilik ilkesine uygun olarak Ekim ayı sonuna kadar tamamlanmasına karar verildi.',
            'Akran zorbalığı ve davranışsal uyum güçlüğü gözlenen durumlarda disiplin işleminden önce koruyucu-önleyici rehberlik görüşmelerinin etkin işletilmesine karar verildi.',
            'Üst öğrenime geçiş sürecindeki sınıflara yönelik deneme analizi sonrası bireysel çalışma programı ve hedef takibi yapılmasına karar verildi.',
            'Velilere yönelik dönem içinde ergenlik/gelişim özellikleri ve bilinçli teknoloji kullanımı konulu seminer/bülten paylaşılmasına karar verildi.',
            'ÖDDK ve Disiplin Kuruluna sevk edilen her öğrenci dosyası için karar öncesinde PDR Servisi tarafından psiko-sosyal vaka inceleme raporu hazırlanmasına karar verildi.',
            'Risk haritası sonuçlarına göre devamsızlık, akademik düşüş veya duygusal zorlanma yaşayan öğrenciler için sınıf rehber öğretmeni - PDR eşgüdüm toplantıları yapılmasına karar verildi.',
            'Psikososyal koruma, önleme ve krize müdahale ekibinin olası yas, travma ve afet durumlarına karşı eylem planını hazır bulundurmasına karar verildi.',
            'Rehberlik görüşme kayıtlarının ve öğrenci özel bilgilerinin MEB RPDH Yönetmeliği gizlilik ilkelerine uygun şekilde kilitli dolapta muhafaza edilmesine karar verildi.',
          ],
          defaultValue: [
            'Okul Rehberlik ve Psikolojik Danışma Programının belirlenen genel, yerel ve özel hedefler doğrultusunda hazırlanarak e-Rehberlik sistemine işlenmesine karar verildi.',
            'Sınıf rehber öğretmenlerince Sınıf Risk Haritası ve Öğrenci Tanıma Formlarının (ÖTF) gizlilik ilkesine uygun olarak Ekim ayı sonuna kadar tamamlanmasına karar verildi.',
            'Akran zorbalığı ve davranışsal uyum güçlüğü gözlenen durumlarda disiplin işleminden önce koruyucu-önleyici rehberlik görüşmelerinin etkin işletilmesine karar verildi.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Komisyon', 'Rehberlik ve Psikolojik Danışma Hizmetleri Yürütme Komisyonu'),
        MapEntry('Dönem / Tarih', '${_str(a, "termType")} • ${_str(a, "date", _today())}'),
        MapEntry('Komisyon Başkanı', '${ctx.principalName} (${ctx.principalTitle})'),
      ],
      composeBody: (a, ctx) => '''
MEB Rehberlik ve Psikolojik Danışma Hizmetleri Yönetmeliği uyarınca; ${ctx.academicYear} Eğitim ve Öğretim Yılında ${ctx.schoolName} bünyesinde yürütülecek rehberlik hizmetlerini planlamak ve kurum içi iş birliğini sağlamak üzere "${_str(a, 'termType')}" ${_str(a, 'date', _today())} tarihinde ${ctx.principalTitle} ${ctx.principalName} başkanlığında toplanmıştır.

KOMİSYON ÜYELERİ:
${_numberedLines(_list(a, 'members'))}

OKUL ÖZEL VE YEREL REHBERLİK ÖNCELİKLERİ:
${_numberedLines(_list(a, 'localGoals'))}

ALINAN KOMİSYON KARARLARI:
${_numberedLines(_list(a, 'decisions'), prefix: 'Karar ')}

İşbu tutanak komisyon üyelerince okunarak imza altına alınmıştır.''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(5)) DocSigner(name: m, title: 'Komisyon Üyesi'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'Komisyon Başkanı'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'bep_gelistirme_birimi_tutanagi',
      code: '1.5',
      categoryId: 'idari_kurul_komisyon',
      title: 'BEP (Bireyselleştirilmiş Eğitim Programı) Geliştirme Birimi Tutanağı',
      subtitle: 'Kaynaştırma/bütünleştirme öğrencileri için BEP birimi kuruluşu, sınav tedbirleri ve destek eğitim kararları',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.accessibility_new_rounded,
      questions: [
        const DocQuestionField(key: 'targetClass', label: 'Öğrencinin Şubesi (Genel Kuruluş ise ilk şubeyi bırakabilirsiniz)', type: DocFieldType.classSelect),
        const DocQuestionField(key: 'students', label: 'BEP Kapsamındaki Öğrenci(ler)', type: DocFieldType.multiStudentSelect),
        DocQuestionField(key: 'date', label: 'Toplantı Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'unitChair', label: 'BEP Birim Başkanı (Müdür / Görevlendirilen Müdür Yardımcısı)', type: DocFieldType.staffSelect),
        const DocQuestionField(key: 'members', label: 'BEP Birimi Üyeleri (Rehber Öğretmen, Sınıf ve Ders Öğretmenleri)', type: DocFieldType.multiStaffSelect, required: true),
        const DocQuestionField(
          key: 'decisions',
          label: 'Alınan BEP ve Eğitim-Ölçme Uyarlama Kararları',
          type: DocFieldType.multiCheck,
          options: [
            'RAM Eğitsel Değerlendirme ve Tanılama Raporu doğrultusunda öğrencinin eğitsel performans düzeyi dikkate alınarak tüm derslerden yıllık BEP hazırlanmasına karar verildi.',
            'Öğrencinin sınıf içi oturma düzeninin öğretmeni ve tahtayı en rahat görebileceği ön sıralarda planlanmasına ve akran desteğinin sağlanmasına karar verildi.',
            'Yazılı ve uygulamalı sınavlarda öğrencinin BEP kazanımlarına uygun farklılaştırılmış sınav soruları hazırlanmasına ve ihtiyaç halinde ek süre / okuyucu-kodlayıcı tedbiri uygulanmasına karar verildi.',
            'Destek Eğitim Odası kapsamında öğrencinin veli onayı ve haftalık ders çizelgesi doğrultusunda bireysel destek eğitimi almasının planlanmasına karar verildi.',
            'BEP hedeflerinin gerçekleşme düzeyinin dönem sonunda birimce yeniden değerlendirilerek veli ile paylaşılmasına karar verildi.',
            'Merkezi sınavlara (LGS / YKS / İOKBS) girecek özel gereksinimli öğrenciler için sınav tedbir hizmetlerinin (tek kişilik salon, okuyucu-kodlayıcı, ek süre) süresi içinde MEBBİS/RAM üzerinden takip edilmesine karar verildi.',
            'Öğrencinin sosyal kabulünü ve özgüvenini desteklemek amacıyla grup etkinliklerinde, törenlerde ve öğrenci kulüplerinde aktif rol verilmesine karar verildi.',
            'Ev ödevlerinin ve proje görevlerinin öğrencinin BEP kısa dönemli amaçlarına uygun zorlukta ve basamaklandırılmış şekilde verilmesine karar verildi.',
            'Sınıf içi davranış yönetiminde olumlu pekiştirme yöntemlerinin kullanılmasına ve veli ile aylık düzenli gelişim iletişimi kurulmasına karar verildi.',
          ],
          defaultValue: [
            'RAM Eğitsel Değerlendirme ve Tanılama Raporu doğrultusunda öğrencinin eğitsel performans düzeyi dikkate alınarak tüm derslerden yıllık BEP hazırlanmasına karar verildi.',
            'Öğrencinin sınıf içi oturma düzeninin öğretmeni ve tahtayı en rahat görebileceği ön sıralarda planlanmasına ve akran desteğinin sağlanmasına karar verildi.',
            'Yazılı ve uygulamalı sınavlarda öğrencinin BEP kazanımlarına uygun farklılaştırılmış sınav soruları hazırlanmasına ve ihtiyaç halinde ek süre / okuyucu-kodlayıcı tedbiri uygulanmasına karar verildi.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Birim Adı', 'Bireyselleştirilmiş Eğitim Programı (BEP) Geliştirme Birimi'),
        if (_list(a, 'students').isNotEmpty) MapEntry('İlgili Öğrenci(ler)', _list(a, 'students').join(', ')),
        MapEntry('Toplantı Tarihi', _str(a, 'date', _today())),
        MapEntry('Birim Başkanı', _str(a, 'unitChair', ctx.principalName)),
      ],
      composeBody: (a, ctx) {
        final sts = _list(a, 'students');
        return '''
MEB Özel Eğitim Hizmetleri Yönetmeliği hükümleri doğrultusunda; kurumumuz ${ctx.schoolName} bünyesinde kaynaştırma/bütünleştirme yoluyla eğitimlerine devam eden öğrencilerimizin eğitsel performanslarını değerlendirmek ve Bireyselleştirilmiş Eğitim Programlarını (BEP) planlamak üzere BEP Geliştirme Birimi ${_str(a, 'date', _today())} tarihinde toplanmıştır.
${sts.isNotEmpty ? '\nDEĞERLENDİRİLEN ÖĞRENCİ(LER):\n${_numberedLines(sts)}\n' : ''}
BİRİM ÜYELERİ:
${_numberedLines(_list(a, 'members'))}

ALINAN BEP BİRİM KARARLARI:
${_numberedLines(_list(a, 'decisions'), prefix: 'Karar ')}

İşbu BEP Geliştirme Birimi tutanağı katılımcılarca imza altına alınarak Okul Müdürlüğünün onayına sunulmuştur.''';
      },
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(5)) DocSigner(name: m, title: 'BEP Birimi Üyesi'),
        DocSigner(name: _str(a, 'unitChair', ctx.principalName), title: 'BEP Birim Başkanı'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'UYGUNDUR'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'oddk_disiplin_onur_kurulu_tutanagi',
      code: '1.6',
      categoryId: 'idari_kurul_komisyon',
      title: 'ÖDDK (Öğrenci Davranışlarını Değerlendirme) / Disiplin ve Onur Kurulu Tutanağı',
      subtitle: 'Kurul kuruluşu, olumlu davranış ödüllendirme, örnek öğrenci seçimi veya davranış değerlendirme kararları',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.balance_rounded,
      questions: [
        const DocQuestionField(
          key: 'boardType',
          label: 'Kurul Türü',
          type: DocFieldType.dropdown,
          options: [
            'Öğrenci Davranışlarını Değerlendirme Kurulu (ÖDDK)',
            'Okul Öğrenci Ödül ve Disiplin Kurulu',
            'Okul Onur Kurulu Toplantısı',
          ],
          defaultValue: 'Öğrenci Davranışlarını Değerlendirme Kurulu (ÖDDK)',
        ),
        const DocQuestionField(
          key: 'agendaMode',
          label: 'Toplantı Gündem Konusu',
          type: DocFieldType.dropdown,
          options: [
            'Sene Başı Kurul Görev Dağılımı ve Önleyici Çalışma İlkeleri',
            'Olumlu Davranış / Örnek Öğrenci / Onur Belgesi Ödüllendirme Değerlendirmesi',
            'Öğrenci Davranış İnceleme ve Yaptırım / Rehberlik Yönlendirme Kararı',
          ],
          defaultValue: 'Sene Başı Kurul Görev Dağılımı ve Önleyici Çalışma İlkeleri',
        ),
        DocQuestionField(key: 'date', label: 'Toplantı Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'chair', label: 'Kurul Başkanı (Müdür Başyardımcısı / Müdür Yardımcısı)', type: DocFieldType.staffSelect),
        const DocQuestionField(key: 'members', label: 'Kurul Üyesi Öğretmenler ve Rehberlik Temsilcisi', type: DocFieldType.multiStaffSelect, required: true),
        const DocQuestionField(
          key: 'caseSummary',
          label: 'Görüşülen Öğrenci / Ödül / Olay Özeti (Varsa)',
          type: DocFieldType.multiline,
          hint: 'Ödüllendirilen öğrenciler veya incelenen davranış dosyası hakkında kısa açıklama yazabilirsiniz...',
        ),
        const DocQuestionField(
          key: 'decisions',
          label: 'Alınan Kurul Kararları',
          type: DocFieldType.multiCheck,
          options: [
            'Okul içinde olumlu davranışların, nezaket kurallarının ve akademik çabanın teşvik edilmesi amacıyla her ay örnek davranış sergileyen öğrencilerin ödüllendirilmesine karar verildi.',
            'Olumsuz davranış eğilimi gözlenen öğrencilerde öncelikle sınıf rehber öğretmeni ve PDR servisi aracılığıyla nedenlerin araştırılmasına ve veli iş birliğinin sağlanmasına karar verildi.',
            'Kurula intikal eden dosya ve beyanların ilgili MEB Kurum Yönetmeliği hükümleri, öğrencinin yaşı, gelişim özellikleri ve üstün yararı gözetilerek gizlilik içinde karara bağlanmasına karar verildi.',
            'Akran nezaketi, okul eşyalarını koruma ve devamsızlığın azaltılması konularında Onur Kurulu / öğrenci temsilcileri ile ortak farkındalık kampanyası yürütülmesine karar verildi.',
            'Yaptırım gerektiren durumlarda kurula sevkten önce MEB İlköğretim Yönetmeliği Md. 54 kapsamında sözlü uyarı, EK-9 öğrenci sözleşmesi ve veli önlem görüşmesi adımlarının tamamlanıp tamamlanmadığının kurulca kontrol edilmesine karar verildi.',
            'Hakkında inceleme yapılan hiçbir öğrenciye yazılı/sözlü savunması alınmadan ve Okul Rehberlik (PDR) Servisi kanaat raporu incelenmeden yaptırım uygulanmamasına karar verildi.',
            'Onarıcı disiplin anlayışı doğrultusunda maddi zararın giderilmesi, samimi özür ve akran uzlaşmasının hafifletici neden olarak dikkate alınmasına karar verildi.',
            'Ders yılı içinde yaptırım almış olup sonrasında davranışlarını olumlu yönde düzelten öğrencilerin durumlarının yıl sonu kurulunda ceza kaldırma/silme açısından değerlendirilmesine karar verildi.',
          ],
          defaultValue: [
            'Okul içinde olumlu davranışların, nezaket kurallarının ve akademik çabanın teşvik edilmesi amacıyla her ay örnek davranış sergileyen öğrencilerin ödüllendirilmesine karar verildi.',
            'Olumsuz davranış eğilimi gözlenen öğrencilerde öncelikle sınıf rehber öğretmeni ve PDR servisi aracılığıyla nedenlerin araştırılmasına ve veli iş birliğinin sağlanmasına karar verildi.',
            'Kurula intikal eden dosya ve beyanların ilgili MEB Kurum Yönetmeliği hükümleri, öğrencinin yaşı, gelişim özellikleri ve üstün yararı gözetilerek gizlilik içinde karara bağlanmasına karar verildi.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Kurul Adı', _str(a, 'boardType')),
        MapEntry('Toplantı Konusu', _str(a, 'agendaMode')),
        MapEntry('Toplantı Tarihi', _str(a, 'date', _today())),
        MapEntry('Kurul Başkanı', _str(a, 'chair', ctx.principalName)),
      ],
      composeBody: (a, ctx) {
        final summary = _str(a, 'caseSummary');
        return '''
MEB Eğitim Kurumları Yönetmeliği ilgili maddeleri uyarınca oluşturulan "${_str(a, 'boardType')}", "${_str(a, 'agendaMode')}" gündemiyle ${_str(a, 'date', _today())} tarihinde ${_str(a, 'chair', ctx.principalName)} başkanlığında toplanmıştır.

KURUL ÜYELERİ:
${_numberedLines(_list(a, 'members'))}
${summary.isNotEmpty ? '\nGÖRÜŞÜLEN DOSYA / KONU ÖZETİ:\n$summary\n' : ''}
ALINAN KURUL KARARLARI:
${_numberedLines(_list(a, 'decisions'), prefix: 'Karar ')}

İşbu kurul karar tutanağı katılımcılarca imza altına alınarak Okul Müdürlüğünün onayına sunulmuştur.''';
      },
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(4)) DocSigner(name: m, title: 'Kurul Üyesi'),
        DocSigner(name: _str(a, 'chair', ctx.principalName), title: 'Kurul Başkanı'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'UYGUNDUR'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'sosyal_etkinlikler_kurulu_tutanagi',
      code: '1.7',
      categoryId: 'idari_kurul_komisyon',
      title: 'Sosyal Etkinlikler Kurulu ve Kulüp-Tören Planlama Tutanağı',
      subtitle: 'Sosyal Etkinlikler Yönetmeliği uyarınca öğrenci kulüpleri, toplum hizmeti ve belirli günler planlaması',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.diversity_1_rounded,
      questions: [
        DocQuestionField(key: 'date', label: 'Toplantı Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'chair', label: 'Sosyal Etkinlikler Kurulu Başkanı (Müdür / Md. Yrd.)', type: DocFieldType.staffSelect),
        const DocQuestionField(key: 'members', label: 'Kurul Üyeleri (Danışman Öğretmen Temsilcileri)', type: DocFieldType.multiStaffSelect, required: true),
        const DocQuestionField(
          key: 'decisions',
          label: 'Sosyal Etkinlikler Kurulu Yıllık Planlama Kararları',
          type: DocFieldType.multiCheck,
          options: [
            'Okulda açılacak öğrenci kulüplerinin öğrenci ilgi/istekleri ve öğretmen branşları dikkate alınarak belirlenmesine ve danışman öğretmen görevlendirmelerinin yapılmasına karar verildi.',
            'Tüm öğrenci kulüplerinin yıllık çalışma planlarını ve toplum hizmeti projelerini Ekim ayı içerisinde hazırlayarak Sosyal Etkinlikler Kuruluna teslim etmesine karar verildi.',
            'Belirli gün ve haftalar ile milli bayram/anma törenlerinin görevli kulüp ve komisyonlarca yıllık takvime uygun hazırlanmasına karar verildi.',
            'Öğrencilerin katıldığı bilimsel, sosyal, kültürel, sanatsal ve sportif etkinliklerin e-Okul Sosyal Etkinlik Modülüne zamanında işlenmesine karar verildi.',
            'Okul dışı inceleme gezileri, müze/bilim merkezi ziyaretleri ve yarışma katılımlarında Sosyal Etkinlikler Yönetmeliği onay ve veli izin prosedürlerine eksiksiz uyulmasına karar verildi.',
            'Her öğrenci kulübünün demokratik seçimle yönetim ve denetim kurulunu oluşturmasına ve en az bir toplum hizmeti çalışması planlamasına karar verildi.',
            'Okul dergisi, duvar gazetesi, şiir dinletisi, münazara, satranç ve spor turnuvalarının dönem içine dengeli yayılmasına karar verildi.',
            'Sosyal etkinlikler kapsamında veli veya öğrencilerden zorunlu bağış/ücret talep edilmemesine ve fırsat eşitliğinin gözetilmesine karar verildi.',
          ],
          defaultValue: [
            'Okulda açılacak öğrenci kulüplerinin öğrenci ilgi/istekleri ve öğretmen branşları dikkate alınarak belirlenmesine ve danışman öğretmen görevlendirmelerinin yapılmasına karar verildi.',
            'Tüm öğrenci kulüplerinin yıllık çalışma planlarını ve toplum hizmeti projelerini Ekim ayı içerisinde hazırlayarak Sosyal Etkinlikler Kuruluna teslim etmesine karar verildi.',
            'Belirli gün ve haftalar ile milli bayram/anma törenlerinin görevli kulüp ve komisyonlarca yıllık takvime uygun hazırlanmasına karar verildi.',
            'Öğrencilerin katıldığı bilimsel, sosyal, kültürel, sanatsal ve sportif etkinliklerin e-Okul Sosyal Etkinlik Modülüne zamanında işlenmesine karar verildi.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Kurul Adı', 'Sosyal Etkinlikler Kurulu'),
        MapEntry('Eğitim-Öğretim Yılı', ctx.academicYear),
        MapEntry('Toplantı Tarihi', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
MEB Eğitim Kurumları Sosyal Etkinlikler Yönetmeliği hükümleri uyarınca; ${ctx.academicYear} Eğitim ve Öğretim Yılında ${ctx.schoolName} bünyesinde yürütülecek öğrenci kulübü, toplum hizmeti, tören, gezi ve sosyal-kültürel etkinlikleri planlamak amacıyla Sosyal Etkinlikler Kurulu ${_str(a, 'date', _today())} tarihinde toplanmıştır.

KURUL BAŞKANI: ${_str(a, 'chair', ctx.principalName)}
KURUL ÜYELERİ:
${_numberedLines(_list(a, 'members'))}

ALINAN KARARLAR:
${_numberedLines(_list(a, 'decisions'), prefix: 'Karar ')}

İşbu tutanak imza altına alınarak yürürlüğe konulmuştur.''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(4)) DocSigner(name: m, title: 'Kurul Üyesi Danışman Öğretmen'),
        DocSigner(name: _str(a, 'chair', ctx.principalName), title: 'Kurul Başkanı'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'OLUR'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'devamsizlik_onleme_komisyonu_tutanagi',
      code: '1.8',
      categoryId: 'idari_kurul_komisyon',
      title: 'Devamsızlığı Önleme, Müdahale ve Yönlendirme Komisyonu Tutanağı',
      subtitle: 'Sürekli devamsız / risk altındaki öğrenciler için erken uyarı, veli iletişimi ve önleyici eylem kararları',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.person_pin_circle_rounded,
      questions: [
        DocQuestionField(key: 'date', label: 'Toplantı Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'members', label: 'Komisyon Üyeleri (İdareci, Rehber Öğretmen, Sınıf Rehber Öğretmenleri)', type: DocFieldType.multiStaffSelect, required: true),
        const DocQuestionField(key: 'targetClasses', label: 'İncelenen Şubeler (Opsiyonel)', type: DocFieldType.multiClassSelect),
        const DocQuestionField(
          key: 'decisions',
          label: 'Devamsızlığı Önleme Eylem Kararları',
          type: DocFieldType.multiCheck,
          options: [
            'Günlük yoklama verilerinin ilk ders sonunda idarece taranarak gelmeyen öğrencilerin velilerine SMS/telefon ile anlık bildirim yapılmasına karar verildi.',
            'Özürsüz devamsızlığı 5, 10 ve 15 güne ulaşan öğrencilerin velilerine resmi devamsızlık uyarı tebligatı gönderilmesine ve yüz yüze görüşmeye davet edilmesine karar verildi.',
            'Ekonomik, sağlık veya ailevi nedenlerle devamsızlık riski taşıyan öğrencilerin Rehberlik Servisi tarafından bireysel izlemeye alınmasına karar verildi.',
            'Okula aidiyeti güçlendirmek amacıyla risk grubundaki öğrencilerin sosyal kulüp, spor takımı ve okul içi sorumluluk projelerine dahil edilmesine karar verildi.',
            'Özür belgesi ve sağlık raporlarının özrün bitiminden itibaren yasal 5 iş günü içinde idareye teslim edilmesi kuralının tüm velilere yazılı olarak hatırlatılmasına karar verildi.',
            'İlk derse sürekli geç kalma eğilimi gösteren öğrencilerin nedenlerinin sınıf rehber öğretmenlerince araştırılarak servis/ulaşım kaynaklı aksaklıkların giderilmesine karar verildi.',
            'Sürekli devamsız durumuna düşme riski taşıyan öğrenciler için gerekirse ev ziyareti yapılmasına ve ilgili mülki/sosyal birimlerle mevzuat çerçevesinde iş birliği kurulmasına karar verildi.',
          ],
          defaultValue: [
            'Günlük yoklama verilerinin ilk ders sonunda idarece taranarak gelmeyen öğrencilerin velilerine SMS/telefon ile anlık bildirim yapılmasına karar verildi.',
            'Özürsüz devamsızlığı 5, 10 ve 15 güne ulaşan öğrencilerin velilerine resmi devamsızlık uyarı tebligatı gönderilmesine ve yüz yüze görüşmeye davet edilmesine karar verildi.',
            'Ekonomik, sağlık veya ailevi nedenlerle devamsızlık riski taşıyan öğrencilerin Rehberlik Servisi tarafından bireysel izlemeye alınmasına karar verildi.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Komisyon Adı', 'Devamsızlığı Önleme, Müdahale ve Yönlendirme Komisyonu'),
        MapEntry('Toplantı Tarihi', _str(a, 'date', _today())),
        if (_list(a, 'targetClasses').isNotEmpty) MapEntry('Değerlendirilen Şubeler', _list(a, 'targetClasses').join(', ')),
      ],
      composeBody: (a, ctx) => '''
${ctx.academicYear} Eğitim ve Öğretim Yılında ${ctx.schoolName} öğrencilerinin okula düzenli devamlarının sağlanması, devamsızlık nedenlerinin erken aşamada tespit edilerek ortadan kaldırılması amacıyla Devamsızlığı Önleme, Müdahale ve Yönlendirme Komisyonu ${_str(a, 'date', _today())} tarihinde toplanmıştır.

KOMİSYON ÜYELERİ:
${_numberedLines(_list(a, 'members'))}

ALINAN ÖNLEYİCİ VE MÜDAHALE KARARLARI:
${_numberedLines(_list(a, 'decisions'), prefix: 'Karar ')}

İşbu tutanak komisyon üyelerince imza altına alınmıştır.''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(5)) DocSigner(name: m, title: 'Komisyon Üyesi'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'OLUR'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'stratejik_plan_kalite_web_ekibi',
      code: '1.9',
      categoryId: 'idari_kurul_komisyon',
      title: 'Stratejik Planlama, Kalite, Proje ve Resmi Web Yayın Ekibi Tutanağı',
      subtitle: 'Okul Gelişim/Stratejik Plan Ekibi, TÜBİTAK-eTwinning Proje Komisyonu veya MEB Web Yayın Ekibi tutanağı',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.rocket_launch_rounded,
      questions: [
        const DocQuestionField(
          key: 'teamType',
          label: 'Kurul / Ekip Seçimi',
          type: DocFieldType.dropdown,
          options: [
            'Okul Gelişim Yönetim Ekibi (OGYE) ve Stratejik Plan İzleme Ekibi',
            'Okul Resmi İnternet Sitesi (meb.k12.tr) Yayın ve İçerik Denetim Ekibi',
            'Ulusal ve Uluslararası Projeleri (TÜBİTAK, TEKNOFEST, eTwinning, Erasmus+) Yürütme Komisyonu',
          ],
          defaultValue: 'Okul Resmi İnternet Sitesi (meb.k12.tr) Yayın ve İçerik Denetim Ekibi',
        ),
        DocQuestionField(key: 'date', label: 'Kuruluş / Toplantı Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'members', label: 'Görevlendirilen Ekip Üyeleri', type: DocFieldType.multiStaffSelect, required: true),
        const DocQuestionField(
          key: 'decisions',
          label: 'Çalışma İlkeleri ve Kararlar',
          type: DocFieldType.multiCheck,
          options: [
            'Kurumsal haber, duyuru ve etkinlik paylaşımlarının Türkçenin doğru kullanımına, KVKK / öğrenci açık rıza kurallarına ve MEB İnternet Sitesi Yönergesine tam uygunlukla yayımlanmasına karar verildi.',
            'Okul stratejik planında yer alan yıllık performans göstergelerinin dönem sonlarında izlenerek gelişim raporu hazırlanmasına karar verildi.',
            'Öğrencilerin bilimsel araştırma ve proje kültürü kazanması için TÜBİTAK, TEKNOFEST ve eTwinning çağrı takvimlerinin zümrelere duyurulmasına karar verildi.',
            'Yapılan tüm çalışma ve içerik güncellemelerinin ekip dosyasında kayıt altına alınmasına karar verildi.',
          ],
          defaultValue: [
            'Kurumsal haber, duyuru ve etkinlik paylaşımlarının Türkçenin doğru kullanımına, KVKK / öğrenci açık rıza kurallarına ve MEB İnternet Sitesi Yönergesine tam uygunlukla yayımlanmasına karar verildi.',
            'Yapılan tüm çalışma ve içerik güncellemelerinin ekip dosyasında kayıt altına alınmasına karar verildi.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Ekip / Komisyon', _str(a, 'teamType')),
        MapEntry('Eğitim-Öğretim Yılı', ctx.academicYear),
        MapEntry('Tarih', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
${ctx.academicYear} Eğitim ve Öğretim Yılında ${ctx.schoolName} kurumsal kalite standartlarının yükseltilmesi amacıyla "${_str(a, 'teamType')}" oluşturulmuş ve ${_str(a, 'date', _today())} tarihinde çalışma esaslarını karara bağlamıştır.

GÖREVLİ EKİP ÜYELERİ:
${_numberedLines(_list(a, 'members'))}

ALINAN KARARLAR VE UYGULAMA ESASLARI:
${_numberedLines(_list(a, 'decisions'), prefix: 'Karar ')}''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(5)) DocSigner(name: m, title: 'Ekip Üyesi'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'OLUR'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'komisyon_kurulus_tutanagi',
      code: '1.10',
      categoryId: 'idari_kurul_komisyon',
      title: 'Genel Okul İçi Komisyon Kuruluş ve Görev Dağılım Tutanağı',
      subtitle: 'Bina Sınav Yürütme, Tören, Kılık-Kıyafet, Beslenme Dostu Okul vb. her türlü özel komisyon şablonu',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.verified_user_rounded,
      questions: [
        const DocQuestionField(
          key: 'commissionName',
          label: 'Komisyon Adı',
          type: DocFieldType.dropdown,
          options: [
            'Bina Sınav Yürütme ve Ölçme Değerlendirme Komisyonu',
            'Okul Sağlığı, Temiz Okul ve Beslenme Dostu Okul Ekibi',
            'Sıfır Atık ve Çevre Yönetimi Komisyonu',
            'Okul Kılık-Kıyafet Belirleme ve İzleme Komisyonu',
            'Mezuniyet, Yıllık ve Tanıtım Etkinlikleri Komisyonu',
          ],
          defaultValue: 'Bina Sınav Yürütme ve Ölçme Değerlendirme Komisyonu',
        ),
        DocQuestionField(key: 'date', label: 'Kuruluş / Toplantı Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'president', label: 'Komisyon Başkanı', type: DocFieldType.staffSelect),
        const DocQuestionField(key: 'members', label: 'Komisyon Üyeleri', type: DocFieldType.multiStaffSelect, required: true),
        const DocQuestionField(
          key: 'duties',
          label: 'Komisyon Çalışma İlkeleri / Görev Dağılımı',
          type: DocFieldType.multiCheck,
          options: [
            'Komisyon görev alanına giren iş ve işlemlerin ilgili MEB yönetmelik, yönerge ve genelgelerine uygun yürütülmesi.',
            'Dönemlik çalışma takviminin hazırlanarak öğretmen, öğrenci ve velilere zamanında duyurulması.',
            'Yapılan faaliyetlere ilişkin tutanak ve raporların düzenli olarak komisyon dosyasında arşivlenmesi.',
            'Dönem sonlarında yürütülen faaliyetlerin değerlendirilerek Okul Müdürlüğüne rapor sunulması.',
            'Komisyon kararlarının öğretmen, öğrenci ve veli panolarında şeffaflık ilkesiyle paylaşılması.',
            'Uygulama sürecinde tespit edilen fiziki veya idari iyileştirme önerilerinin tutanakla okul yönetimine bildirilmesi.',
            'Diğer okul içi kurul ve zümrelerle eşgüdüm içinde hareket edilerek kaynakların verimli kullanılması.',
          ],
          defaultValue: [
            'Komisyon görev alanına giren iş ve işlemlerin ilgili MEB yönetmelik, yönerge ve genelgelerine uygun yürütülmesi.',
            'Dönemlik çalışma takviminin hazırlanarak öğretmen, öğrenci ve velilere zamanında duyurulması.',
            'Yapılan faaliyetlere ilişkin tutanak ve raporların düzenli olarak komisyon dosyasında arşivlenmesi.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Komisyon Adı', _str(a, 'commissionName')),
        MapEntry('Eğitim-Öğretim Yılı', ctx.academicYear),
        MapEntry('Kuruluş Tarihi', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) {
        final comm = _str(a, 'commissionName', 'Okul İçi Komisyon');
        final pres = _str(a, 'president', ctx.principalName);
        final members = _list(a, 'members');
        final duties = _list(a, 'duties');
        return '''
${ctx.academicYear} Eğitim ve Öğretim Yılında ${ctx.schoolName} bünyesinde yürütülecek iş ve işlemlerin mevzuata uygun, planlı ve etkin biçimde gerçekleştirilmesi amacıyla "$comm" oluşturulmuştur.

KOMİSYON BAŞKANI: $pres
KOMİSYON ASİL ÜYELERİ:
${_numberedLines(members)}

ÇALIŞMA ESASLARI VE ALINAN KARARLAR:
${_numberedLines(duties)}

İşbu komisyon kuruluş ve görev dağılım tutanağı ${_str(a, 'date', _today())} tarihinde imza altına alınmıştır.''';
      },
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(5)) DocSigner(name: m, title: 'Komisyon Üyesi'),
        DocSigner(name: _str(a, 'president', ctx.principalName), title: 'Komisyon Başkanı'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'OLUR'), isApproval: true),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // BAŞLIK 2: MALİ İŞLER, TAŞINIR MAL, KANTİN, SERVİS VE İSG DENETİM KOMİSYONLARI
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'satin_alma_muayene_kabul_tutanagi',
      code: '2.1',
      categoryId: 'idari_mali_guvenlik_denetim',
      title: 'Satın Alma, Piyasa Araştırma ve Muayene-Kabul Komisyonu Tutanağı',
      subtitle: 'Doğrudan temin, piyasa fiyat araştırması veya alınan mal/hizmetin muayene ve kabul tutanağı',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.inventory_rounded,
      questions: [
        const DocQuestionField(
          key: 'docSubType',
          label: 'İşlem / Komisyon Türü',
          type: DocFieldType.dropdown,
          options: [
            'Muayene ve Teslim Alma (Kabul) Komisyonu Tutanağı',
            'Satın Alma ve Piyasa Fiyat Araştırma Komisyonu Kuruluş / Karar Tutanağı',
          ],
          defaultValue: 'Muayene ve Teslim Alma (Kabul) Komisyonu Tutanağı',
        ),
        DocQuestionField(key: 'date', label: 'Tutanak Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'vendorAndInvoice', label: 'Firma Adı / Fatura Tarih ve Sayısı (Varsa)', type: DocFieldType.text, hint: 'Örn: ABC Kırtasiye Ltd. Şti. - Fatura No: GIB2026000123'),
        const DocQuestionField(
          key: 'purchasedItems',
          label: 'Alınan / Muayene Edilen Mal veya Hizmet Kalemleri',
          type: DocFieldType.multiline,
          defaultValue: 'Okul eğitim-öğretim ve temizlik/bakım ihtiyaçları kapsamında temin edilen malzemeler.',
          required: true,
        ),
        const DocQuestionField(
          key: 'inspectionChecks',
          label: 'Komisyon Muayene, Piyasa Araştırması ve Kabul Tespit Maddeleri',
          type: DocFieldType.multiCheck,
          options: [
            'En az üç (3) farklı tedarikçiden alınan fiyat teklifleri karşılaştırılarak kamu yararına en uygun teklif belirlenmiştir.',
            'Teslim edilen malzemelerin fatura/irsaliye kalemleriyle miktar, birim, marka ve teknik özellik bakımından birebir uyumlu olduğu sayım ile doğrulandı.',
            'Ürün ambalajlarının sağlam olduğu, kırık/eksik/arızalı parça bulunmadığı ve garanti/kullanım belgelerinin tam olduğu görüldü.',
            'Hizmet/bakım-onarım işinin teknik şartnameye ve iş sağlığı güvenliği standartlarına uygun tamamlandığı yerinde kontrol edildi.',
            'Dayanıklı taşınırların Taşınır İşlem Fişi (TİF) kesilerek TKYS ambar ve zimmet kayıtlarına alınması uygun görüldü.',
            '4734 sayılı Kamu İhale Kanunu (Md. 22/d Doğrudan Temin) ve Harcama Belgeleri Yönetmeliği usullerine tam uygunluk sağlandı.',
          ],
          defaultValue: [
            'Teslim edilen malzemelerin fatura/irsaliye kalemleriyle miktar, birim, marka ve teknik özellik bakımından birebir uyumlu olduğu sayım ile doğrulandı.',
            'Ürün ambalajlarının sağlam olduğu, kırık/eksik/arızalı parça bulunmadığı ve garanti/kullanım belgelerinin tam olduğu görüldü.',
            'Dayanıklı taşınırların Taşınır İşlem Fişi (TİF) kesilerek TKYS ambar ve zimmet kayıtlarına alınması uygun görüldü.',
          ],
        ),
        const DocQuestionField(key: 'president', label: 'Komisyon Başkanı', type: DocFieldType.staffSelect),
        const DocQuestionField(key: 'members', label: 'Komisyon Üyeleri (En az 2 Üye)', type: DocFieldType.multiStaffSelect, required: true),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Komisyon İşlemi', _str(a, 'docSubType')),
        MapEntry('Tarih', _str(a, 'date', _today())),
        if (_str(a, 'vendorAndInvoice').isNotEmpty) MapEntry('Firma / Fatura Bilgisi', _str(a, 'vendorAndInvoice')),
      ],
      composeBody: (a, ctx) => '''
${_str(a, 'docSubType').toUpperCase()}

Kurumumuz ${ctx.schoolName} ihtiyaçları doğrultusunda temin edilen aşağıda yazılı mal/hizmet kalemleri, komisyonumuzca ${_str(a, 'date', _today())} tarihinde yerinde incelenmiş; miktar, nitelik ve teknik şartnameye/sipariş esaslarına tam uygun olduğu görülerek sağlam ve eksiksiz şekilde teslim alınması / kabulü oy birliği ile uygun görülmüştür.

MUAYENE EDİLEN MAL / HİZMET ÖZETİ:
${_str(a, 'purchasedItems')}

KOMİSYON KONTROL VE KABUL MADDELERİ:
${_numberedLines(_list(a, 'inspectionChecks'))}''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(4)) DocSigner(name: m, title: 'Komisyon Üyesi'),
        DocSigner(name: _str(a, 'president', ctx.vicePrincipals.isNotEmpty ? ctx.vicePrincipals.first.fullName : 'Komisyon Başkanı'), title: 'Komisyon Başkanı'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'OLUR / Harcama Yetkilisi'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'tasinir_sayim_hurda_komisyonu',
      code: '2.2',
      categoryId: 'idari_mali_guvenlik_denetim',
      title: 'Taşınır Mal (Demirbaş) Yıl Sonu Sayım ve Kayıttan Düşme Tutanağı',
      subtitle: 'Taşınır Mal Yönetmeliği uyarınca demirbaş sayımı veya ekonomik ömrünü tamamlayan eşya düşüm tutanağı',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.qr_code_scanner_rounded,
      questions: [
        const DocQuestionField(
          key: 'mode',
          label: 'Tutanak Konusu',
          type: DocFieldType.dropdown,
          options: [
            'Yıl Sonu Taşınır Mal / Demirbaş Sayım Komisyonu Tutanağı',
            'Kayıttan Düşme, Hurdaya Ayırma ve Değer Tespit Komisyonu Tutanağı',
          ],
          defaultValue: 'Yıl Sonu Taşınır Mal / Demirbaş Sayım Komisyonu Tutanağı',
        ),
        DocQuestionField(key: 'date', label: 'Sayım / Tespit Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'members', label: 'Sayım Komisyonu Başkan ve Üyeleri (Taşınır Kayıt Yetkilisi Dahil)', type: DocFieldType.multiStaffSelect, required: true),
        const DocQuestionField(
          key: 'tkysChecks',
          label: 'Taşınır Mal Sayım ve Kayıttan Düşme Tespit Maddeleri',
          type: DocFieldType.multiCheck,
          options: [
            'Tüm derslikler, laboratuvarlar, atölyeler, kütüphane ve idari odalardaki dayanıklı taşınırlar oda bazlı zimmet listeleriyle karşılaştırıldı.',
            'Taşınır Kayıt Yönetim Sistemi (TKYS) envanter kayıtları ile fiili sayım miktarlarının tam mutabakat içinde olduğu doğrulandı.',
            'Barkod/demirbaş numarası silinen veya yıpranan taşınırların etiketleri yenilendi.',
            'Ekonomik ömrünü tamamlamış, onarımı ekonomik olmayan ve kullanılamaz hale gelen taşınırlar Kayıttan Düşme Teklif ve Onay Tutanağına bağlandı.',
            'Ambar stoklarında bulunan tüketim malzemelerinin yıl sonu sayımı yapılarak devir cetvelleri hazırlandı.',
            'Etkileşimli tahtalar, bilgisayarlar, yazıcılar ve yangın/güvenlik ekipmanlarının çalışır durumda olduğu kontrol edildi.',
          ],
          defaultValue: [
            'Tüm derslikler, laboratuvarlar, atölyeler, kütüphane ve idari odalardaki dayanıklı taşınırlar oda bazlı zimmet listeleriyle karşılaştırıldı.',
            'Taşınır Kayıt Yönetim Sistemi (TKYS) envanter kayıtları ile fiili sayım miktarlarının tam mutabakat içinde olduğu doğrulandı.',
            'Etkileşimli tahtalar, bilgisayarlar, yazıcılar ve yangın/güvenlik ekipmanlarının çalışır durumda olduğu kontrol edildi.',
          ],
        ),
        const DocQuestionField(
          key: 'inventoryNote',
          label: 'Sayım / Tespit Edilen Demirbaş Durumu',
          type: DocFieldType.multiline,
          defaultValue: 'Okul derslikleri, laboratuvarlar, idari odalar ve ortak alanlarda bulunan dayanıklı taşınırlar (sıra, masa, etkileşimli tahta, bilişim ekipmanları) fiilen sayılmış ve Taşınır Kayıt Yönetim Sistemi (TKYS) kayıtlarıyla mutabakat sağlanmıştır.',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('İşlem Türü', _str(a, 'mode')),
        MapEntry('Sayım Tarihi', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
5018 sayılı Kamu Mali Yönetimi Kanunu ve Taşınır Mal Yönetmeliği hükümleri uyarınca oluşturulan komisyonumuzca ${_str(a, 'date', _today())} tarihinde kurumumuz ${ctx.schoolName} taşınır mal ve demirbaşlarının fiili kontrolü gerçekleştirilmiştir.

TESPİT VE DEĞERLENDİRME:
${_numberedLines(_list(a, 'tkysChecks'))}

${_str(a, 'inventoryNote')}

İşbu tutanak Taşınır Mal Yönetmeliği esaslarına göre düzenlenerek imza altına alınmıştır.''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(4)) DocSigner(name: m, title: 'Sayım Komisyonu Üyesi'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'ONAY'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'kantin_yemekhane_denetim_tutanagi',
      code: '2.3',
      categoryId: 'idari_mali_guvenlik_denetim',
      title: 'Okul Kantin / Yemekhane Aylık Denetim Komisyonu Raporu',
      subtitle: 'MEB Kantin Hijyen Yönetmeliği zorunlu aylık gıda güvenliği, fiyat tarifesi ve hijyen denetim formu',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.restaurant_rounded,
      questions: [
        const DocQuestionField(
          key: 'placeType',
          label: 'Denetlenen Birim',
          type: DocFieldType.dropdown,
          options: ['Okul Kantini', 'Okul Yemekhanesi ve Mutfak Alanı', 'Kantin ve Yemekhane Birlikte'],
          defaultValue: 'Okul Kantini',
        ),
        DocQuestionField(key: 'date', label: 'Denetim Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'members', label: 'Kantin Denetim Komisyonu Üyeleri', type: DocFieldType.multiStaffSelect, required: true),
        const DocQuestionField(
          key: 'checkedCriteria',
          label: 'Denetlenen ve Uygunluğu Kontrol Edilen Hususlar',
          type: DocFieldType.multiCheck,
          options: [
            'MEB genelgesi uyarınca okul kantinlerinde satışı yasak olan gıda ve içeceklerin (enerji içeceği, gazlı/kolalı içecek, kızartma, cips vb.) bulundurulmadığı kontrol edildi.',
            'Satışa sunulan ambalajlı ürünlerin Tarım ve Orman Bakanlığı onaylı olduğu ve Son Tüketim Tarihlerinin (STT/TETT) geçmediği kontrol edildi.',
            'Güncel fiyat listesinin öğrencilerin rahatça görebileceği görünür bir yerde asılı olduğu ve etiket fiyatlarıyla uyumlu olduğu görüldü.',
            'Kantin/yemekhane çalışanlarının hijyen eğitimi belgeleri, periyodik sağlık muayeneleri, iş önlüğü, bone ve eldiven kullanımı kontrol edildi.',
            'Soğuk zincir dolaplarının sıcaklık dereceleri, tezgah/zemin temizliği, çöp kovaları ve haşere önlemleri uygun bulundu.',
            'Yemekhane şahit numunelerinin steril kaplarda 72 saat süreyle uygun soğuklukta muhafaza edildiği kontrol edildi.',
            'İşletme kayıt belgesi, vergi levhası ve kira sözleşmesi yükümlülüklerinin güncel ve eksiksiz olduğu görüldü.',
            'Çiğ ve pişmiş gıdaların çapraz bulaşmayı önleyecek şekilde ayrı doğrama tahtası ve dolap bölmelerinde tutulduğu doğrulandı.',
            'Tost makinesi, çay ocağı, davlumbaz, elektrik panosu ve yangın söndürme tüplerinin güvenli ve temiz olduğu kontrol edildi.',
            'Kızartma yağı kullanılmadığı, fırınlama/haşlama usulüne uyulduğu ve taze meyve/süt/ayran satışının teşvik edildiği görüldü.',
            'Bulaşık yıkama suyunun sıcaklığı, kullanılan dezenfektanların Sağlık Bakanlığı onaylı olduğu ve gıdalardan ayrı depolandığı kontrol edildi.',
            'Çölyak veya gıda alerjisi bulunan öğrenciler için uygun ürün/bilgilendirme hassasiyetinin gözetildiği teyit edildi.',
          ],
          defaultValue: [
            'MEB genelgesi uyarınca okul kantinlerinde satışı yasak olan gıda ve içeceklerin (enerji içeceği, gazlı/kolalı içecek, kızartma, cips vb.) bulundurulmadığı kontrol edildi.',
            'Satışa sunulan ambalajlı ürünlerin Tarım ve Orman Bakanlığı onaylı olduğu ve Son Tüketim Tarihlerinin (STT/TETT) geçmediği kontrol edildi.',
            'Güncel fiyat listesinin öğrencilerin rahatça görebileceği görünür bir yerde asılı olduğu ve etiket fiyatlarıyla uyumlu olduğu görüldü.',
            'Kantin/yemekhane çalışanlarının hijyen eğitimi belgeleri, periyodik sağlık muayeneleri, iş önlüğü, bone ve eldiven kullanımı kontrol edildi.',
            'Soğuk zincir dolaplarının sıcaklık dereceleri, tezgah/zemin temizliği, çöp kovaları ve haşere önlemleri uygun bulundu.',
          ],
        ),
        const DocQuestionField(
          key: 'auditResult',
          label: 'Genel Denetim Sonucu ve Varsa Eksiklik / Uyarılar',
          type: DocFieldType.multiline,
          defaultValue: 'Yapılan denetimde hijyen, gıda güvenliği ve mevzuat kriterlerine genel olarak uyulduğu tespit edilmiş; temizlik ve ürün tazeliği hassasiyetinin sürdürülmesi işletmeciye tebliğ edilmiştir.',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Denetlenen Alan', _str(a, 'placeType')),
        MapEntry('Denetim Tarihi', _str(a, 'date', _today())),
        MapEntry('Mevzuat Dayanağı', 'MEB Okul Kantinlerine Dair Özel Hijyen Kuralları Yönetmeliği'),
      ],
      composeBody: (a, ctx) => '''
OKUL KANTİN / YEMEKHANE AYLIK DENETİM TUTANAĞI

MEB Okul Kantinlerine Dair Özel Hijyen Kuralları Yönetmeliği ve Okul Gıdası genelgeleri çerçevesinde, kurumumuz ${ctx.schoolName} bünyesindeki "${_str(a, 'placeType')}" komisyonumuzca ${_str(a, 'date', _today())} tarihinde denetlenmiştir.

KONTROL EDİLEN KRİTERLER:
${_numberedLines(_list(a, 'checkedCriteria'))}

DENETİM SONUCU VE DEĞERLENDİRME:
${_str(a, 'auditResult')}

İşbu aylık denetim raporu komisyonumuzca mahallinde düzenlenerek imza altına alınmıştır.''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(4)) DocSigner(name: m, title: 'Kantin Denetim Komisyonu Üyesi'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'GÖRÜLDÜ / ONAY'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'okul_servis_denetim_tutanagi',
      code: '2.4',
      categoryId: 'idari_mali_guvenlik_denetim',
      title: 'Okul Servis Araçları ve Taşımalı Eğitim Denetim Tutanağı',
      subtitle: 'Servis araçlarının güvenlik donanımı, rehber personel, emniyet kemeri ve evrak kontrol tutanağı',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.airport_shuttle_rounded,
      questions: [
        DocQuestionField(key: 'date', label: 'Denetim Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'plates', label: 'Denetlenen Servis Plakaları / Firma Bilgisi', type: DocFieldType.text, defaultValue: 'Okul öğrenci servis araçları tamamı'),
        const DocQuestionField(key: 'members', label: 'Servis Denetim Komisyonu Üyeleri', type: DocFieldType.multiStaffSelect, required: true),
        const DocQuestionField(
          key: 'checks',
          label: 'Kontrol Edilen Güvenlik Kriterleri',
          type: DocFieldType.multiCheck,
          options: [
            'Araç arkasında "OKUL TAŞITI" yazısı, ışıklı "DUR" levhası ve emniyet kemerlerinin her koltukta çalışır durumda olduğu kontrol edildi.',
            'Araçlarda mevzuata uygun yaş ve şartları taşıyan Rehber Personel bulunduğu teyit edildi.',
            'Sürücülerin SRC, psikoteknik, ehliyet ve adli sicil/güzergâh izin belgelerinin tam olduğu kontrol edildi.',
            'Öğrencilerin okul bahçesinde güvenli indirme-bindirme alanında alınıp bırakıldığı ve ayakta yolcu taşınmadığı denetlendi.',
            'Araç içi temizlik, ilk yardım çantası, yangın söndürme tüpü ve otomatik kapı güvenlik sistemleri kontrol edildi.',
            'Araç yaşlarının mevzuatta belirtilen yaş sınırını aşmadığı, TÜVTÜRK muayene ve zorunlu koltuk ferdi kaza sigortalarının geçerli olduğu doğrulandı.',
            'Araç camlarının sabit/güvenlik kilitli olduğu ve araç içinde kesici/delici veya sabitlemesiz eşya bulunmadığı kontrol edildi.',
            'Son öğrenci indikten sonra araç içi kontrolü sağlayan sesli/ışıklı "Öğrenci Unutma Sensörü / Uyarı Sistemi"nin aktif çalıştığı test edildi.',
            'Sürücü ve rehber personelin araç içinde kesinlikle sigara kullanmadığı, kılık-kıyafet ve iletişim dilinin pedagojik kurallara uygun olduğu görüldü.',
            'Güncel öğrenci isim ve veli acil telefon listesinin her servis aracında rehber personelde mevcut olduğu teyit edildi.',
          ],
          defaultValue: [
            'Araç arkasında "OKUL TAŞITI" yazısı, ışıklı "DUR" levhası ve emniyet kemerlerinin her koltukta çalışır durumda olduğu kontrol edildi.',
            'Araçlarda mevzuata uygun yaş ve şartları taşıyan Rehber Personel bulunduğu teyit edildi.',
            'Öğrencilerin okul bahçesinde güvenli indirme-bindirme alanında alınıp bırakıldığı ve ayakta yolcu taşınmadığı denetlendi.',
            'Araç içi temizlik, ilk yardım çantası, yangın söndürme tüpü ve otomatik kapı güvenlik sistemleri kontrol edildi.',
            'Araç yaşlarının mevzuatta belirtilen yaş sınırını aşmadığı, TÜVTÜRK muayene ve zorunlu koltuk ferdi kaza sigortalarının geçerli olduğu doğrulandı.',
            'Araç camlarının sabit/güvenlik kilitli olduğu ve araç içinde kesici/delici veya sabitlemesiz eşya bulunmadığı kontrol edildi.',
            'Son öğrenci indikten sonra araç içi kontrolü sağlayan sesli/ışıklı "Öğrenci Unutma Sensörü / Uyarı Sistemi"nin aktif çalıştığı test edildi.',
            'Sürücü ve rehber personelin araç içinde kesinlikle sigara kullanmadığı, kılık-kıyafet ve iletişim dilinin pedagojik kurallara uygun olduğu görüldü.',
            'Güncel öğrenci isim ve veli acil telefon listesinin her servis aracında rehber personelde mevcut olduğu teyit edildi.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Denetim Konusu', 'Okul Servis Araçları Güvenlik Denetimi'),
        MapEntry('Tarih', _str(a, 'date', _today())),
        MapEntry('Kapsam / Plakalar', _str(a, 'plates')),
      ],
      composeBody: (a, ctx) => '''
Okul Servis Araçları Yönetmeliği hükümleri doğrultusunda öğrencilerimizin güvenli ulaşımını sağlamak amacıyla ${_str(a, 'date', _today())} tarihinde kurumumuz ${ctx.schoolName} servis araçları komisyonumuzca denetlenmiştir.

DENETLENEN HUSUSLAR:
${_numberedLines(_list(a, 'checks'))}

Tespit edilen hususlar kayıt altına alınmış olup güvenli taşıma kurallarına azami dikkat gösterilmesi sürücü ve rehber personellere hatırlatılmıştır.''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(4)) DocSigner(name: m, title: 'Servis Denetim Komisyonu Üyesi'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'ONAY'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'sivil_savunma_tahliye_tatbikati',
      code: '2.5',
      categoryId: 'idari_mali_guvenlik_denetim',
      title: 'İSG Acil Durum Ekipleri ve Deprem / Yangın Tahliye Tatbikatı Tutanağı',
      subtitle: 'Çök-Kapan-Tutun ve bina acil tahliye tatbikatı süresi, katılımcı sayısı ve İSG değerlendirme raporu',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.fire_extinguisher_rounded,
      questions: [
        const DocQuestionField(
          key: 'drillType',
          label: 'Tatbikat / Çalışma Türü',
          type: DocFieldType.dropdown,
          options: [
            'Deprem (Çök-Kapan-Tutun) ve Acil Bina Tahliye Tatbikatı',
            'Yangın Söndürme ve Acil Durum Tahliye Tatbikatı',
            'Sivil Savunma ve İSG Acil Durum Ekipleri (Söndürme-Kurtarma-Koruma-İlk Yardım) Kuruluş Tutanağı',
          ],
          defaultValue: 'Deprem (Çök-Kapan-Tutun) ve Acil Bina Tahliye Tatbikatı',
        ),
        DocQuestionField(key: 'date', label: 'Tatbikat Tarihi ve Saati', type: DocFieldType.text, defaultValue: '${_today()} - 10:15'),
        const DocQuestionField(key: 'evacuationDuration', label: 'Bina Tam Tahliye Süresi', type: DocFieldType.text, defaultValue: '2 Dakika 15 Saniye'),
        const DocQuestionField(key: 'participantInfo', label: 'Katılan Öğrenci ve Personel Sayısı', type: DocFieldType.text, defaultValue: 'Tüm okul öğrenci, öğretmen ve yardımcı personeli'),
        const DocQuestionField(key: 'members', label: 'Tatbikat Koordinasyon / Acil Durum Ekip Sorumluları', type: DocFieldType.multiStaffSelect, required: true),
        const DocQuestionField(
          key: 'observations',
          label: 'Tatbikat Uygulama Adımları ve Gözlemler',
          type: DocFieldType.multiCheck,
          options: [
            'Siren/alarm sesiyle birlikte tüm sınıflarda "Çök - Kapan - Tutun" pozisyonu kurallara uygun şekilde uygulandı.',
            'İkinci sirenle birlikte öğretmenlerin refakatinde acil çıkış yönlendirmeleri takip edilerek panik yapmadan toplanma alanına çıkıldı.',
            'Acil çıkış kapılarının açık ve tahliye koridorlarının engelsiz olduğu kontrol edildi.',
            'Toplanma alanında sınıf yoklamaları alınarak bina içinde kimsenin kalmadığı teyit edildi.',
            'Yangın tüpleri, elektrik/doğalgaz ana kesme vanaları ve ilk yardım çantalarının erişilebilirliği kontrol edildi.',
            'Özel gereksinimli (kaynaştırma/fiziksel engelli) öğrencilerin görevli refakatçi öğretmenleriyle güvenli tahliyesi sağlandı.',
            'Söndürme, Kurtarma, Koruma ve İlk Yardım acil durum ekiplerinin görev yerlerine zamanında ulaştığı doğrulandı.',
            'Asansörlerin acil durumda kullanılmaması kuralına tam riayet edildiği ve kat kontrol sorumlularının son oda taramasını tamamladığı görüldü.',
            'Yangın dolapları, duman dedektörleri, acil durum aydınlatma armatürleri ve toplanma alanı levhalarının sağlam olduğu kontrol edildi.',
            'Tatbikat verilerinin MEBBİS İşyeri Sağlık ve Güvenlik Birimi (İSGB) modülüne işlenmesine karar verildi.',
          ],
          defaultValue: [
            'Siren/alarm sesiyle birlikte tüm sınıflarda "Çök - Kapan - Tutun" pozisyonu kurallara uygun şekilde uygulandı.',
            'İkinci sirenle birlikte öğretmenlerin refakatinde acil çıkış yönlendirmeleri takip edilerek panik yapmadan toplanma alanına çıkıldı.',
            'Acil çıkış kapılarının açık ve tahliye koridorlarının engelsiz olduğu kontrol edildi.',
            'Toplanma alanında sınıf yoklamaları alınarak bina içinde kimsenin kalmadığı teyit edildi.',
          ],
        ),
        const DocQuestionField(
          key: 'includeStaffSignatureTable',
          label: 'Tutanak Sonuna Öğretmen İmza Sirküsü Eklensin mi?',
          type: DocFieldType.yesNo,
          defaultValue: false,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Tatbikat Türü', _str(a, 'drillType')),
        MapEntry('Uygulama Tarihi / Saati', _str(a, 'date')),
        MapEntry('Toplam Tahliye Süresi', _str(a, 'evacuationDuration')),
        MapEntry('Katılımcı Kapsamı', _str(a, 'participantInfo')),
      ],
      composeBody: (a, ctx) => '''
ACİL DURUM VE TAHLİYE TATBİKATI RAPORU

6331 sayılı İş Sağlığı ve Güvenliği Kanunu ile MEB İşyerlerinde Acil Durumlar Hakkında Yönetmelik uyarınca; kurumumuz ${ctx.schoolName} öğrenci ve personelinin afet ve acil durum hazırlık düzeyini geliştirmek amacıyla ${_str(a, 'date')} tarihinde "${_str(a, 'drillType')}" gerçekleştirilmiştir.

UYGULAMA VE GÖZLEM MADDELERİ:
${_numberedLines(_list(a, 'observations'))}

Okul binasının tamamı "${_str(a, 'evacuationDuration')}" sürede güvenli toplanma alanına herhangi bir yaralanma veya aksaklık yaşanmaksızın tahliye edilmiş olup işbu tutanak kayıt altına alınmıştır.''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(4)) DocSigner(name: m, title: 'Acil Durum / Sivil Savunma Ekibi'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'ONAY'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'kutuphane_arsiv_ayiklama_komisyonu',
      code: '2.6',
      categoryId: 'idari_mali_guvenlik_denetim',
      title: 'Kütüphane Eser Seçimi ve Kurum Arşivi Ayıklama-İmha Komisyonu Tutanağı',
      subtitle: 'Okul/sınıf kütüphanesi kitap inceleme komisyonu veya saklama süresi dolan arşiv evrak ayıklama tutanağı',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.local_library_rounded,
      questions: [
        const DocQuestionField(
          key: 'commMode',
          label: 'Komisyon Görev Alanı',
          type: DocFieldType.dropdown,
          options: [
            'Okul Kütüphanesi Kaynaklarının Tespiti ve Eser İnceleme Komisyonu',
            'Kurum Arşivi Ayıklama ve İmha Komisyonu',
          ],
          defaultValue: 'Okul Kütüphanesi Kaynaklarının Tespiti ve Eser İnceleme Komisyonu',
        ),
        DocQuestionField(key: 'date', label: 'Toplantı Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'members', label: 'Komisyon Başkan ve Üyeleri', type: DocFieldType.multiStaffSelect, required: true),
        const DocQuestionField(
          key: 'decisions',
          label: 'Alınan İnceleme / Ayıklama Kararları',
          type: DocFieldType.multiCheck,
          options: [
            'Okul ve sınıf kitaplıklarına kazandırılacak eserlerin Milli Eğitimin temel amaçlarına, öğrencilerin gelişim düzeyine ve pedagojik ölçütlere uygunluğunun incelenerek kayıt altına alınmasına karar verildi.',
            'MEB Okul Kütüphaneleri Yönetmeliği çerçevesinde kütüphane envanter sayımının yapılmasına ve öğrencilerin kitap ödünç alma alışkanlığının teşvik edilmesine karar verildi.',
            'Devlet Arşiv Hizmetleri Hakkında Yönetmelik uyarınca saklama süresini dolduran evrakların usulüne uygun tasnif edilmesine, saklanması gereken belgelerin ise düzenli arşivlenmesine karar verildi.',
            'Bağış veya satın alma yoluyla gelen kitapların komisyon inceleme tutanağı olmadan kütüphane/sınıf raflarına konulmamasına karar verildi.',
            'Yıpranmış ve kullanılamaz durumdaki materyallerin kütüphane demirbaş kayıtlarından mevzuat usulünce düşülmesine karar verildi.',
            'Diplomalara, öğrenim belgelerine, kütük defterlerine ve özlük dosyalarına ilişkin süresiz saklanması zorunlu arşiv belgelerinin imha kapsamı dışında tutularak güvenli koruma altına alınmasına karar verildi.',
          ],
          defaultValue: [
            'Okul ve sınıf kitaplıklarına kazandırılacak eserlerin Milli Eğitimin temel amaçlarına, öğrencilerin gelişim düzeyine ve pedagojik ölçütlere uygunluğunun incelenerek kayıt altına alınmasına karar verildi.',
            'MEB Okul Kütüphaneleri Yönetmeliği çerçevesinde kütüphane envanter sayımının yapılmasına ve öğrencilerin kitap ödünç alma alışkanlığının teşvik edilmesine karar verildi.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Komisyon Adı', _str(a, 'commMode')),
        MapEntry('Tarih', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
${ctx.academicYear} Eğitim ve Öğretim Yılında ${ctx.schoolName} bünyesinde oluşturulan "${_str(a, 'commMode')}", ${_str(a, 'date', _today())} tarihinde toplanarak aşağıdaki kararları almıştır:

KOMİSYON ÜYELERİ:
${_numberedLines(_list(a, 'members'))}

ALINAN KARARLAR:
${_numberedLines(_list(a, 'decisions'), prefix: 'Karar ')}''',
      buildSigners: (a, ctx) => [
        for (final m in _list(a, 'members').take(4)) DocSigner(name: m, title: 'Komisyon Üyesi'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'OLUR'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'okul_aile_birligi_tutanagi',
      code: '2.7',
      categoryId: 'idari_mali_guvenlik_denetim',
      title: 'Okul-Aile Birliği (OAB) Yönetim / Genel Kurul Toplantı Tutanağı',
      subtitle: 'MEB Okul-Aile Birliği Yönetmeliği kapsamında veli-okul iş birliği, bütçe ve etkinlik karar tutanağı',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.handshake_rounded,
      questions: [
        const DocQuestionField(
          key: 'meetingKind',
          label: 'Toplantı Türü',
          type: DocFieldType.dropdown,
          options: [
            'Okul-Aile Birliği Olağan Genel Kurul Toplantısı',
            'Okul-Aile Birliği Yönetim Kurulu Karar Toplantısı',
            'Okul-Aile Birliği Denetleme Kurulu Rapor Tutanağı',
          ],
          defaultValue: 'Okul-Aile Birliği Yönetim Kurulu Karar Toplantısı',
        ),
        DocQuestionField(key: 'date', label: 'Toplantı Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'boardMembers', label: 'OAB Başkan ve Yönetim Üyeleri (İdare + Veli Temsilcileri)', type: DocFieldType.multiline, defaultValue: 'OAB Başkanı, Başkan Yardımcısı, Muhasip Üye, Yazman ve Okul Yönetimi Temsilcisi'),
        const DocQuestionField(
          key: 'decisions',
          label: 'Alınan OAB Kararları',
          type: DocFieldType.multiCheck,
          options: [
            'Okulun eğitim-öğretim ortamlarının iyileştirilmesi, temizlik, güvenlik ve bakım-onarım ihtiyaçlarının MEB Okul-Aile Birliği Yönetmeliği usullerine göre desteklenmesine karar verildi.',
            'Sosyal, kültürel, sportif etkinlikler ile belirli gün ve haftalarda yapılacak öğrenci çalışmalarının desteklenmesine karar verildi.',
            'İhtiyaç sahibi öğrencilerin eğitim materyali, kıyafet ve sosyal etkinlik katılımlarının gizlilik ve hakkaniyet ilkesiyle desteklenmesine karar verildi.',
            'Gelir-gider kayıtlarının TEFBİS sistemine ve resmi defterlere düzenli işlenmesine karar verildi.',
            'Gönüllü bağışların yalnızca Okul-Aile Birliği resmi banka hesabı üzerinden kabul edilmesine; kayıt/mezuniyet dönemlerinde velilerden zorunlu bağış istenmemesine karar verildi.',
            'Kantin ve benzeri yerlerin kiralama/işletme ödemelerinin sözleşme şartlarına uygun takip edilmesine karar verildi.',
            'Yapılan tüm harcamaların fatura/harcama belgeleriyle yönetim kurulu kararına bağlanmasına ve denetleme kurulunun incelemesine hazır tutulmasına karar verildi.',
            'Veli-okul iletişimini güçlendirmek amacıyla seminer, kermes ve aile katılım etkinliklerinin okul yönetimiyle koordineli planlanmasına karar verildi.',
          ],
          defaultValue: [
            'Okulun eğitim-öğretim ortamlarının iyileştirilmesi, temizlik, güvenlik ve bakım-onarım ihtiyaçlarının MEB Okul-Aile Birliği Yönetmeliği usullerine göre desteklenmesine karar verildi.',
            'Sosyal, kültürel, sportif etkinlikler ile belirli gün ve haftalarda yapılacak öğrenci çalışmalarının desteklenmesine karar verildi.',
            'Gelir-gider kayıtlarının TEFBİS sistemine ve resmi defterlere düzenli işlenmesine karar verildi.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Kurul / Toplantı', _str(a, 'meetingKind')),
        MapEntry('Tarih', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
MEB Okul-Aile Birliği Yönetmeliği hükümleri çerçevesinde ${ctx.schoolName} "${_str(a, 'meetingKind')}", ${_str(a, 'date', _today())} tarihinde toplanarak okul-veli iş birliği ve kurumsal destek süreçlerini görüşmüştür.

KATILIMCILAR / YÖNETİM ORGANLARI:
${_str(a, 'boardMembers')}

ALINAN KARARLAR:
${_numberedLines(_list(a, 'decisions'), prefix: 'Karar ')}''',
      buildSigners: (a, ctx) => [
        const DocSigner(name: 'OAB Yönetim Kurulu Başkanı', title: 'Okul-Aile Birliği Başkanı'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx)),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // BAŞLIK 3: PERSONEL GÖREVLENDİRME, TEBLİĞ VE İDARİ YAZILAR
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'personel_gorevlendirme_yazisi',
      code: '3.1',
      categoryId: 'idari_personel_yazi',
      title: 'Öğretmen / Personel Görevlendirme ve Tebliğ Yazısı',
      subtitle: 'Sınıf rehberliği, kulüp, zümre başkanlığı, komisyon, kurs/etüt veya tören resmi tebliği',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.officialLetter,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.assignment_ind_rounded,
      questions: [
        const DocQuestionField(key: 'docNumber', label: 'Sayı / Evrak No (Opsiyonel)', type: DocFieldType.text, defaultValue: 'İDARİ-GÖREV/2026-01'),
        DocQuestionField(key: 'date', label: 'Evrak Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'staff', label: 'Görevlendirilen Öğretmen / Personel', type: DocFieldType.staffSelect, required: true),
        const DocQuestionField(
          key: 'dutyType',
          label: 'Görevlendirme Konusu',
          type: DocFieldType.dropdown,
          options: [
            'Sınıf Rehber Öğretmenliği Görevlendirmesi',
            'Öğrenci Kulübü / Toplum Hizmeti Danışman Öğretmenliği Görevlendirmesi',
            'Zümre Başkanlığı Görevlendirmesi',
            'Rehberlik ve Psikolojik Danışma Hizmetleri Yürütme Komisyonu Üyeliği',
            'Bireyselleştirilmiş Eğitim Programı (BEP) Geliştirme Birimi Üyeliği',
            'Öğrenci Davranışlarını Değerlendirme / Ödül ve Disiplin Kurulu Üyeliği',
            'Satın Alma / Muayene ve Kabul / Kantin Denetim Komisyonu Üyeliği',
            'Destekleme ve Yetiştirme Kursu (DYK) / Akademik Etüt Görevlendirmesi',
            'Tören, Belirli Gün ve Haftalar Kutlama Komisyonu Görevlendirmesi',
            'Ortak Yazılı Sınav Salon Başkanı / Gözetmenlik Görevlendirmesi',
            'Nöbetçi Öğretmenlik / Nöbet Bölgesi Değişikliği Tebliği',
            'Okul Web Yayın / Stratejik Planlama ve Kalite Ekibi Görevlendirmesi',
          ],
          defaultValue: 'Sınıf Rehber Öğretmenliği Görevlendirmesi',
        ),
        const DocQuestionField(
          key: 'dutyDetail',
          label: 'Görev Yeri / Şube / Kulüp / Komisyon / Tarih Detayı',
          type: DocFieldType.text,
          hint: 'Örn: 7-A Şubesi Sınıf Rehber Öğretmenliği / Bilim ve Teknoloji Kulübü',
          required: true,
        ),
        const DocQuestionField(
          key: 'extraClause',
          label: 'Görev Kapsamı ve Ek Açıklama (Opsiyonel)',
          type: DocFieldType.multiline,
          hint: 'Örn: İlgili göreve ait yıllık çalışma planının 15 gün içinde idareye teslim edilmesi gerekmektedir.',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Sayı', _str(a, 'docNumber', '-')),
        MapEntry('Konu', _str(a, 'dutyType', 'Görevlendirme')),
        MapEntry('Tarih', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) {
        final staff = _str(a, 'staff', 'Sayın İlgili');
        final dutyType = _str(a, 'dutyType', 'Görevlendirme');
        final detail = _str(a, 'dutyDetail', 'belirtilen görev');
        final extra = _str(a, 'extraClause');
        return '''
Sayın $staff,

1739 sayılı Milli Eğitim Temel Kanunu ile Millî Eğitim Bakanlığı Okul Öncesi Eğitim ve İlköğretim / Ortaöğretim Kurumları Yönetmeliğinin ilgili hükümleri uyarınca; ${ctx.academicYear} Eğitim ve Öğretim Yılında kurumumuz ${ctx.schoolName} bünyesinde yürütülecek eğitim, öğretim ve yönetim faaliyetleri kapsamında "$dutyType" çerçevesinde "$detail" görevi Okul Müdürlüğümüzce tarafınıza verilmiştir.

Söz konusu görevin ilgili mevzuat esaslarına, yıllık çalışma takvimine, Öğretmenler Kurulu kararlarına ve kurum işleyiş ilkelerine uygun olarak zamanında ve titizlikle yürütülmesi; süreçle ilgili tutanak, plan ve raporların süresi içerisinde idareye teslim edilmesi hususunda bilgilerinizi ve gereğini rica ederim.${extra.isNotEmpty ? '\n\nEk Husus / Açıklama: $extra' : ''}''';
      },
      buildSigners: (a, ctx) => [
        DocSigner(name: _str(a, 'staff', 'Görevli Personel'), title: 'Aslını Elden Tebellüğ Eden (${_str(a, "date", _today())})'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx)),
      ],
    ),

    OfficialDocTemplate(
      id: 'genel_teblig_imza_sirkusu',
      code: '3.2',
      categoryId: 'idari_personel_yazi',
      title: 'Genel Tebliğ - Tebellüğ Belgesi (İmza Sirküsü)',
      subtitle: 'Üstte resmi duyuru veya mevzuat talimat metni, altta seçilen öğretmen/personel imza çizelgesi',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.circularSignatureTable,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.draw_rounded,
      questions: [
        const DocQuestionField(
          key: 'subject',
          label: 'Tebliğ Konusu / Başlığı',
          type: DocFieldType.text,
          defaultValue: 'Eğitim-Öğretim İşleyiş Esasları ve İdari Yazı Tebliği',
          required: true,
        ),
        DocQuestionField(key: 'date', label: 'Tebliğ Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(
          key: 'announcementText',
          label: 'Tebliğ Edilecek Metin / İdari Talimat Maddeleri',
          type: DocFieldType.multiCheck,
          options: [
            'Ders giriş-çıkış saatlerine riayet edilmesi, sınıf ders defterlerinin günlük işlenerek imzalanması ve öğrenci yoklamalarının ilk 5 dakikada eksiksiz alınması gerekmektedir.',
            'Nöbet görevine ilk dersten 20 dakika önce başlanması, son ders bitiminden 15 dakika sonrasına kadar sürdürülmesi ve nöbet bölgesinin kesinlikle terk edilmemesi gerekmektedir.',
            'Ortak yazılı sınav tarihlerinin, konu-soru dağılım tablolarının ve sınav sonuçlarının e-Okul / okul otomasyon sistemine mevzuatta belirtilen yasal süre içinde işlenmesi zorunludur.',
            'Sınav analizleri sonucunda kazanım başarısı düşük kalan konularda telafi ve eylem planı çalışmalarının zümre kararıyla yürütülmesi gerekmektedir.',
            'Kaynaştırma/bütünleştirme öğrencileri için hazırlanan BEP planlarına uygun ders işlenmesi ve ölçme-değerlendirme uyarlamalarının yapılması yasal zorunluluktur.',
            'Öğrencilerin ders saatleri içinde cep telefonu ve akıllı cihaz kullanmaması konusunda gerekli kontrollerin ders öğretmenlerince titizlikle sürdürülmesi gerekmektedir.',
            'Veli görüşmelerinin yalnızca belirlenen görüşme saatlerinde yapılması, ders esnasında veli kabul edilmemesi ve her görüşmenin tutanak altına alınması gerekmektedir.',
            'Okul bina, koridor, laboratuvar ve dersliklerde 6331 sayılı İş Sağlığı ve Güvenliği Kanunu ile kamu tasarruf tedbirlerine (enerji, su, sarf malzeme) azami özen gösterilecektir.',
            'Öğrencilere ait kişisel verilerin, sınav sonuçlarının ve fotoğraf/video görüntülerinin 6698 sayılı KVKK hükümleri gereği izinsiz paylaşılmaması gerekmektedir.',
            'Üst makamlarca gönderilen resmi yazı, duyuru ve yarışma şartnamelerinin süresi içinde incelenerek ilgili öğrenci ve velilere duyurulması gerekmektedir.',
            'Olumsuz öğrenci davranışlarında kurula sevk öncesi MEB Yönetmeliği Md. 54 kapsamında sözlü uyarı, EK-9 öğrenci sözleşmesi ve veli görüşmesi adımlarının eksiksiz tamamlanması gerekmektedir.',
            'Mazeret izin ve sağlık raporu bildirimlerinin ders ve nöbet planlamasının aksamaması için vaktinde idareye ulaştırılması gerekmektedir.',
            'MEB Eser İnceleme Komisyonu onayı bulunmayan yardımcı kaynak, fotokopi paket veya ticari materyallerin aldırılmaması gerekmektedir.',
            'Bayrak törenlerine, belirli gün ve hafta programlarına, öğretmenler kurulu ve zümre toplantılarına zamanında katılım sağlanması zorunludur.',
            '657 sayılı Devlet Memurları Kanunu, Kamu Görevlileri Etik Davranış İlkeleri ve kılık-kıyafet mevzuatına uygun hareket edilmesi gerekmektedir.',
          ],
          defaultValue: [
            'Ders giriş-çıkış saatlerine riayet edilmesi, sınıf ders defterlerinin günlük işlenerek imzalanması ve öğrenci yoklamalarının ilk 5 dakikada eksiksiz alınması gerekmektedir.',
            'Nöbet görevine ilk dersten 20 dakika önce başlanması, son ders bitiminden 15 dakika sonrasına kadar sürdürülmesi ve nöbet bölgesinin kesinlikle terk edilmemesi gerekmektedir.',
            'Ortak yazılı sınav tarihlerinin, konu-soru dağılım tablolarının ve sınav sonuçlarının e-Okul / okul otomasyon sistemine mevzuatta belirtilen yasal süre içinde işlenmesi zorunludur.',
            'Öğrencilere ait kişisel verilerin, sınav sonuçlarının ve fotoğraf/video görüntülerinin 6698 sayılı KVKK hükümleri gereği izinsiz paylaşılmaması gerekmektedir.',
          ],
        ),
        const DocQuestionField(
          key: 'customAnnouncement',
          label: 'Özel Duyuru / İl-İlçe MEM Resmi Yazı Özeti (Opsiyonel)',
          type: DocFieldType.multiline,
          hint: 'İl/İlçe MEM resmi yazı tarih-sayısı veya özel idari duyuru metnini buraya ekleyebilirsiniz...',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Konu', _str(a, 'subject', 'İdari Duyuru Tebliği')),
        MapEntry('Tebliğ Tarihi', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) {
        final items = _list(a, 'announcementText');
        final custom = _str(a, 'customAnnouncement');
        final buf = StringBuffer();
        buf.writeln(
          'Aşağıda belirtilen mevzuat hükümleri, resmi yazı ve idari işleyiş esasları ${ctx.schoolName} Müdürlüğü tarafından ilgili öğretmen ve personele tebliğ edilmiş olup; okuduğuna, bilgi edindiğine ve gereğini süresi içinde yerine getireceğine dair imza sirküsü aşağıdadır:',
        );
        if (custom.isNotEmpty) buf.writeln('\nRESMİ YAZI / ÖZEL DUYURU ÖZETİ:\n$custom');
        if (items.isNotEmpty) buf.writeln('\nTEBLİĞ EDİLEN HUSUSLAR:\n${_numberedLines(items)}');
        return buf.toString().trim();
      },
      buildSigners: (a, ctx) => [
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'personel_izin_mazeret_formu',
      code: '3.3',
      categoryId: 'idari_personel_yazi',
      title: 'Personel Günlük / Saatlik Mazeret İzin Formu',
      subtitle: 'İzin dilekçesi, boş ders/nöbet telafi planı ve İdare Olur onay kutusu tek sayfada',
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.event_busy_rounded,
      questions: [
        const DocQuestionField(key: 'staff', label: 'İzin Talep Eden Personel', type: DocFieldType.staffSelect, required: true),
        const DocQuestionField(
          key: 'leaveType',
          label: 'İzin Türü',
          type: DocFieldType.dropdown,
          options: [
            'Saatlik Mazeret İzni',
            'Günlük Mazeret İzni',
            'Sağlık / Poliklinik Muayene İzni',
            'Resmi Görevli - İzinli (Seminer / Sınav / Müsabaka)',
            'Evlilik / Babalık / Vefat (Ölüm) Mazeret İzni',
            'Süt İzni / Refakat İzni Talebi',
          ],
          defaultValue: 'Günlük Mazeret İzni',
        ),
        DocQuestionField(key: 'startDate', label: 'Başlangıç Tarihi / Saati', type: DocFieldType.text, defaultValue: '${_today()} 08:30'),
        DocQuestionField(key: 'endDate', label: 'Bitiş Tarihi / Saati (Göreve Başlama)', type: DocFieldType.text, defaultValue: '${_today()} 17:00'),
        const DocQuestionField(key: 'reason', label: 'Mazeret Açıklaması', type: DocFieldType.multiline, defaultValue: 'Şahsi / ailevi mazeretim nedeniyle belirtilen tarih ve saat aralığında izin talep ediyorum.'),
        const DocQuestionField(key: 'address', label: 'İzinde Bulunacağı Adres ve İletişim Telefonu', type: DocFieldType.text, defaultValue: 'Sistemde kayıtlı ikamet adresi ve cep telefonu numarası'),
        const DocQuestionField(key: 'substitutePlan', label: 'Boş Geçecek DersSaatleri / Nöbet Görevi Telafi Planı', type: DocFieldType.text, defaultValue: 'Nöbetçi müdür yardımcısı ve zümre öğretmenlerince ders/nöbet koordinasyonu sağlanacaktır.'),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Talep Eden Personel', _str(a, 'staff')),
        MapEntry('İzin Türü', _str(a, 'leaveType')),
        MapEntry('İzin Başlangıç', _str(a, 'startDate')),
        MapEntry('İzin Bitiş', _str(a, 'endDate')),
        MapEntry('İletişim / Adres', _str(a, 'address')),
        MapEntry('Ders / Nöbet Planlaması', _str(a, 'substitutePlan')),
      ],
      composeBody: (a, ctx) => '''
${ctx.schoolName.toUpperCase()} MÜDÜRLÜĞÜNE

Kurumunuzda öğretmen / personel olarak görev yapmaktayım. "${_str(a, 'reason')}" mazeretim sebebiyle ${_str(a, 'startDate')} ile ${_str(a, 'endDate')} tarih/saatleri arasında (${_str(a, 'leaveType')}) kapsamında izinli sayılmam hususunda;

Bilgilerinizi ve gereğini arz ederim.

İzin Süresince Ders / Nöbet Telafi Planı:
${_str(a, 'substitutePlan')}''',
      buildSigners: (a, ctx) => [
        DocSigner(name: _str(a, 'staff', 'Talep Eden'), title: 'İzin Talep Eden Personel'),
        DocSigner(
          name: ctx.vicePrincipals.isNotEmpty ? ctx.vicePrincipals.first.fullName : 'Müdür Yardımcısı',
          title: 'Uygun Görüşle Arz / Md. Yrd.',
        ),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'OLUR'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'gorev_yeri_belgesi',
      code: '3.4',
      categoryId: 'idari_personel_yazi',
      title: 'Resmi Görev Yeri (Çalışma) Belgesi',
      subtitle: 'Resmi kurumlara, bankalara, konsolosluk/vize işlemlerine veya üniversitelere verilmek üzere belge',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.officialLetter,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.workspace_premium_rounded,
      questions: [
        const DocQuestionField(key: 'staff', label: 'Personel Seçimi', type: DocFieldType.staffSelect, required: true),
        const DocQuestionField(key: 'tcNo', label: 'T.C. Kimlik Numarası (Opsiyonel)', type: DocFieldType.text),
        const DocQuestionField(key: 'startDateInfo', label: 'Kurumda Göreve Başlama Tarihi (Opsiyonel)', type: DocFieldType.text, hint: 'Örn: 01.09.2024'),
        const DocQuestionField(key: 'dutyTitle', label: 'Görev Unvanı / Branşı', type: DocFieldType.text, defaultValue: 'Öğretmen'),
        const DocQuestionField(key: 'targetAuthority', label: 'Hitap Edilecek Makam', type: DocFieldType.text, defaultValue: 'İLGİLİ MAKAMA'),
        DocQuestionField(key: 'date', label: 'Düzenlenme Tarihi', type: DocFieldType.date, defaultValue: _today()),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Belge Konusu', 'Resmi Görev Yeri (Çalışma) Belgesi'),
        MapEntry('Düzenlenme Tarihi', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) {
        final staff = _str(a, 'staff', 'İlgili Personel');
        final tc = _str(a, 'tcNo');
        final startInfo = _str(a, 'startDateInfo');
        final title = _str(a, 'dutyTitle', 'Öğretmen');
        final target = _str(a, 'targetAuthority', 'İLGİLİ MAKAMA');
        return '''
$target

${tc.isNotEmpty ? '$tc T.C. Kimlik Numaralı ' : ''}Sayın $staff, kurumumuz ${ctx.schoolName} bünyesinde ${startInfo.isNotEmpty ? '$startInfo tarihinden bu yana ' : ''}"$title" unvanıyla kadrolu/sözleşmeli olarak aktif görev yapmaktadır.

İşbu görev yeri belgesi, ilgilinin yazılı/sözlü talebi üzerine resmi işlemlerde kullanılmak üzere düzenlenerek kendisine verilmiştir. Bilgilerinize arz/rica ederim.''';
      },
      buildSigners: (a, ctx) => [
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx)),
      ],
    ),

    OfficialDocTemplate(
      id: 'idari_tespit_savunma_isteme',
      code: '3.5',
      categoryId: 'idari_personel_yazi',
      title: 'İdari Tespit ve Yazılı Bilgi / Savunma İsteme Yazısı',
      subtitle: 'Görev aksaması veya idari tespit durumlarında mevzuat usulüne uygun resmi açıklama/savunma istemi',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.officialLetter,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.policy_rounded,
      questions: [
        const DocQuestionField(key: 'docNumber', label: 'Sayı / Evrak No', type: DocFieldType.text, defaultValue: 'İDARİ-ÖZEL/01'),
        const DocQuestionField(key: 'staff', label: 'İlgili Personel', type: DocFieldType.staffSelect, required: true),
        DocQuestionField(key: 'date', label: 'Yazı Tarihi', type: DocFieldType.date, defaultValue: _today()),
        DocQuestionField(key: 'incidentDate', label: 'Tespit / Olay Tarihi ve Saati', type: DocFieldType.text, defaultValue: '${_today()} - 09:00'),
        const DocQuestionField(
          key: 'docMode',
          label: 'Yazı Niteliği',
          type: DocFieldType.dropdown,
          options: [
            'Yazılı Bilgi ve Açıklama İsteme Yazısı',
            'Usulüne Uygun Yazılı Savunma İsteme Yazısı (En Az 7 Gün Süreli)',
            'Görev Hassasiyeti ve Yazılı Hatırlatma Tebliği',
          ],
          defaultValue: 'Yazılı Bilgi ve Açıklama İsteme Yazısı',
        ),
        const DocQuestionField(
          key: 'subjectDetail',
          label: 'Tutanakla Tespit Edilen Fiil / Husus',
          type: DocFieldType.multiline,
          defaultValue: 'Belirtilen tarih ve saatte nöbet / ders görev yerinde bulunulmadığı ve idareye önceden mazeret bildiriminde bulunulmadığı tutanakla tespit edilmiştir.',
          required: true,
        ),
        const DocQuestionField(key: 'deadlineDays', label: 'Yasal Cevap / Savunma Süresi', type: DocFieldType.dropdown, options: ['7 (Yedi) Gün', '5 (Beş) İş Günü', '3 (Üç) İş Günü'], defaultValue: '7 (Yedi) Gün'),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Sayı', _str(a, 'docNumber', 'İDARİ-ÖZEL/01')),
        MapEntry('Konu', '${_str(a, "docMode", "Bilgi İsteme")} (GİZLİ / KİŞİYE ÖZEL)'),
        MapEntry('Tarih', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) {
        final staff = _str(a, 'staff', 'Sayın İlgili');
        final incDate = _str(a, 'incidentDate', _today());
        final detail = _str(a, 'subjectDetail');
        final days = _str(a, 'deadlineDays', '7 (Yedi) Gün');
        final mode = _str(a, 'docMode');
        return '''
Sayın $staff,

Kurumumuzca yürütülen idari gözetim ve denetim faaliyetleri kapsamında, $incDate tarih/saatinde; "$detail" hususu idari tutanakla kayıt altına alınmıştır.

İlgili mevzuat hükümleri çerçevesinde konu hakkındaki yazılı bilgi / savunmanızı, işbu yazının tarafınıza tebliğ edildiği tarihten itibaren $days içerisinde kapalı zarf ile Okul Müdürlüğümüze teslim etmeniz; belirtilen yasal süre içerisinde yazılı beyanda bulunmadığınız takdirde savunma/açıklama hakkınızdan feragat etmiş sayılarak mevcut bilgi, belge ve tutanaklar üzerinden idari değerlendirme yapılacağı hususunda;

Bilgilerinizi ve gereğini rica ederim. ($mode)''';
      },
      buildSigners: (a, ctx) => [
        DocSigner(name: _str(a, 'staff', 'İlgili Personel'), title: 'Kapalı Zarf Tebellüğ Eden (Tarih / Saat / İmza)'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx)),
      ],
    ),

    OfficialDocTemplate(
      id: 'nobet_gorev_teblig_cizelgesi',
      code: '3.6',
      categoryId: 'idari_personel_yazi',
      title: 'Nöbet Görev Esasları ve Nöbet Talimatnamesi Tebliği (İmza Sirküsü)',
      subtitle: 'MEB Yönetmeliğine uygun nöbetçi öğretmen görev talimatnamesi ve seçmeli öğretmen imza tablosu',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.circularSignatureTable,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.verified_user_rounded,
      questions: [
        const DocQuestionField(
          key: 'termLabel',
          label: 'Nöbet Çizelgesi Dönemi',
          type: DocFieldType.dropdown,
          options: [
            '1. Dönem Haftalık Nöbet Görev Esasları Tebliği',
            '2. Dönem Haftalık Nöbet Görev Esasları Tebliği',
            'Güncellenen Aylık / Dönemlik Nöbet Çizelgesi Tebliği',
          ],
          defaultValue: '1. Dönem Haftalık Nöbet Görev Esasları Tebliği',
        ),
        DocQuestionField(key: 'effectiveDate', label: 'Yürürlük / Tebliğ Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(
          key: 'dutyRules',
          label: 'Nöbetçi Öğretmen Görev ve Sorumluluk Maddeleri',
          type: DocFieldType.multiCheck,
          options: [
            'Nöbet görevi, ilk ders başlamadan 30 (ortaöğretim) / 20 (ilköğretim) dakika önce başlar ve son ders bitiminden 15-30 dakika sonra nöbet defteri imzalanarak sona erer.',
            'Nöbetçi öğretmen teneffüslerde ve öğle aralarında kendi nöbet bölgesinden kesinlikle ayrılmaz; koridor, merdiven, tuvalet ve bahçe güvenliğini aktif olarak denetler.',
            'Sabah ve akşam bayrak törenleri, öğrenci sıra düzeni ve ders zili çaldığında öğrencilerin güvenli şekilde sınıflara girmesi nöbetçi öğretmenlerce sağlanır.',
            'Gün içinde dersliklerin ısınma, aydınlatma, havalandırma, temizlik ve akıllı tahta/demirbaş durumu kontrol edilerek arızalar nöbetçi müdür yardımcısına bildirilir.',
            'Herhangi bir sebeple öğretmeni derse girmeyen sınıflar derhal nöbetçi idareciye bildirilir ve sınıf başıboş bırakılmaz.',
            'Okul bina ve bahçesine yabancı/yetkisiz kişilerin girmemesi için güvenlik/danışma birimi ile koordineli hareket edilir.',
            'Öğrenci rahatsızlanması, kaza veya yaralanma durumunda ilk gözlem yapılarak derhal nöbetçi idareye bilgi verilir ve kaza tutanağı düzenlenir.',
            'Taşımalı / servisli öğrencilerin sabah iniş ve akşam servis araçlarına güvenli binişleri bahçe nöbetçi öğretmeni ve nöbetçi idarece kontrol edilir.',
            'Hastalık veya kabul edilebilir mazeret halinde nöbetçi müdür yardımcısına önceden bilgi verilerek nöbet değişikliği idari onayla sağlanır.',
            'Nöbet bitiminde günlük işleyiş ve varsa vukuatlar Okul Nöbet Defterine işlenerek nöbetçi müdür yardımcısına teslim edilir.',
            'Kantin ve yemekhane önlerinde sıra düzeni, gıda hijyeni gözlemi ve öğle arası öğrenci güvenliği nöbetçi öğretmenlerce takip edilir.',
            'Merdiven boşlukları, pencere kenarları, ıslak zeminler ve yangın/acil çıkış kapıları teneffüs başlarında kontrol edilerek risk görülürse anında müdahale edilir.',
            'Özel gereksinimli (BEP/kaynaştırma) öğrencilerin teneffüs güvenliği ve akran etkileşimleri nöbetçi öğretmenlerce hassasiyetle gözetilir.',
            'Acil durum / deprem / yangın sireni çaldığında nöbetçi öğretmen kendi katındaki sınıfların panik yapmadan acil çıkıştan tahliyesini koordine eder.',
          ],
          defaultValue: [
            'Nöbet görevi, ilk ders başlamadan 30 (ortaöğretim) / 20 (ilköğretim) dakika önce başlar ve son ders bitiminden 15-30 dakika sonra nöbet defteri imzalanarak sona erer.',
            'Nöbetçi öğretmen teneffüslerde ve öğle aralarında kendi nöbet bölgesinden kesinlikle ayrılmaz; koridor, merdiven, tuvalet ve bahçe güvenliğini aktif olarak denetler.',
            'Herhangi bir sebeple öğretmeni derse girmeyen sınıflar derhal nöbetçi idareciye bildirilir ve sınıf başıboş bırakılmaz.',
            'Öğrenci rahatsızlanması, kaza veya yaralanma durumunda ilk gözlem yapılarak derhal nöbetçi idareye bilgi verilir ve kaza tutanağı düzenlenir.',
            'Taşımalı / servisli öğrencilerin sabah iniş ve akşam servis araçlarına güvenli binişleri bahçe nöbetçi öğretmeni ve nöbetçi idarece kontrol edilir.',
            'Nöbet bitiminde günlük işleyiş ve varsa vukuatlar Okul Nöbet Defterine işlenerek nöbetçi müdür yardımcısına teslim edilir.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Konu', _str(a, 'termLabel')),
        MapEntry('Yürürlük / Tebliğ Tarihi', _str(a, 'effectiveDate', _today())),
      ],
      composeBody: (a, ctx) => '''
OKUL NÖBET HİZMETLERİ TALİMATNAMESİ VE İMZA SİRKÜSÜ

MEB Okul Öncesi Eğitim ve İlköğretim Kurumları Yönetmeliği (Md. 44) ile Ortaöğretim Kurumları Yönetmeliği (Md. 91) hükümleri uyarınca ${ctx.academicYear} Eğitim ve Öğretim Yılında ${ctx.schoolName} bünyesinde yürütülecek nöbet hizmetlerinde aşağıda belirtilen esaslara titizlikle uyulacaktır:

${_numberedLines(_list(a, 'dutyRules'))}

Yukarıdaki nöbet görev talimatnamesini ve ilan edilen haftalık nöbet çizelgesini okudum, tebellüğ ettim:''',
      buildSigners: (a, ctx) => [
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'ONAY'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'dyk_etut_kurs_acilis_onayi',
      code: '3.7',
      categoryId: 'idari_personel_yazi',
      title: 'Destekleme ve Yetiştirme Kursu (DYK) / Akademik Etüt Onay Yazısı',
      subtitle: 'Hafta içi / hafta sonu DYK, telafi eğitimi veya kurumsal etüt programı idari açılış oluru',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.officialLetter,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.school_outlined,
      questions: [
        const DocQuestionField(
          key: 'programName',
          label: 'Kurs / Etüt Programı Adı',
          type: DocFieldType.text,
          defaultValue: 'Destekleme ve Yetiştirme Kursu (DYK) / Akademik Güçlendirme Etüt Programı',
          required: true,
        ),
        DocQuestionField(key: 'date', label: 'Onay Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'dateRange', label: 'Uygulama Başlangıç ve Bitiş Tarih Aralığı', type: DocFieldType.text, defaultValue: 'Ekim 2026 — Haziran 2027 (Cumartesi 09:00 - 13:30)'),
        const DocQuestionField(key: 'targetClasses', label: 'Kapsanan Sınıf Seviyeleri / Şubeler', type: DocFieldType.multiClassSelect),
        const DocQuestionField(key: 'teachers', label: 'Görev Alacak Öğretmenler', type: DocFieldType.multiStaffSelect, required: true),
        const DocQuestionField(key: 'coordinator', label: 'Kurs / Etüt Sorumlu Müdür Yardımcısı', type: DocFieldType.staffSelect),
        const DocQuestionField(
          key: 'rules',
          label: 'Uygulama ve Denetim Esasları',
          type: DocFieldType.multiCheck,
          options: [
            'Kurs/etüt yoklamalarının her ders saatinde düzenli alınmasına ve devamsızlık yapan öğrencilerin velilerine aynı gün bilgi verilmesine.',
            'Kazanım değerlendirme ve deneme sınavı analizlerine göre eksik konulara öncelik verilmesine.',
            'Kurs süresince bina güvenliği, nöbetçi idareci/personel planlaması ve temizlik tedbirlerinin eksiksiz uygulanmasına.',
            'Kurs planlarının ve ders defterlerinin ilgili öğretmenlerce haftalık işlenerek sorumlu müdür yardımcısına imzalatılmasına.',
          ],
          defaultValue: [
            'Kurs/etüt yoklamalarının her ders saatinde düzenli alınmasına ve devamsızlık yapan öğrencilerin velilerine aynı gün bilgi verilmesine.',
            'Kazanım değerlendirme ve deneme sınavı analizlerine göre eksik konulara öncelik verilmesine.',
            'Kurs süresince bina güvenliği, nöbetçi idareci/personel planlaması ve temizlik tedbirlerinin eksiksiz uygulanmasına.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Konu', _str(a, 'programName')),
        MapEntry('Uygulama Takvimi', _str(a, 'dateRange')),
        MapEntry('Sorumlu İdareci', _str(a, 'coordinator', '-')),
        MapEntry('Tarih', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
MÜDÜRLÜK MAKAMINA

MEB Destekleme ve Yetiştirme Kursları Yönergesi ve kurumumuz akademik başarı eylem planı doğrultusunda; ${ctx.schoolName} bünyesinde öğrenim gören (${_list(a, 'targetClasses').join(', ')}) sınıf/şube öğrencilerimizin eksik kazanımlarını tamamlamak ve merkezi sınav hazırlıklarını desteklemek amacıyla ${_str(a, 'dateRange')} tarihleri arasında "${_str(a, 'programName')}" yürütülmesi planlanmıştır.

GÖREVLENDİRİLEN ÖĞRETMENLER:
${_numberedLines(_list(a, 'teachers'))}

UYGULAMA ESASLARI:
${_numberedLines(_list(a, 'rules'))}

Söz konusu kurs/etüt programının belirtilen takvim ve esaslar çerçevesinde yürütülmesi hususunu Olurlarınıza arz ederim.''',
      buildSigners: (a, ctx) => [
        DocSigner(
          name: _str(a, 'coordinator', ctx.vicePrincipals.isNotEmpty ? ctx.vicePrincipals.first.fullName : 'Müdür Yardımcısı'),
          title: 'Kurs/Etüt Sorumlu Md. Yrd.',
        ),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'OLUR'), isApproval: true),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // BAŞLIK 4: ÖĞRENCİ DİSİPLİN, OLAY, KAZA VE DEVAMSIZLIK EVRAKLARI
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'ogrenci_olay_disiplin_tutanagi',
      code: '4.1',
      categoryId: 'idari_disiplin_kaza',
      title: 'Öğrenci Olay / Disiplin Tespit Tutanağı',
      subtitle: 'Okul içinde yaşanan disiplin, akran zorbalığı veya kural ihlali olaylarının resmi kayıt tutanağı',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.report_problem_rounded,
      questions: [
        const DocQuestionField(key: 'targetClass', label: 'Şube Seçimi', type: DocFieldType.classSelect, required: true),
        const DocQuestionField(key: 'students', label: 'Olaya Karışan Öğrenci(ler)', type: DocFieldType.multiStudentSelect, required: true),
        DocQuestionField(key: 'date', label: 'Olay Tarihi', type: DocFieldType.date, defaultValue: _today()),
        DocQuestionField(key: 'time', label: 'Olay Saati', type: DocFieldType.time, defaultValue: _nowTime()),
        const DocQuestionField(
          key: 'location',
          label: 'Olay Yeri',
          type: DocFieldType.dropdown,
          options: [
            'Derslik / Sınıf İçi',
            'Koridor / Merdiven / Kat Alanı',
            'Okul Bahçesi / Tören Alanı',
            'Yemekhane / Kantin Alanı',
            'Spor Salonu / Soyunma Odası',
            'Fen / Bilişim Laboratuvarı',
            'Tuvalet / Lavabo Önü',
            'Okul Servisi / Giriş-Çıkış Kapısı',
          ],
          defaultValue: 'Koridor / Merdiven / Kat Alanı',
        ),
        const DocQuestionField(
          key: 'incidentCategory',
          label: 'Olayın Genel Niteliği',
          type: DocFieldType.dropdown,
          options: [
            'Akran Çatışması / Fiziksel veya Sözlü Tartışma',
            'Ders ve Eğitim-Öğretim Düzenini Bozma',
            'Okul Malına / Demirbaşına Zarar Verme',
            'Bilişim Araçlarını Kurallara Aykırı Kullanma / Siber Zorbalık',
            'İzinsiz Okul Terki / Derslikten Ayrılma',
            'Öğretmen veya Okul Çalışanlarına Karşı Saygısız Tutum',
          ],
          defaultValue: 'Akran Çatışması / Fiziksel veya Sözlü Tartışma',
        ),
        const DocQuestionField(
          key: 'detectedClauses',
          label: 'Somut Olay Tespit ve İlk Müdahale Maddeleri (Seçilebilir)',
          type: DocFieldType.multiCheck,
          options: [
            'Olay mahalline anında müdahale edilerek taraflar sakinleştirilmiş ve fiziksel/ortamsal güvenlik sağlanmıştır.',
            'Olaya karışan öğrencilerin sağlık ve fiziki bütünlük kontrolü yapılmış; herhangi bir acil tıbbi tehlike bulunmadığı/müdahale edildiği görülmüştür.',
            'Olay anında çevrede bulunan görgü tanığı öğrenciler ve nöbetçi personel tespit edilmiştir.',
            'Olay mahallini gören güvenlik kamerası kayıt saati not edilerek idarece incelemeye alınmıştır.',
            'Okul eşyasında / demirbaşında oluşan maddi hasar yerinde tespit edilerek kayıt altına alınmıştır.',
            'Öğrenciler ön görüşme ve sakinleşme desteği için Okul Rehberlik (PDR) Servisine yönlendirilmiştir.',
            'Öğrenci velilerine telefonla bilgi verilerek okula davet edilmiş ve tutanak ÖDDK / Disiplin Kurulu gündemi için idareye sunulmuştur.',
          ],
          defaultValue: [
            'Olay mahalline anında müdahale edilerek taraflar sakinleştirilmiş ve fiziksel/ortamsal güvenlik sağlanmıştır.',
            'Olay anında çevrede bulunan görgü tanığı öğrenciler ve nöbetçi personel tespit edilmiştir.',
            'Öğrenci velilerine telefonla bilgi verilerek okula davet edilmiş ve tutanak ÖDDK / Disiplin Kurulu gündemi için idareye sunulmuştur.',
          ],
        ),
        const DocQuestionField(
          key: 'description',
          label: 'Olayın Oluş Şekli ve Somut Tespitler',
          type: DocFieldType.multiline,
          defaultValue: 'Yukarıda kimlik bilgileri belirtilen öğrenci(ler)in belirtilen tarih ve saatte okul kurallarına ve ilgili yönetmelik hükümlerine aykırı davranışta bulunduğu mahallinde görülerek/tespit edilerek tutanak altına alınmıştır.',
          required: true,
        ),
        const DocQuestionField(
          key: 'witnessStaff',
          label: 'Tutanağı Düzenleyen Öğretmen / İdareciler',
          type: DocFieldType.multiStaffSelect,
          required: true,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Şube', _str(a, 'targetClass', '-')),
        MapEntry('İlgili Öğrenci(ler)', _list(a, 'students').join(', ')),
        MapEntry('Olay Tarihi / Saati', '${_str(a, "date", _today())} - ${_str(a, "time", _nowTime())}'),
        MapEntry('Olay Yeri / Niteliği', '${_str(a, "location")} — ${_str(a, "incidentCategory")}'),
      ],
      composeBody: (a, ctx) => '''
OLAY TESPİT TUTANAĞI

${_str(a, 'date', _today())} tarihinde saat ${_str(a, 'time', _nowTime())} sıralarında kurumumuz ${_str(a, 'location')} alanında meydana gelen "${_str(a, 'incidentCategory')}" nitelikli olayda; ${_list(a, 'students').join(', ')} isimli öğrenci(ler) ile ilgili aşağıdaki somut durum tespit edilmiştir:

OLAYIN GELİŞİMİ VE TESPİTLER:
${_str(a, 'description')}

TESPİT VE İLK MÜDAHALE MADDELERİ:
${_numberedLines(_list(a, 'detectedClauses'))}

İşbu olay tespit tutanağı, vakıanın hemen ardından maddi gerçeği kayıt altına almak amacıyla mahallinde 2 (iki) nüsha olarak düzenlenmiş; okunarak aşağıda imzası bulunan görevlilerce imza altına alınmış ve gereği için Öğrenci Davranışlarını Değerlendirme (Ödül ve Disiplin) Kurulu / Okul İdaresine teslim edilmiştir.''',
      buildSigners: (a, ctx) {
        final staff = _list(a, 'witnessStaff');
        if (staff.isEmpty) {
          return [
            DocSigner(name: ctx.currentUser?.fullName ?? 'Görevli Öğretmen', title: 'Tutanak Düzenleyen'),
            DocSigner(name: ctx.vicePrincipals.isNotEmpty ? ctx.vicePrincipals.first.fullName : 'Müdür Yardımcısı', title: 'İlgili Müdür Yardımcısı'),
          ];
        }
        return [for (final s in staff) DocSigner(name: s, title: 'Tutanak Düzenleyen Görevli')];
      },
    ),

    OfficialDocTemplate(
      id: 'ogrenci_ifade_beyan_formu',
      code: '4.2',
      categoryId: 'idari_disiplin_kaza',
      title: 'Öğrenci / Görgü Tanığı Bilgi ve Yazılı Beyan Tutanağı',
      subtitle: 'Pedagojik usullere uygun öğrenci yazılı anlatım / tanık beyanı ve veli bilgilendirme formu',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.contact_page_rounded,
      questions: [
        const DocQuestionField(key: 'targetClass', label: 'Öğrencinin Şubesi', type: DocFieldType.classSelect, required: true),
        const DocQuestionField(key: 'student', label: 'Öğrenci Seçimi', type: DocFieldType.studentSelect, required: true),
        const DocQuestionField(
          key: 'roleType',
          label: 'Beyan Sıfatı',
          type: DocFieldType.dropdown,
          options: [
            'Bilgisine / Savunmasına Başvurulan Öğrenci',
            'Görgü Tanığı Sıfatıyla Bilgisine Başvurulan Öğrenci',
            'Mağdur / Şikâyetçi Öğrenci Beyanı',
          ],
          defaultValue: 'Bilgisine / Savunmasına Başvurulan Öğrenci',
        ),
        DocQuestionField(key: 'date', label: 'Görüşme Tarihi ve Saati', type: DocFieldType.text, defaultValue: '${_today()} - ${_nowTime()}'),
        const DocQuestionField(key: 'topic', label: 'Olay Konusu, Tarihi ve Yeri', type: DocFieldType.text, required: true, hint: 'Örn: 31.10.2026 tarihli 3. teneffüs koridor olayı'),
        const DocQuestionField(
          key: 'statement',
          label: 'Öğrencinin Beyanı (Boş bırakılırsa el yazısı ile doldurulması için noktalı alan basılır)',
          type: DocFieldType.multiline,
          hint: 'Öğrencinin kendi ifadelerini yazabilir veya boş bırakıp çıktı alarak öğrenciye el yazısıyla doldurtabilirsiniz...',
        ),
        const DocQuestionField(key: 'interviewer', label: 'Bilgi Alan Kurul Başkanı / İdareci', type: DocFieldType.staffSelect),
        const DocQuestionField(key: 'counselorRef', label: 'Gözlemci Rehber Öğretmen / Sınıf Öğretmeni (Opsiyonel)', type: DocFieldType.staffSelect),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Beyan Sıfatı', _str(a, 'roleType')),
        MapEntry('Görüşme Tarihi / Saati', _str(a, 'date', _today())),
        MapEntry('İlgili Olay Konusu', _str(a, 'topic')),
      ],
      composeBody: (a, ctx) {
        final st = _str(a, 'statement');
        final blankLines = List.generate(8, (_) => '........................................................................................................................................').join('\n\n');
        return '''
PEDAGOJİK BİLGİ VE BEYAN ALMA TUTANAĞI

SORU: "${_str(a, 'topic')}" konusuyla ilgili gördüklerinizi, bildiklerinizi ve olayın gelişimini hiçbir etki altında kalmadan açıkça anlatınız.

ÖĞRENCİNİN BEYANI:
${st.isNotEmpty ? st : blankLines}

Yukarıdaki yazılı beyanımı pedagojik ortamda, hiçbir baskı altında kalmadan kendi özgür irademle verdim; okudum ve doğruluğunu imzamla kabul ederim.''';
      },
      buildSigners: (a, ctx) {
        final counselor = _str(a, 'counselorRef');
        return [
          DocSigner(name: _str(a, 'student', 'Öğrenci'), title: 'Beyan Sahibi Öğrenci'),
          if (counselor.isNotEmpty) DocSigner(name: counselor, title: 'Gözlemci Öğretmen / PDR'),
          DocSigner(
            name: _str(a, 'interviewer', ctx.vicePrincipals.isNotEmpty ? ctx.vicePrincipals.first.fullName : ctx.principalName),
            title: 'Bilgi Alan Kurul Üyesi / İdareci',
          ),
        ];
      },
    ),

    OfficialDocTemplate(
      id: 'okul_ici_kaza_tutanagi',
      code: '4.3',
      categoryId: 'idari_disiplin_kaza',
      title: 'Okul İçi Kaza / Yaralanma ve Acil Müdahale Tutanağı',
      subtitle: 'Kaza yeri, saati, yapılan ilk yardım, 112/veli bildirimi ve kamera/İSG kayıt tutanağı',
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.medical_services_rounded,
      questions: [
        const DocQuestionField(key: 'targetClass', label: 'Öğrencinin Şubesi', type: DocFieldType.classSelect, required: true),
        const DocQuestionField(key: 'student', label: 'Kazazede / Rahatsızlanan Öğrenci', type: DocFieldType.studentSelect, required: true),
        DocQuestionField(key: 'date', label: 'Kaza / Olay Tarihi', type: DocFieldType.date, defaultValue: _today()),
        DocQuestionField(key: 'time', label: 'Kaza / Olay Saati', type: DocFieldType.time, defaultValue: _nowTime()),
        const DocQuestionField(key: 'location', label: 'Kaza Yeri', type: DocFieldType.text, defaultValue: 'Okul Bahçesi / Koridor Alanı'),
        const DocQuestionField(key: 'dutyTeacher', label: 'Nöbetçi / Ders Öğretmeni', type: DocFieldType.staffSelect),
        const DocQuestionField(key: 'dutyAdmin', label: 'Nöbetçi Müdür Yardımcısı', type: DocFieldType.staffSelect),
        const DocQuestionField(
          key: 'howHappened',
          label: 'Kazanın / Rahatsızlığın Oluş Şekli ve İlk Gözlem',
          type: DocFieldType.multiline,
          defaultValue: 'Teneffüs esnasında öğrencinin koşarken dengesini kaybederek düşmesi sonucu meydana gelmiş olup öğrencinin bilinci açık şekilde ilk kontrolü yapılmıştır.',
        ),
        const DocQuestionField(
          key: 'actionsTaken',
          label: 'Yapılan İlk Müdahale, İdari İşlem ve Bildirimler',
          type: DocFieldType.multiCheck,
          options: [
            'Öğrenci hareket ettirilmeden / güvenli revir alanına alınarak ilk yardım sertifikalı personelce ilk gözlemi yapıldı.',
            'Yaralanma bölgesine soğuk kompres / pansuman uygulandı, bilinci ve genel durumu kesintisiz takip edildi.',
            'Öğrenci velisine sistemde kayıtlı telefon numarasından derhal ulaşılarak olay hakkında ayrıntılı bilgi verildi.',
            '112 Acil Sağlık Çağrı Merkezi aranarak ambulans / sağlık ekibi talep edildi ve geliş saati kayıt altına alındı.',
            'Öğrenci, okula gelen velisine imza karşılığı teslim edilerek sağlık kuruluşuna yönlendirildi.',
            'Acil durum gereği nöbetçi idareci / öğretmen refakatinde sağlık kuruluşuna intikali sağlandı.',
            'Kaza mahallindeki fiziki durum incelendi, olası risk unsuru giderildi ve güvenlik kamerası zaman aralığı not edildi.',
            'Olay, Okul Kaza/Vukuat Kayıt Defterine ve İSG Kurul kayıtlarına işlendi.',
            'Öğrencinin e-Okul / rehberlik sağlık bilgi formundaki kronik hastalık ve ilaç/alerji kaydı kontrol edildi.',
            'Sınıf rehber öğretmeni bilgilendirilerek öğrencinin sonraki günlerdeki sağlık ve devam takibinin yapılması planlandı.',
            'İSG Uzmanı / İşyeri Güvenlik Ekibi tarafından kaza kök neden incelemesi yapılarak tekrarını önleyici tedbir alındı.',
          ],
          defaultValue: [
            'Öğrenci hareket ettirilmeden / güvenli revir alanına alınarak ilk yardım sertifikalı personelce ilk gözlemi yapıldı.',
            'Öğrenci velisine sistemde kayıtlı telefon numarasından derhal ulaşılarak olay hakkında ayrıntılı bilgi verildi.',
            'Öğrenci, okula gelen velisine imza karşılığı teslim edilerek sağlık kuruluşuna yönlendirildi.',
            'Olay, Okul Kaza/Vukuat Kayıt Defterine ve İSG Kurul kayıtlarına işlendi.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Kaza Tarihi ve Saati', '${_str(a, "date", _today())} - ${_str(a, "time", _nowTime())}'),
        MapEntry('Kaza Mahalli', _str(a, 'location')),
        MapEntry('Nöbetçi / Ders Öğretmeni', _str(a, 'dutyTeacher', '-')),
        MapEntry('Nöbetçi Müdür Yardımcısı', _str(a, 'dutyAdmin', '-')),
      ],
      composeBody: (a, ctx) => '''
OKUL İÇİ KAZA, ACİL MÜDAHALE VE BİLDİRİM TUTANAĞI

1. KAZANIN / RAHATSIZLIĞIN OLUŞ ŞEKLİ VE GÖZLEM:
${_str(a, 'date', _today())} tarihinde saat ${_str(a, 'time', _nowTime())} sıralarında kurumumuz ${_str(a, 'location')} alanında, ${_str(a, 'targetClass')} şubesi öğrencisi ${_str(a, 'student')} ile ilgili olarak:
${_str(a, 'howHappened')}

2. UYGULANAN İLK MÜDAHALE, BİLDİRİM VE İSG İŞLEMLERİ:
${_numberedLines(_list(a, 'actionsTaken'))}

İşbu tutanak, yaşanan kaza/rahatsızlık olayını ve yürütülen sağlık/idari işlemleri resmi kayıt altına almak üzere olayın hemen akabinde 2 (iki) nüsha halinde düzenlenerek imza altına alınmıştır.''',
      buildSigners: (a, ctx) => [
        DocSigner(name: _str(a, 'dutyTeacher', 'Nöbetçi Öğretmen'), title: 'Nöbetçi / Ders Öğretmeni'),
        DocSigner(
          name: _str(a, 'dutyAdmin', ctx.vicePrincipals.isNotEmpty ? ctx.vicePrincipals.first.fullName : 'Müdür Yardımcısı'),
          title: 'Nöbetçi Müdür Yardımcısı',
        ),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'devamsizlik_veli_uyari_mektubu',
      code: '4.4',
      categoryId: 'idari_disiplin_kaza',
      title: 'Devamsızlık Uyarı Mektubu ve Veli Tebligatı',
      subtitle: '5, 10, 15 ve 20+ gün MEB devamsızlık kademe bildirimi ve kesilebilir veli tebellüğ pusulası',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.officialLetter,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.mark_email_unread_rounded,
      questions: [
        const DocQuestionField(key: 'docNumber', label: 'Sayı / Tebligat No', type: DocFieldType.text, defaultValue: 'ÖĞR-DEVAM/2026'),
        const DocQuestionField(key: 'targetClass', label: 'Öğrencinin Şubesi', type: DocFieldType.classSelect, required: true),
        const DocQuestionField(key: 'student', label: 'Öğrenci Seçimi', type: DocFieldType.studentSelect, required: true),
        const DocQuestionField(
          key: 'warningStage',
          label: 'MEB Devamsızlık Uyarı Kademesi',
          type: DocFieldType.dropdown,
          options: [
            '1. Devamsızlık Bildirimi ve Veli Bilgilendirme (5 Gün)',
            '2. Devamsızlık Uyarısı ve Rehberlik Görüşme Çağrısı (10 Gün)',
            '3. Kritik Devamsızlık Uyarısı — Sınıf Tekrarı Riski (15 Gün)',
            'Son Resmi İhtar — Sürekli Devamsızlık ve Başarısızlık Sınırı (20+ Gün)',
          ],
          defaultValue: '1. Devamsızlık Bildirimi ve Veli Bilgilendirme (5 Gün)',
        ),
        const DocQuestionField(key: 'unexcusedDays', label: 'Özürsüz Devamsızlık Gün Sayısı', type: DocFieldType.text, defaultValue: '5 Gün'),
        const DocQuestionField(key: 'excusedDays', label: 'Özürlü (Raporlu/İzinli) Devamsızlık Gün Sayısı', type: DocFieldType.text, defaultValue: '2 Gün'),
        DocQuestionField(key: 'date', label: 'Tebligat Tarihi', type: DocFieldType.date, defaultValue: _today()),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Sayı', _str(a, 'docNumber', '-')),
        MapEntry('Konu', _str(a, 'warningStage', 'Öğrenci Devamsızlık Bildirimi')),
        MapEntry('Öğrenci / Sınıf', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Tebliğ Tarihi', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
Sayın Veli,

222 sayılı İlköğretim ve Eğitim Kanunu, 1739 sayılı Milli Eğitim Temel Kanunu ve MEB Kurum Yönetmeliğinin devam-devamsızlıkla ilgili hükümleri uyarınca öğrencilerin okula düzenli devam etmeleri yasal zorunluluktur.

Velisi bulunduğunuz ${_str(a, 'targetClass')} sınıfı öğrencisi ${_str(a, 'student')}'in ${_str(a, 'date', _today())} tarihi itibarıyla e-Okul / kurum kayıtlarımızda;
• Özürsüz Devamsızlık Süresi : ${_str(a, 'unexcusedDays')}
• Özürlü Devamsızlık Süresi  : ${_str(a, 'excusedDays')}
olduğu tespit edilmiştir.

Mevzuat gereği özür belgesi veya sağlık raporlarının, özrün sona erdiği tarihten itibaren en geç 5 (beş) iş günü içinde Okul İdaresine teslim edilmesi gerekmektedir. Öğrencimizin akademik başarısının düşmemesi, kazanım kaybı ve devamsızlıktan dolayı sınıf tekrarı / başarısızlık yaptırımı ile karşılaşmaması için okula düzenli devamının sağlanması ve Okul Rehberlik Servisi / ilgili müdür yardımcısı ile iletişime geçmeniz hususunda bilgilerinizi ve gereğini önemle rica ederim.

- - - - - - - - - - - - - - - - - - - - ✂ KESİNİZ (VELİ TEBELLÜĞ VE İADE PUSULASI) - - - - - - - - - - - - - - - - - - - -
Velisi bulunduğum ${_str(a, 'student')} (${_str(a, 'targetClass')}) isimli öğrencinin "${_str(a, 'warningStage')}" konulu resmi devamsızlık bildirim yazısını tebellüğ ettim.
Tebellüğ Tarihi: ..../..../202..   Veli Adı Soyadı: .................................   Tel: ........................   İmza: ....................''',
      buildSigners: (a, ctx) => [
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx)),
      ],
    ),

    OfficialDocTemplate(
      id: 'ogrenci_belgesi_evrak_teslim',
      code: '4.5',
      categoryId: 'idari_disiplin_kaza',
      title: 'Aktif Öğrenci Belgesi & Veliye Evrak Teslim Tutanağı',
      subtitle: 'Kurum antetli öğrenci belgesi, nakil/kayıt dosyası veya resmi belge teslim tutanağı',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.officialLetter,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.school_rounded,
      questions: [
        const DocQuestionField(key: 'targetClass', label: 'Öğrencinin Şubesi', type: DocFieldType.classSelect, required: true),
        const DocQuestionField(key: 'student', label: 'Öğrenci Seçimi', type: DocFieldType.studentSelect, required: true),
        const DocQuestionField(
          key: 'docVariant',
          label: 'Düzenlenecek Belge Türü',
          type: DocFieldType.dropdown,
          options: [
            'Aktif Öğrenim (Öğrenci) Belgesi',
            'Veliye Resmi Evrak / Gelişim Dosyası Teslim Tutanağı',
            'Nakil / Kayıt Evrakları Teslim Alma ve Kontrol Tutanağı',
          ],
          defaultValue: 'Aktif Öğrenim (Öğrenci) Belgesi',
        ),
        const DocQuestionField(key: 'extraDetail', label: 'Verileceği Makam veya Teslim Edilen/Alınan Belgeler', type: DocFieldType.text, defaultValue: 'İLGİLİ MAKAMA'),
        DocQuestionField(key: 'date', label: 'Düzenlenme Tarihi', type: DocFieldType.date, defaultValue: _today()),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Belge Türü', _str(a, 'docVariant')),
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Tarih', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) {
        final variant = _str(a, 'docVariant');
        if (variant.contains('Teslim')) {
          return '''
RESMİ EVRAK TESLİM / TESELLÜM TUTANAĞI

Kurumumuz ${_str(a, 'targetClass')} şubesi öğrencisi ${_str(a, 'student')}'e ait aşağıda dökümü belirtilen resmi belge ve dosyalar, ${_str(a, 'date', _today())} tarihinde kontrol edilerek eksiksiz şekilde velisine teslim edilmiş / teslim alınmıştır.

İşlem Konusu Belgeler:
${_str(a, 'extraDetail', 'Öğrenci gelişim dosyası, sağlık/BEP evrakları ve kayıt belgeleri')}

İşbu tutanak 2 (iki) nüsha olarak düzenlenmiş ve taraflarca imza altına alınmıştır.''';
        }
        return '''
${_str(a, 'extraDetail', 'İLGİLİ MAKAMA')}

Yukarıda açık kimlik ve şube bilgileri belirtilen ${_str(a, 'student')}, ${ctx.academicYear} Eğitim ve Öğretim Yılında kurumumuz ${ctx.schoolName} ${_str(a, 'targetClass')} şubesinde tam zamanlı aktif kayıtlı öğrenci olarak öğrenimine devam etmektedir.

İşbu öğrenci belgesi, öğrenci velisinin talebi üzerine resmi işlemlerde kullanılmak üzere düzenlenerek verilmiştir.''';
      },
      buildSigners: (a, ctx) {
        if (_str(a, 'docVariant').contains('Teslim')) {
          return [
            const DocSigner(name: 'Öğrenci Velisi', title: 'Teslim Alan / Veren Veli'),
            DocSigner(name: ctx.principalName, title: _authorityTitle(ctx)),
          ];
        }
        return [DocSigner(name: ctx.principalName, title: _authorityTitle(ctx))];
      },
    ),

    OfficialDocTemplate(
      id: 'yasakli_materyal_telefon_teslim_tutanagi',
      code: '4.6',
      categoryId: 'idari_disiplin_kaza',
      title: 'Cep Telefonu / Uygunsuz Eşya Muhafaza ve Veliye Teslim Tutanağı',
      subtitle: 'Ders/okul saatinde kurallara aykırı kullanılan cihaz veya eşyanın muhafaza ve veliye iade formu',
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.phonelink_erase_rounded,
      questions: [
        const DocQuestionField(key: 'targetClass', label: 'Öğrencinin Şubesi', type: DocFieldType.classSelect, required: true),
        const DocQuestionField(key: 'student', label: 'Öğrenci Seçimi', type: DocFieldType.studentSelect, required: true),
        DocQuestionField(key: 'date', label: 'Tespit / Muhafaza Tarihi ve Saati', type: DocFieldType.text, defaultValue: '${_today()} - ${_nowTime()}'),
        const DocQuestionField(
          key: 'itemDescription',
          label: 'Muhafaza Altına Alınan Cihaz / Eşya Tanımı',
          type: DocFieldType.text,
          defaultValue: '1 Adet Akıllı Cep Telefonu (Kapalı konumda, fiziki hasarsız olarak teslim alındı)',
          required: true,
        ),
        const DocQuestionField(
          key: 'reason',
          label: 'Tespit Nedeni',
          type: DocFieldType.dropdown,
          options: [
            'MEB Genelgesi ve Kurul Kararına aykırı olarak ders esnasında cep telefonu kullanımı',
            'Sınav / Etüt salonuna yasaklı akıllı cihaz (telefon / akıllı saat) ile girilmesi',
            'Eğitim ortamına uygun olmayan ve güvenliği riske atan materyal bulundurulması',
          ],
          defaultValue: 'MEB Genelgesi ve Kurul Kararına aykırı olarak ders esnasında cep telefonu kullanımı',
        ),
        const DocQuestionField(key: 'parentName', label: 'Teslim Alan Veli Adı Soyadı (Boş bırakılırsa el ile yazılır)', type: DocFieldType.text),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Muhafaza Tarihi', _str(a, 'date')),
        MapEntry('Eşya / Cihaz Tanımı', _str(a, 'itemDescription')),
        MapEntry('Tespit Nedeni', _str(a, 'reason')),
      ],
      composeBody: (a, ctx) => '''
EŞYA / CİHAZ GEÇİCİ MUHAFAZA VE VELİYE İADE TUTANAĞI

1. GEÇİCİ MUHAFAZA TESPİTİ:
Millî Eğitim Bakanlığı ders içi cep telefonu/akıllı cihaz kullanım yasağı genelgesi ve Okul Öğretmenler Kurulu kararları uyarınca; ${_str(a, 'targetClass')} şubesi öğrencisi ${_str(a, 'student')}'in üzerinde/sırasında "${_str(a, 'reason')}" sebebiyle tespit edilen "${_str(a, 'itemDescription')}" kapatılarak velisine teslim edilmek üzere Okul İdaresince güvenli muhafaza altına alınmıştır.

2. VELİYE TESLİM VE TAAHHÜT BEYANI:
Yukarıda özellikleri belirtilen cihazı/eşyayı sağlam ve eksiksiz olarak Okul İdaresinden elden teslim aldım. Öğrencimin okul kurallarına uyması hususunda gerekli bilgilendirmeyi yapacağımı beyan ederim.
Teslim Tarihi: ..../..../202..''',
      buildSigners: (a, ctx) => [
        DocSigner(name: ctx.currentUser?.fullName ?? 'Tespit Eden Öğretmen', title: 'Tespit Eden Öğretmen'),
        DocSigner(
          name: ctx.vicePrincipals.isNotEmpty ? ctx.vicePrincipals.first.fullName : 'Müdür Yardımcısı',
          title: 'Muhafaza ve Teslim Eden İdareci',
        ),
        DocSigner(name: _str(a, 'parentName', '........................................'), title: 'Sağlam Teslim Alan Öğrenci Velisi'),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // BAŞLIK 5: GEZİ, TÖREN, YARIŞMA VE VELİ İZİN EVRAKLARI
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'toplu_veli_izin_muvafakatname',
      code: '5.1',
      categoryId: 'idari_gezi_toren',
      title: 'Toplu Veli İzin Belgesi / Muvafakatname Üretici',
      subtitle: 'Seçilen şubelerdeki her öğrenci için kişiye özel basılmış kesim çizgili veli muvafakatnameleri',
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.bulkParentSlip,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.family_restroom_rounded,
      questions: [
        const DocQuestionField(
          key: 'targetClasses',
          label: 'Hedef Sınıf / Şubeler (Tüm öğrenciler otomatik çekilir)',
          type: DocFieldType.multiClassSelect,
          required: true,
        ),
        const DocQuestionField(
          key: 'eventTitle',
          label: 'Gezi / Yarışma / Kurs / Etkinlik Adı',
          type: DocFieldType.text,
          defaultValue: 'Kültürel ve Bilimsel İnceleme Gezisi',
          required: true,
        ),
        const DocQuestionField(
          key: 'destination',
          label: 'Gidilecek Yer / Etkinlik Alanı',
          type: DocFieldType.text,
          defaultValue: 'Bilim Merkezi ve Müze Alanı',
          required: true,
        ),
        DocQuestionField(key: 'eventDate', label: 'Etkinlik Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'timeRange', label: 'Hareket ve Dönüş Saat Aralığı', type: DocFieldType.text, defaultValue: '09:00 - 15:30'),
        const DocQuestionField(
          key: 'slipsPerPage',
          label: 'A4 Sayfa Yerleşimi',
          type: DocFieldType.dropdown,
          options: ['A4 Sayfada 2 Öğrenci (Kesim Çizgili Ekonomik)', 'A4 Sayfada 1 Öğrenci (Tam Sayfa Resmi)'],
          defaultValue: 'A4 Sayfada 2 Öğrenci (Kesim Çizgili Ekonomik)',
        ),
        const DocQuestionField(
          key: 'extraNote',
          label: 'Ulaşım / Kıyafet / Beslenme / KVKK Notu (Opsiyonel)',
          type: DocFieldType.text,
          defaultValue: 'Öğrencilerimizin okul kıyafeti ile katılması rica olunur.',
        ),
      ],
      composeBody: (a, ctx) {
        final extra = _str(a, 'extraNote');
        return '''
${ctx.schoolName.toUpperCase()} MÜDÜRLÜĞÜNE

MEB Eğitim Kurumları Sosyal Etkinlikler Yönetmeliği kapsamında; okulunuz {{SINIF}} şubesi, {{NO}} numaralı öğrencisi {{OGRENCI_ADI}}'nın, kurumunuz tarafından ${_str(a, 'eventDate', _today())} tarihinde ${_str(a, 'timeRange', '09:00 - 15:30')} saatleri arasında "${_str(a, 'destination')}" adresine düzenlenecek olan "${_str(a, 'eventTitle')}" faaliyetine katılmasına muvafakat ediyorum (izin veriyorum).

Öğrencimin kafile kurallarına uyması hususunda bilgilendirildiğini ve etkinlik süresince bilinmesi gereken özel bir sağlık/alerji/ilaç durumu varsa aşağıda belirttiğimi beyan ederim.${extra.isNotEmpty ? '\nNot: $extra' : ''}''';
      },
    ),

    OfficialDocTemplate(
      id: 'okul_gezisi_kafile_onay_paketi',
      code: '5.2',
      categoryId: 'idari_gezi_toren',
      title: 'Okul Gezisi Resmi Onay ve Öğrenci Kafile Listesi',
      subtitle: 'Gezi güvenlik planı, kafile başkanı/gözetmen görevlendirmesi ve öğrenci TC/veli telefon tablosu',
      audience: DocAudience.admin,
      layoutKind: DocLayoutKind.circularSignatureTable,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.directions_bus_rounded,
      questions: [
        const DocQuestionField(key: 'targetClasses', label: 'Geziye Katılacak Şubeler', type: DocFieldType.multiClassSelect, required: true),
        const DocQuestionField(key: 'tripName', label: 'Gezi Adı ve Eğitsel Amacı', type: DocFieldType.text, defaultValue: 'Eğitsel, Tarihi ve Bilimsel Müze İnceleme Gezisi', required: true),
        const DocQuestionField(key: 'destination', label: 'Gezi Güzergâhı / İl - İlçe', type: DocFieldType.text, required: true, defaultValue: 'İl İçi Kültür, Müze ve Bilim Rotası'),
        DocQuestionField(key: 'date', label: 'Gezi Tarihi ve Hareket-Dönüş Saatleri', type: DocFieldType.text, defaultValue: '${_today()} (09:00 - 16:00)'),
        const DocQuestionField(key: 'leader', label: 'Kafile Başkanı (İdareci / Öğretmen)', type: DocFieldType.staffSelect),
        const DocQuestionField(key: 'supervisors', label: 'Sorumlu Gözetmen Öğretmenler', type: DocFieldType.multiStaffSelect),
        const DocQuestionField(key: 'vehicleInfo', label: 'Araç Plakası, Firma ve Sürücü İletişim Bilgisi', type: DocFieldType.text, hint: 'Örn: 06 ABC 123 - D2 Yetki Belgeli Turizm Taşıma'),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Gezi Adı / Güzergâh', '${_str(a, "tripName")} — ${_str(a, "destination")}'),
        MapEntry('Gezi Tarih / Saat', _str(a, 'date')),
        MapEntry('Kafile Başkanı', _str(a, 'leader', ctx.principalName)),
        MapEntry('Sorumlu Öğretmenler', _list(a, 'supervisors').join(', ')),
        if (_str(a, 'vehicleInfo').isNotEmpty) MapEntry('Araç ve Sürücü Bilgisi', _str(a, 'vehicleInfo')),
      ],
      composeBody: (a, ctx) => '''
SOSYAL ETKİNLİK VE İNCELEME GEZİSİ İDARİ ONAY VE KAFİLE LİSTESİ

MEB Eğitim Kurumları Sosyal Etkinlikler Yönetmeliği çerçevesinde kurumumuz öğrencilerinin öğretim programlarıyla bütünleşik olarak tarihi, kültürel ve bilimsel kazanımlarını yerinde pekiştirmek amacıyla yukarıda bilgileri yer alan gezinin düzenlenmesi;
1) Tüm katılımcı öğrenciler için imzalı Veli İzin Belgesi (Muvafakatname) dosyalanması,
2) Ulaşım aracının Karayolu Taşıma Yönetmeliği şartlarına, koltuk ferdi kaza sigortasına ve emniyet kemeri donanımına sahip olduğunun kafile başkanınca hareket öncesi kontrol edilmesi,
3) Aşağıda kimlik ve veli iletişim bilgileri listelenen öğrenci kafilesinin belirtilen kafile başkanı ve gözetmen öğretmenler refakatinde geziye katılması uygun görülmüştür.''',
      buildSigners: (a, ctx) => [
        DocSigner(name: _str(a, 'leader', 'Kafile Başkanı'), title: 'Gezi Kafile Başkanı'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'OLUR'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'belirli_gun_toren_programi',
      code: '5.3',
      categoryId: 'idari_gezi_toren',
      title: 'Milli Bayram, Anma Günü ve Resmi Tören Kutlama Programı',
      subtitle: 'Ulusal bayramlar, 10 Kasım, 24 Kasım, belirli gün/haftalar tören akışı ve görev dağılım onayı',
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.celebration_rounded,
      questions: [
        const DocQuestionField(
          key: 'ceremonyName',
          label: 'Milli Bayram / Anma Günü / Hafta Programı',
          type: DocFieldType.dropdown,
          options: [
            'İlköğretim Haftası ve Eğitim-Öğretim Yılı Açılış Töreni',
            '29 Ekim Cumhuriyet Bayramı Kutlama Programı',
            '10 Kasım Atatürk\'ü Anma Günü ve Atatürk Haftası Programı',
            '24 Kasım Öğretmenler Günü Kutlama Programı',
            'Tutum, Yatırım ve Türk Malları (Yerli Malı) Haftası Etkinliği',
            '12 Mart İstiklal Marşı\'nın Kabulü ve Mehmet Akif Ersoy\'u Anma Programı',
            '18 Mart Şehitler Günü ve Çanakkale Deniz Zaferi\'ni Anma Programı',
            'Kütüphaneler Haftası ve Kitap Okuma Etkinliği Programı',
            '23 Nisan Ulusal Egemenlik ve Çocuk Bayramı Kutlama Programı',
            '19 Mayıs Atatürk\'ü Anma, Gençlik ve Spor Bayramı Kutlama Programı',
            'Çevre Koruma Haftası ve Sıfır Atık Etkinlik Programı',
            '15 Temmuz Demokrasi ve Millî Birlik Günü Anma Programı',
            'Karne Takdim, Yıl Sonu Kapanış ve Mezuniyet Töreni',
          ],
          defaultValue: '29 Ekim Cumhuriyet Bayramı Kutlama Programı',
        ),
        DocQuestionField(key: 'date', label: 'Tören Tarihi ve Başlama Saati', type: DocFieldType.text, defaultValue: '${_today()} - 09:30'),
        const DocQuestionField(key: 'place', label: 'Tören Alanı (ve Hava Muhalefeti Yedek Alanı)', type: DocFieldType.text, defaultValue: 'Okul Tören Bahçesi (Yağış halinde Çok Amaçlı Konferans Salonu)'),
        const DocQuestionField(key: 'presenter', label: 'Program Sunucusu Öğretmen / Öğrenci', type: DocFieldType.text, defaultValue: 'Türkçe / Edebiyat Zümresi Görevli Sunucuları'),
        const DocQuestionField(key: 'teachers', label: 'Tören Hazırlık ve Düzenleme Komisyonu Öğretmenleri', type: DocFieldType.multiStaffSelect),
        const DocQuestionField(
          key: 'flowItems',
          label: 'Resmi Tören Akış Maddeleri',
          type: DocFieldType.multiCheck,
          options: [
            'Tören komutanı tarafından öğrenci birliklerinin, bayrak ve flama kıtasının tören alanındaki yerini alması',
            'Açılış anonsu, Cumhuriyetimizin kurucusu Gazi Mustafa Kemal Atatürk ve aziz şehitlerimiz manevi huzurunda Saygı Duruşu ve İstiklal Marşı\'nın okunması',
            'Okul Müdürü tarafından günün anlam ve önemini belirten açılış konuşmasının yapılması',
            'Günün anlam ve önemine ilişkin öğrenci konuşması ve seçilen şiirlerin okunması',
            'Tarihsel süreç / belgesel / sinevizyon gösteriminin sunulması',
            'Okul korosu, müzik dinletisi ve oratoryo / dramatik gösterinin sahnelenmesi',
            'Halk oyunları / sportif / sanatsal gösterilerin sunulması',
            'İlçe / okul genelinde düzenlenen resim, şiir ve kompozisyon yarışmalarında dereceye giren öğrencilere ödüllerinin takdim edilmesi',
            'Tören geçişi / sergi açılışı ve programın kapanışı',
          ],
          defaultValue: [
            'Tören komutanı tarafından öğrenci birliklerinin, bayrak ve flama kıtasının tören alanındaki yerini alması',
            'Açılış anonsu, Cumhuriyetimizin kurucusu Gazi Mustafa Kemal Atatürk ve aziz şehitlerimiz manevi huzurunda Saygı Duruşu ve İstiklal Marşı\'nın okunması',
            'Okul Müdürü tarafından günün anlam ve önemini belirten açılış konuşmasının yapılması',
            'Günün anlam ve önemine ilişkin öğrenci konuşması ve seçilen şiirlerin okunması',
            'Okul korosu, müzik dinletisi ve oratoryo / dramatik gösterinin sahnelenmesi',
            'İlçe / okul genelinde düzenlenen resim, şiir ve kompozisyon yarışmalarında dereceye giren öğrencilere ödüllerinin takdim edilmesi',
            'Tören geçişi / sergi açılışı ve programın kapanışı',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Resmi Program Adı', _str(a, 'ceremonyName')),
        MapEntry('Tarih / Saat / Alan', '${_str(a, "date")} • ${_str(a, "place")}'),
        MapEntry('Sunum Sorumlusu', _str(a, 'presenter')),
        MapEntry('Tören Komisyonu', _list(a, 'teachers').join(', ')),
      ],
      composeBody: (a, ctx) => '''
ULUSAL VE RESMİ BAYRAMLAR / BELİRLİ GÜNLER TÖREN AKIŞ VE GÖREV PLANI

MEB Eğitim Kurumları Sosyal Etkinlikler Yönetmeliği ile Ulusal ve Resmi Bayramlar ve Kurtuluş Günlerinde Yapılacak Tören ve Kutlamalar Yönetmeliği esaslarına uygun olarak; ${ctx.schoolName} tarafından icra edilecek "${_str(a, 'ceremonyName')}", ${_str(a, 'date')} tarihinde ${_str(a, 'place')} alanında aşağıdaki akış ve sorumluluk düzeniyle gerçekleştirilecektir:

PROGRAM AKIŞ SIRASI:
${_numberedLines(_list(a, 'flowItems'))}

GÖREV VE HAZIRLIK TEDBİRLERİ:
1. Bayrak, flama, Atatürk köşesi/büstü, kürsü ve ses-mikrofon sisteminin son provası tören saatinden en az 30 dakika önce görevli öğretmenlerce tamamlanacaktır.
2. Tören süresince şube düzeni sınıf rehber öğretmenleri ve nöbetçi öğretmenler tarafından sağlanacaktır.''',
      buildSigners: (a, ctx) => [
        for (final t in _list(a, 'teachers').take(4)) DocSigner(name: t, title: 'Tören Komisyonu Üyesi'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'UYGUNDUR'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'sosyal_sportif_yarisma_onay',
      code: '5.4',
      categoryId: 'idari_gezi_toren',
      title: 'Okul Sporları / Bilim-Sanat Yarışması Katılım Onayı ve Kafile Listesi',
      subtitle: 'İl/ilçe spor müsabakaları, TÜBİTAK, Teknofest veya bilgi yarışması öğrenci kafile oluru',
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.circularSignatureTable,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.emoji_events_rounded,
      questions: [
        const DocQuestionField(key: 'targetClasses', label: 'Yarışmacı Öğrencilerin Şubeleri', type: DocFieldType.multiClassSelect, required: true),
        const DocQuestionField(
          key: 'competitionTitle',
          label: 'Müsabaka / Yarışma / Organizasyon Adı',
          type: DocFieldType.text,
          defaultValue: 'Okul Sporları Yıldızlar/Gençler İlçe Müsabakası',
          required: true,
        ),
        const DocQuestionField(key: 'venue', label: 'Müsabaka / Yarışma Yeri', type: DocFieldType.text, defaultValue: 'İlçe Gençlik ve Spor Müdürlüğü Kapalı Spor Salonu'),
        DocQuestionField(key: 'date', label: 'Tarih ve Saat Aralığı', type: DocFieldType.text, defaultValue: '${_today()} (09:30 - 15:00)'),
        const DocQuestionField(key: 'coachTeacher', label: 'Sorumlu Danışman / Beden Eğitimi Öğretmeni', type: DocFieldType.staffSelect, required: true),
        const DocQuestionField(key: 'adminLeader', label: 'Kafile Başkanı İdareci', type: DocFieldType.staffSelect),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Organizasyon / Müsabaka', _str(a, 'competitionTitle')),
        MapEntry('Müsabaka Yeri / Tarihi', '${_str(a, "venue")} • ${_str(a, "date")}'),
        MapEntry('Kafile Başkanı', _str(a, 'adminLeader', ctx.principalName)),
        MapEntry('Çalıştırıcı / Danışman Öğretmen', _str(a, 'coachTeacher')),
      ],
      composeBody: (a, ctx) => '''
OKUL SPORLARI / AKADEMİK VE KÜLTÜREL YARIŞMA KAFİLE KATILIM ONAYI

Kurumumuz ${ctx.schoolName} takım/proje grubunu temsilen aşağıda kimlik bilgileri yer alan öğrencilerimizin, ${_str(a, 'date')} tarihinde "${_str(a, 'venue')}" adresinde düzenlenecek olan "${_str(a, 'competitionTitle')}" etkinliğine veli izin belgeleri ve lisans/sağlık evrakları tam olarak, sorumlu öğretmen ${_str(a, 'coachTeacher')} refakatinde görevli-izinli olarak katılmaları uygun görülmüştür.''',
      buildSigners: (a, ctx) => [
        DocSigner(name: _str(a, 'coachTeacher', 'Danışman Öğretmen'), title: 'Sorumlu Öğretmen'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'OLUR'), isApproval: true),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // BAŞLIK 6: ZÜMRE, BEP, ORTAK SINAV VE AKADEMİK DERS EVRAKLARI (ÖĞRETMEN)
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'brans_zumre_tutanagi',
      code: '6.1',
      categoryId: 'ogretmen_zumre_akademik',
      title: 'Branş Zümre Öğretmenler Kurulu Toplantı Tutanağı',
      subtitle: 'Türkiye Yüzyılı Maarif Modeli, yıllık plan, ortak yazılı senaryoları, BEP ve zümre kararları',
      audience: DocAudience.teacher,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.auto_stories_rounded,
      questions: [
        const DocQuestionField(key: 'branch', label: 'Zümre Branşı / Dersi', type: DocFieldType.branchSelect, required: true),
        const DocQuestionField(
          key: 'termType',
          label: 'Zümre Dönemi',
          type: DocFieldType.dropdown,
          options: [
            '1. Dönem Başı Zümre Öğretmenler Kurulu Toplantısı',
            '2. Dönem Başı Zümre Öğretmenler Kurulu Toplantısı',
            'Sene Sonu Değerlendirme Zümre Öğretmenler Kurulu Toplantısı',
            'Ortak Sınav Öncesi Ara Değerlendirme Zümre Toplantısı',
          ],
          defaultValue: '1. Dönem Başı Zümre Öğretmenler Kurulu Toplantısı',
        ),
        DocQuestionField(key: 'date', label: 'Toplantı Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'time', label: 'Toplantı Saati', type: DocFieldType.time, defaultValue: '14:00'),
        const DocQuestionField(key: 'headTeacher', label: 'Zümre Başkanı Öğretmen', type: DocFieldType.staffSelect),
        const DocQuestionField(key: 'members', label: 'Zümreye Katılan Branş Öğretmenleri', type: DocFieldType.multiStaffSelect, required: true),
        const DocQuestionField(
          key: 'agenda',
          label: 'MEB Zümre Yönergesine Uygun Gündem Maddeleri',
          type: DocFieldType.multiCheck,
          options: [
            'Açılış, yoklama, yazman seçimi ve zümre başkanının belirlenmesi',
            'Bir önceki dönem/eğitim-öğretim yılı zümre kararlarının uygulama sonuçlarının ve akademik başarı düzeyinin değerlendirilmesi',
            'MEB Öğretim Programları, Türkiye Yüzyılı Maarif Modeli öğrenme çıktıları, beceri temelli çerçeve ve ünitelendirilmiş yıllık planların incelenmesi',
            'Atatürkçülük ile ilgili konuların ve belirli gün-haftaların ünitelendirilmiş yıllık planlara ve ders işlenişine yansıtılması',
            'Dersin işlenişinde uygulanacak öğretim yöntem ve teknikleri, EBA/EÖB dijital içerikleri, deney, gezi-gözlem ve laboratuvar kullanımı',
            'Diğer zümre ve alan öğretmenleriyle yapılacak yatay/dikey disiplinlerarası iş birliği esaslarının belirlenmesi',
            'MEB Yazılı ve Uygulamalı Sınavlar Yönergesi uyarınca ortak yazılı sınav tarihleri, konu-soru dağılım tabloları ve açık uçlu sınav senaryolarının kararlaştırılması',
            'Türkçe/Edebiyat ve Yabancı Dil derslerinde dört temel dil becerisi (dinleme, konuşma, okuma, yazma) ve diğer derslerde uygulamalı sınav ölçütlerinin belirlenmesi',
            'Kaynaştırma/bütünleştirme yoluyla eğitim gören öğrenciler için BEP (Bireyselleştirilmiş Eğitim Programı) ders hedefleri ve sınav uyarlamalarının planlanması',
            'Merkezi sınavlara (LGS / YKS / Bursluluk) ve kurumsal deneme sınavlarına hazırlık çalışmaları, kazanım analizleri ve DYK/etüt planlaması',
            'Öğrencilere verilecek proje ve ders içi performans görev konularının, teslim takviminin ve dereceli puanlama anahtarlarının (rubrik) belirlenmesi',
            'Okul ve çevre imkanlarının değerlendirilmesi; TÜBİTAK, Teknofest, yarışma ve bilim/sanat projelerine katılım hedeflerinin görüşülmesi',
            'Derslik, atölye ve laboratuvarlarda 6331 sayılı İş Sağlığı ve Güvenliği Kanunu kapsamında alınacak tedbirlerin görüşülmesi',
            'Dilek, temenniler ve kapanış',
          ],
          defaultValue: [
            'Açılış, yoklama, yazman seçimi ve zümre başkanının belirlenmesi',
            'Bir önceki dönem/eğitim-öğretim yılı zümre kararlarının uygulama sonuçlarının ve akademik başarı düzeyinin değerlendirilmesi',
            'MEB Öğretim Programları, Türkiye Yüzyılı Maarif Modeli öğrenme çıktıları, beceri temelli çerçeve ve ünitelendirilmiş yıllık planların incelenmesi',
            'Atatürkçülük ile ilgili konuların ve belirli gün-haftaların ünitelendirilmiş yıllık planlara ve ders işlenişine yansıtılması',
            'MEB Yazılı ve Uygulamalı Sınavlar Yönergesi uyarınca ortak yazılı sınav tarihleri, konu-soru dağılım tabloları ve açık uçlu sınav senaryolarının kararlaştırılması',
            'Kaynaştırma/bütünleştirme yoluyla eğitim gören öğrenciler için BEP (Bireyselleştirilmiş Eğitim Programı) ders hedefleri ve sınav uyarlamalarının planlanması',
            'Merkezi sınavlara (LGS / YKS / Bursluluk) ve kurumsal deneme sınavlarına hazırlık çalışmaları, kazanım analizleri ve DYK/etüt planlaması',
            'Öğrencilere verilecek proje ve ders içi performans görev konularının, teslim takviminin ve dereceli puanlama anahtarlarının (rubrik) belirlenmesi',
            'Derslik, atölye ve laboratuvarlarda 6331 sayılı İş Sağlığı ve Güvenliği Kanunu kapsamında alınacak tedbirlerin görüşülmesi',
            'Dilek, temenniler ve kapanış',
          ],
        ),
        const DocQuestionField(
          key: 'decisions',
          label: 'Alınan Zümre Kararları',
          type: DocFieldType.multiCheck,
          options: [
            'Ünitelendirilmiş yıllık planların MEB öğretim programı ve Türkiye Yüzyılı Maarif Modeli öğrenme çıktılarına tam uyumlu hazırlanarak eş zamanlı uygulanmasına karar verildi.',
            'Atatürkçülük konularının ilgili kazanımlarla bütünleştirilerek yıllık planlarda tarih ve saatleriyle açıkça gösterilmesine karar verildi.',
            'Her dönemde yapılacak ortak yazılı sınavların açık uçlu ve kısa cevaplı sorulardan oluşturulmasına; il/okul konu-soru dağılım tablosunun sınavdan en az bir hafta önce öğrencilere duyurulmasına karar verildi.',
            'Ortak sınavların zümre öğretmenlerince hazırlanan ayrıntılı cevap anahtarı üzerinden ortak kriterlerle değerlendirilmesine ve sınav analizlerinin 5 iş günü içinde çıkarılmasına karar verildi.',
            'Deneme ve yazılı sınav analizlerinde %65-%70 başarı barajının altında kalan kazanımlar için telafi ders anlatımı, çalışma yaprağı ve hedefli etüt uygulanmasına karar verildi.',
            'Kaynaştırma/bütünleştirme öğrencileri için BEP Geliştirme Birimi kararları doğrultusunda bireyselleştirilmiş ders planı ve uyarlanmış sınav kağıdı hazırlanmasına karar verildi.',
            'Derslerde akıllı tahta, EBA içerikleri, somut materyal, deney/gözlem ve öğrenci merkezli aktif öğrenme yöntemlerinin etkin kullanılmasına karar verildi.',
            'Öğrencilere en az bir ders saati performans değerlendirmesi ve talepleri doğrultusunda proje görevi verilmesine; proje konularının kasım ayında imza karşılığı tebliğ edilerek nisan ayının üçüncü haftasında teslim alınmasına karar verildi.',
            'Proje ve performans görevlerinin zümrece hazırlanan şeffaf dereceli puanlama anahtarı (rubrik) ile değerlendirilmesine karar verildi.',
            'Derslik, laboratuvar ve uygulama alanlarında iş sağlığı ve güvenliği kurallarının dönem başında öğrencilere anlatılmasına ve güvenlik tedbirlerinin titizlikle uygulanmasına karar verildi.',
            'Türkçe/Edebiyat ve Yabancı Dil derslerinde dört temel beceri (dinleme, konuşma, okuma, yazma) ağırlık oranlarının mevzuata uygun uygulanmasına ve uygulama ölçeklerinin dosyalanmasına karar verildi.',
            'Okul dışı öğrenme ortamları (müze, bilim merkezi, kütüphane, doğa alanları) etkinliklerinin yıllık planlarla ilişkilendirilmesine karar verildi.',
            'Akademik dürüstlük ve kopyanın önlenmesi amacıyla sınavlarda eşdeğer A/B kitapçık veya farklı soru grupları kullanılmasına karar verildi.',
            'Üstün/özel yetenekli öğrencilere zenginleştirilmiş araştırma görevleri ve proje yarışması rehberliği sunulmasına karar verildi.',
          ],
          defaultValue: [
            'Ünitelendirilmiş yıllık planların MEB öğretim programı ve Türkiye Yüzyılı Maarif Modeli öğrenme çıktılarına tam uyumlu hazırlanarak eş zamanlı uygulanmasına karar verildi.',
            'Her dönemde yapılacak ortak yazılı sınavların açık uçlu ve kısa cevaplı sorulardan oluşturulmasına; il/okul konu-soru dağılım tablosunun sınavdan en az bir hafta önce öğrencilere duyurulmasına karar verildi.',
            'Deneme ve yazılı sınav analizlerinde %65-%70 başarı barajının altında kalan kazanımlar için telafi ders anlatımı, çalışma yaprağı ve hedefli etüt uygulanmasına karar verildi.',
            'Kaynaştırma/bütünleştirme öğrencileri için BEP Geliştirme Birimi kararları doğrultusunda bireyselleştirilmiş ders planı ve uyarlanmış sınav kağıdı hazırlanmasına karar verildi.',
            'Proje ve performans görevlerinin zümrece hazırlanan şeffaf dereceli puanlama anahtarı (rubrik) ile değerlendirilmesine karar verildi.',
          ],
        ),
        const DocQuestionField(
          key: 'extraNotes',
          label: 'Ders Bazlı Özel Sınav Tarihleri / Ek Zümre Notu (Opsiyonel)',
          type: DocFieldType.multiline,
          hint: 'Örn: 1. Yazılı: 04.11.2026 (Senaryo 2), 2. Yazılı: 30.12.2026 (Senaryo 1)...',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Zümre Branşı / Alanı', _str(a, 'branch', 'Genel Branş')),
        MapEntry('Toplantı Dönemi', '${ctx.academicYear} — ${_str(a, "termType")}'),
        MapEntry('Tarih / Saat', '${_str(a, "date", _today())} - ${_str(a, "time", "14:00")}'),
        MapEntry('Zümre Başkanı', _str(a, 'headTeacher', ctx.currentUser?.fullName ?? '-')),
      ],
      composeBody: (a, ctx) {
        final branch = _str(a, 'branch', 'İlgili Ders');
        final termType = _str(a, 'termType', 'Zümre Toplantısı');
        final head = _str(a, 'headTeacher', ctx.currentUser?.fullName ?? 'Zümre Başkanı');
        final members = _list(a, 'members');
        final extra = _str(a, 'extraNotes');
        return '''
MEB Eğitim Kurumları Kurulları ve Zümreleri Yönergesi hükümleri uyarınca; ${ctx.academicYear} Eğitim ve Öğretim Yılı ${ctx.schoolName} "$branch Dersi $termType", ${_str(a, 'date', _today())} tarihinde saat ${_str(a, 'time', '14:00')}'da Zümre Başkanı $head başkanlığında zümre öğretmenlerinin (${members.join(', ')}) katılımıyla gerçekleştirilmiştir.

GÜNDEM MADDELERİ:
${_numberedLines(_list(a, 'agenda'))}

GÜNDEMİN GÖRÜŞÜLMESİ VE ALINAN ZÜMRE KARARLARI:
Gündem maddeleri yürürlükteki MEB öğretim programı, Türkiye Yüzyılı Maarif Modeli esasları, okulun fiziki/teknolojik imkanları ve öğrenci hazırbulunuşluk düzeyleri dikkate alınarak ayrıntılı biçimde değerlendirilmiş; aşağıdaki kararlar oy birliği ile alınmıştır:

${_numberedLines(_list(a, 'decisions'), prefix: 'Karar ')}${extra.isNotEmpty ? '\n\nÖZEL SINAV TAKVİMİ / EK ZÜMRE NOTLARI:\n$extra' : ''}

İşbu zümre toplantı tutanağı 2 (iki) nüsha olarak düzenlenmiş ve tarafımızca imza altına alınarak Okul Müdürlüğünün onayına sunulmuştur.''';
      },
      buildSigners: (a, ctx) {
        final members = _list(a, 'members');
        final head = _str(a, 'headTeacher');
        return [
          for (final m in members)
            DocSigner(name: m, title: m == head ? 'Zümre Başkanı' : 'Zümre Öğretmeni'),
          DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'UYGUNDUR'), isApproval: true),
        ];
      },
    ),

    OfficialDocTemplate(
      id: 'ortak_sinav_analiz_telafi_tutanagi',
      code: '6.2',
      categoryId: 'ogretmen_zumre_akademik',
      title: 'Ortak Sınav / Yazılı Kazanım Analizi ve Telafi Tutanağı',
      subtitle: 'Sınav başarı dağılımı, baraj altı kalan öğrenme çıktıları ve telafi eylem raporu',
      audience: DocAudience.teacher,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.query_stats_rounded,
      questions: [
        const DocQuestionField(key: 'targetClass', label: 'Şube Seçimi', type: DocFieldType.classSelect, required: true),
        const DocQuestionField(key: 'branch', label: 'Ders / Branş', type: DocFieldType.branchSelect, required: true),
        const DocQuestionField(
          key: 'examTitle',
          label: 'Değerlendirilen Sınav',
          type: DocFieldType.dropdown,
          options: [
            '1. Dönem 1. Ortak Yazılı Sınavı',
            '1. Dönem 2. Ortak Yazılı Sınavı',
            '2. Dönem 1. Ortak Yazılı Sınavı',
            '2. Dönem 2. Ortak Yazılı Sınavı',
            'İl / İlçe / Bakanlık Ortak Yazılı Sınavı',
            'Kurumsal Kazanım Değerlendirme / Deneme Sınavı',
          ],
          defaultValue: '1. Dönem 1. Ortak Yazılı Sınavı',
        ),
        DocQuestionField(key: 'date', label: 'Analiz Rapor Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'avgScore', label: 'Şube Puan Ortalaması ve Başarı Oranı (%)', type: DocFieldType.text, defaultValue: '72,4 Puan / %72 Başarı (50+ Alan Öğrenci Oranı: %84)'),
        const DocQuestionField(
          key: 'weakOutcomes',
          label: 'Kazanım Başarısı Düşük Tespit Edilen Konular / Öğrenme Çıktıları',
          type: DocFieldType.multiline,
          hint: 'Örn: M.7.1.3 Rasyonel sayılarla çok adımlı işlemler kazanımı (%48 başarı)',
          required: true,
        ),
        const DocQuestionField(
          key: 'remedialActions',
          label: 'Planlanan Telafi, Farklılaştırılmış Öğretim ve Destek Çalışmaları',
          type: DocFieldType.multiCheck,
          options: [
            'Sınıf içinde kazanım başarısı %60\'ın altında kalan sorular ve ilgili konular için 1-2 ders saati yapılandırılmış telafi anlatımı yapılacaktır.',
            'Açık uçlu sorularda sık yapılan kavram yanılgıları ve işlem hataları tahtada örnek çözümlerle giderilecektir.',
            '50 puan barajının altında kalan öğrencilere hedefli kazanım kavrama çalışma yaprağı verilerek bireysel geri bildirim sağlanacaktır.',
            'Destekleme kursu (DYK) ve hafta içi etüt saatlerinde ilgili öğrencilerle küçük grup telafi çalışması uygulanacaktır.',
            'Sınıf rehber öğretmeni ve öğrenci velileri bilgilendirilerek ev tekrar takibi güçlendirilecektir.',
            'Bir sonraki sınav ve sınıf içi uygulamalarda söz konusu öğrenme çıktılarının kalıcılığı yeniden ölçülecektir.',
            'Görsel/işitsel materyaller, EBA/MEBİ dijital içerikleri ve somut örneklerle farklılaştırılmış öğretim etkinlikleri uygulanacaktır.',
            'Akran öğretimi ve iş birlikli öğrenme grupları oluşturularak öğrencilerin birbirini desteklemesi sağlanacaktır.',
            'Okuduğunu anlama ve soru kökünü doğru analiz etme hatalarına yönelik örnek soru çözüm atölyesi yapılacaktır.',
            'BEP kapsamındaki kaynaştırma öğrencilerinin bireyselleştirilmiş sınav performansları ayrıca değerlendirilerek hedefleri güncellenecektir.',
          ],
          defaultValue: [
            'Sınıf içinde kazanım başarısı %60\'ın altında kalan sorular ve ilgili konular için 1-2 ders saati yapılandırılmış telafi anlatımı yapılacaktır.',
            'Açık uçlu sorularda sık yapılan kavram yanılgıları ve işlem hataları tahtada örnek çözümlerle giderilecektir.',
            '50 puan barajının altında kalan öğrencilere hedefli kazanım kavrama çalışma yaprağı verilerek bireysel geri bildirim sağlanacaktır.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Şube / Ders', '${_str(a, "targetClass")} — ${_str(a, "branch")}'),
        MapEntry('Değerlendirilen Sınav', _str(a, 'examTitle')),
        MapEntry('Şube Başarı Verisi', _str(a, 'avgScore')),
        MapEntry('Analiz Tarihi', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
ORTAK YAZILI / DENEME SINAVI MADDE VE KAZANIM ANALİZİ TELAFİ TUTANAĞI

MEB Yazılı ve Uygulamalı Sınavlar Yönergesi uyarınca yapılan soru ve kazanım bazlı sınav analizi sonucunda aşağıdaki tespitler yapılmış ve telafi eylem adımları kararlaştırılmıştır:

1. GÜÇLENDİRİLMESİ GEREKEN KONU VE ÖĞRENME ÇIKTILARI:
${_str(a, 'weakOutcomes')}

2. KARARLAŞTIRILAN TELAFİ VE DESTEKLEME ÇALIŞMALARI:
${_numberedLines(_list(a, 'remedialActions'))}

Yukarıda belirtilen kazanım eksikliklerinin giderilmesine yönelik telafi süreci ders öğretmeni tarafından uygulanarak zümre dosyasında muhafaza edilecektir.''',
      buildSigners: (a, ctx) => [
        DocSigner(name: ctx.currentUser?.fullName ?? 'Ders Öğretmeni', title: '${_str(a, "branch")} Öğretmeni'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'İNCELENDİ / UYGUNDUR'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'proje_odevi_dagitim_cizelgesi',
      code: '6.3',
      categoryId: 'ogretmen_zumre_akademik',
      title: 'Proje / Performans Ödevi Dağıtım ve İmza Çizelgesi',
      subtitle: 'Seçilen şube öğrencilerine proje konularının, rubrik ölçütlerinin ve teslim tarihinin imza karşılığı tebliği',
      audience: DocAudience.teacher,
      layoutKind: DocLayoutKind.circularSignatureTable,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.assignment_turned_in_rounded,
      questions: [
        const DocQuestionField(key: 'targetClasses', label: 'Şube Seçimi', type: DocFieldType.multiClassSelect, required: true),
        const DocQuestionField(key: 'branch', label: 'Ders Adı', type: DocFieldType.branchSelect, required: true),
        DocQuestionField(key: 'givenDate', label: 'Ödev Tebliğ / Veriliş Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'interimDate', label: 'Ara Kontrol Tarihi', type: DocFieldType.text, defaultValue: '15.02.2027'),
        const DocQuestionField(key: 'dueDate', label: 'Son Teslim Tarihi', type: DocFieldType.text, defaultValue: '16.04.2027'),
        const DocQuestionField(
          key: 'criteria',
          label: 'Dereceli Puanlama (Rubrik) Değerlendirme Ölçütleri',
          type: DocFieldType.multiCheck,
          options: [
            'Bilimsel içerik doğruluğu, araştırma derinliği ve güvenilir kaynakça kullanımı (25 Puan)',
            'Özgünlük, yaratıcılık, materyal/görsel düzen ve yazım kurallarına uyum (25 Puan)',
            'Planlama ve ara kontrol takvimine uyum, süreç içi öğretmen rehberliğinden yararlanma (20 Puan)',
            'Zamanında ve eksiksiz teslim etme sorumluluğu (10 Puan)',
            'Konuyu kavrama, sınıfta sunma ve yöneltilen soruları yanıtlama becerisi (20 Puan)',
          ],
          defaultValue: [
            'Bilimsel içerik doğruluğu, araştırma derinliği ve güvenilir kaynakça kullanımı (25 Puan)',
            'Özgünlük, yaratıcılık, materyal/görsel düzen ve yazım kurallarına uyum (25 Puan)',
            'Planlama ve ara kontrol takvimine uyum, süreç içi öğretmen rehberliğinden yararlanma (20 Puan)',
            'Zamanında ve eksiksiz teslim etme sorumluluğu (10 Puan)',
            'Konuyu kavrama, sınıfta sunma ve yöneltilen soruları yanıtlama becerisi (20 Puan)',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Ders / Şube', '${_str(a, "branch")} — ${_list(a, "targetClasses").join(", ")}'),
        MapEntry('Tebliğ / Ara Kontrol / Teslim', '${_str(a, "givenDate", _today())}  →  Ara: ${_str(a, "interimDate")}  →  Teslim: ${_str(a, "dueDate")}'),
        MapEntry('Ders Öğretmeni', ctx.currentUser?.fullName ?? '-'),
      ],
      composeBody: (a, ctx) => '''
PROJE / PERFORMANS GÖREVİ TEBLİĞ VE DERECELİ PUANLAMA ESASLARI

Aşağıda isim ve numaraları yer alan öğrencilere ${ctx.academicYear} Eğitim ve Öğretim Yılı "${_str(a, 'branch')}" dersi proje/performans görev konuları, ara kontrol tarihi ve son teslim takvimi açıklanarak imza karşılığı tebliğ edilmiştir.

DEĞERLENDİRME ÖLÇÜTLERİ (TOPLAM 100 PUAN):
${_numberedLines(_list(a, 'criteria'))}''',
      buildSigners: (a, ctx) => [
        DocSigner(name: ctx.currentUser?.fullName ?? 'Ders Öğretmeni', title: 'Ders Öğretmeni'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'ogretmen_bep_ders_plani_formu',
      code: '6.4',
      categoryId: 'ogretmen_zumre_akademik',
      title: 'Öğretmen Ders Bazlı BEP (Bireyselleştirilmiş Eğitim Programı) Formu',
      subtitle: 'Kaynaştırma öğrencisi için uzun/kısa dönemli amaçlar, öğretim uyarlaması ve değerlendirme planı',
      audience: DocAudience.teacher,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.accessibility_new_rounded,
      questions: [
        const DocQuestionField(key: 'targetClass', label: 'Öğrencinin Şubesi', type: DocFieldType.classSelect, required: true),
        const DocQuestionField(key: 'student', label: 'BEP Hazırlanan Öğrenci', type: DocFieldType.studentSelect, required: true),
        const DocQuestionField(key: 'branch', label: 'Ders / Alan Adı', type: DocFieldType.branchSelect, required: true),
        DocQuestionField(key: 'date', label: 'Plan Hazırlama Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(
          key: 'currentPerformance',
          label: 'Öğrencinin Eğitsel Performans Düzeyi (Mevcut Durumu)',
          type: DocFieldType.multiline,
          defaultValue: 'Öğrenci temel kavramları görsel ipuçları ve somut örneklerle desteklendiğinde kavrayabilmekte, kısa yönergeleri takip edebilmektedir.',
        ),
        const DocQuestionField(
          key: 'longShortGoals',
          label: 'Uzun ve Kısa Dönemli Öğretim Amaçları',
          type: DocFieldType.multiline,
          defaultValue: 'Uzun Dönemli Amaç: Dersin temel kavram ve becerilerini günlük yaşamla ilişkilendirerek bağımsız uygular.\nKısa Dönemli Amaçlar:\n1. Verilen görsel/yazılı materyaldeki temel kavramları %75 (3/4) ölçütünde doğru eşleştirir ve açıklar.\n2. Öğretmen rehberliğinde tek ve iki adımlı temel uygulama etkinliklerini tamamlar.',
          required: true,
        ),
        const DocQuestionField(
          key: 'adaptations',
          label: 'Öğretim Yöntemi, Materyal ve Ölçme-Değerlendirme Uyarlamaları',
          type: DocFieldType.multiCheck,
          options: [
            'Sınıf içinde öğretmene yakın ve dikkat dağıtıcı unsurlardan uzak ön sıraya oturtma düzenlemesi',
            'Doğrudan öğretim, gösterip yaptırma, somutlaştırma ve basamaklandırılmış öğretim yöntemi',
            'Büyük puntolu çalışma yaprakları, görsel şemalar ve sadeleştirilmiş yönergeler kullanma',
            'Bireyselleştirilmiş yazılı/uygulamalı BEP sınav soruları hazırlama ve ek sınav süresi tanıma',
            'Süreç içi küçük adımlı başarıları sözlü pekiştireçlerle destekleme ve veli-rehberlik iş birliği',
            'Akran öğretimi / duyarlı sıra arkadaşı eşleştirmesi ile sosyal katılımı ve grup uyumunu destekleme',
            'Karmaşık ve uzun görevleri kısa, anlaşılır alt basamaklara bölerek adım adım geri bildirim verme',
            'Destek Eğitim Odası öğretmeni ve Okul PDR Servisi ile aylık eşgüdüm sağlayarak BEP izleme çizelgesi tutma',
            'Ev tekrar çalışmalarını velinin rehberlik edebileceği somut etkinlik kartlarıyla destekleme',
          ],
          defaultValue: [
            'Sınıf içinde öğretmene yakın ve dikkat dağıtıcı unsurlardan uzak ön sıraya oturtma düzenlemesi',
            'Doğrudan öğretim, gösterip yaptırma, somutlaştırma ve basamaklandırılmış öğretim yöntemi',
            'Bireyselleştirilmiş yazılı/uygulamalı BEP sınav soruları hazırlama ve ek sınav süresi tanıma',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Ders / Eğitim Yılı', '${_str(a, "branch")} — ${ctx.academicYear}'),
        MapEntry('Hazırlayan Öğretmen', ctx.currentUser?.fullName ?? '-'),
        MapEntry('Tarih', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
BİREYSELLEŞTİRİLMİŞ EĞİTİM PROGRAMI (BEP) DERS VE İZLEME PLANI

1. ÖĞRENCİNİN EĞİTSEL PERFORMANS DÜZEYİ:
${_str(a, 'currentPerformance')}

2. UZUN VE KISA DÖNEMLİ ÖĞRETİM AMAÇLARI (ÖLÇÜT: %75 - 3/4):
${_str(a, 'longShortGoals')}

3. ÖĞRETİMSEL DÜZENLEMELER, MATERYALLER VE ÖLÇME-DEĞERLENDİRME UYARLAMALARI:
${_numberedLines(_list(a, 'adaptations'))}

İşbu BEP ders planı Özel Eğitim Hizmetleri Yönetmeliği hükümlerine uygun olarak hazırlanmış olup BEP Geliştirme Birimi dosyasına sunulmuştur.''',
      buildSigners: (a, ctx) => [
        DocSigner(name: ctx.currentUser?.fullName ?? 'Ders Öğretmeni', title: '${_str(a, "branch")} Öğretmeni'),
        DocSigner(
          name: ctx.counselors.isNotEmpty ? ctx.counselors.first.fullName : 'Rehber Öğretmen / Psikolojik Danışman',
          title: 'BEP Birimi Üyesi (PDR)',
        ),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'UYGUNDUR'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'uygulamali_sinav_degerlendirme_tutanagi',
      code: '6.5',
      categoryId: 'ogretmen_zumre_akademik',
      title: 'Uygulamalı Sınav / Dinleme-Konuşma Sınavı Değerlendirme Çizelgesi',
      subtitle: 'Türkçe/Edebiyat, Yabancı Dil (Dinleme-Konuşma) ve Görsel/Müzik/Beden Eğitimi 4 ölçütlü puan tablosu',
      audience: DocAudience.teacher,
      layoutKind: DocLayoutKind.circularSignatureTable,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.record_voice_over_rounded,
      questions: [
        const DocQuestionField(key: 'targetClasses', label: 'Uygulama Yapılan Şube', type: DocFieldType.multiClassSelect, required: true),
        const DocQuestionField(key: 'branch', label: 'Ders Adı', type: DocFieldType.branchSelect, required: true),
        const DocQuestionField(
          key: 'examMode',
          label: 'Uygulamalı Sınav Türü',
          type: DocFieldType.dropdown,
          options: [
            'Türkçe / Türk Dili ve Edebiyatı — Konuşma Becerisi Sınavı',
            'Türkçe / Türk Dili ve Edebiyatı — Dinleme Becerisi Sınavı',
            'Yabancı Dil (İngilizce / Almanca) — Speaking (Konuşma) Sınavı',
            'Yabancı Dil (İngilizce / Almanca) — Listening (Dinleme) Sınavı',
            'Beden Eğitimi ve Spor / Görsel Sanatlar / Müzik / Bilişim Uygulama Sınavı',
            'Fen / Fizik / Kimya / Biyoloji Laboratuvar Uygulama Değerlendirmesi',
          ],
          defaultValue: 'Türkçe / Türk Dili ve Edebiyatı — Konuşma Becerisi Sınavı',
        ),
        DocQuestionField(key: 'date', label: 'Uygulama Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(
          key: 'rubricItems',
          label: 'Puanlama Tablosundaki 4 Değerlendirme Ölçütü Açıklaması (Her Biri 25 Puan)',
          type: DocFieldType.multiline,
          defaultValue: '1. Ölçüt (25p): Konuya hakimiyet, içerik tutarlılığı ve amaca uygunluk\n2. Ölçüt (25p): Akıcılık, telaffuz/boğumlama ve dil kurallarına/tekniğe uyum\n3. Ölçüt (25p): Kelime dağarcığı / materyal-araç kullanımı ve özgünlük\n4. Ölçüt (25p): Beden dili, özgüven, zaman yönetimi ve sunum/uygulama bütünlüğü',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Şube / Ders', '${_list(a, "targetClasses").join(", ")} — ${_str(a, "branch")}'),
        MapEntry('Uygulama Türü', _str(a, 'examMode')),
        MapEntry('Uygulama Tarihi', _str(a, 'date', _today())),
        MapEntry('Ders Öğretmeni', ctx.currentUser?.fullName ?? '-'),
      ],
      composeBody: (a, ctx) => '''
UYGULAMALI SINAV / DİL BECERİLERİ ÖLÇME VE DEĞERLENDİRME TUTANAĞI

MEB Yazılı ve Uygulamalı Sınavlar Yönergesi hükümleri uyarınca yürütülen "${_str(a, 'examMode')}" uygulaması aşağıda tanımlanan dereceli puanlama anahtarı (4x25 = 100 Tam Puan) doğrultusunda değerlendirilmiştir:

${_str(a, 'rubricItems')}''',
      buildSigners: (a, ctx) => [
        DocSigner(name: ctx.currentUser?.fullName ?? 'Ders Öğretmeni', title: 'Uygulayıcı Ders Öğretmeni'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'ONAY'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'ogretmen_evrak_plan_teslim_tutanagi',
      code: '6.6',
      categoryId: 'ogretmen_zumre_akademik',
      title: 'Öğretmen Yıllık Plan, Sınav Evrakı ve Dönem Sonu Dosya Teslim Tutanağı',
      subtitle: 'Okul idaresine teslim edilen yazılı kağıtları, cevap anahtarları, planlar ve tutanakların alındı belgesi',
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.folder_copy_rounded,
      questions: [
        const DocQuestionField(key: 'teacher', label: 'Teslim Eden Öğretmen', type: DocFieldType.staffSelect),
        const DocQuestionField(key: 'branch', label: 'Branşı / Görevi', type: DocFieldType.branchSelect),
        const DocQuestionField(key: 'receiverAdmin', label: 'Teslim Alan Müdür Yardımcısı', type: DocFieldType.staffSelect),
        DocQuestionField(key: 'date', label: 'Teslim Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(
          key: 'submissionPeriod',
          label: 'Teslim Dönemi',
          type: DocFieldType.dropdown,
          options: [
            'Sene Başı Plan ve Zümre Evrakları Teslimi',
            '1. Dönem Ortak Sınav Evrakları ve Analiz Teslimi',
            '1. Dönem Sonu Kapanış Evrakları Teslimi',
            '2. Dönem Ortak Sınav Evrakları ve Analiz Teslimi',
            'Yıl Sonu (Haziran) Kapanış ve Arşiv Evrakları Teslimi',
          ],
          defaultValue: '1. Dönem Sonu Kapanış Evrakları Teslimi',
        ),
        const DocQuestionField(
          key: 'deliveredDocs',
          label: 'İdareye Teslim Edilen Evrak ve Dosyalar',
          type: DocFieldType.multiCheck,
          options: [
            'Ünitelendirilmiş Yıllık Ders Planları ve Ders Kesim Raporu',
            'Branş Zümre Öğretmenler Kurulu Toplantı Tutanağı',
            'Ortak Yazılı Sınav Zarfları (Sınav Kağıtları, Konu-Soru Dağılım Tablosu, Cevap Anahtarı ve Yoklama)',
            'Uygulamalı Sınav / Dinleme-Konuşma / Performans ve Proje Değerlendirme Ölçekleri',
            'Sınav Madde-Kazanım Analizleri ve Telafi Eğitimi Tutanakları',
            'Kaynaştırma Öğrencileri BEP Planları ve Dönem Sonu BEP Gelişim Raporları',
            'Sınıf Rehberlik Dosyası, Veli Toplantı ve Bireysel Veli Görüşme Tutanakları',
            'Öğrenci Kulübü ve Toplum Hizmeti Faaliyet Dosyası / Yıl Sonu Raporu',
            'e-Okul Not, Davranış Notu, Kitap Okuma ve Sosyal Etkinlik Girişleri Tamamlandı Beyanı',
            'Ortak Yazılı Mazeret Sınavı Evrakları ve Uygulama Yoklama Tutanakları',
            'Destekleme ve Yetiştirme Kursu (DYK) / İYEP / Destek Eğitim Odası Plan ve Defterleri',
            'Şube Öğretmenler Kurulu (ŞÖK) Tutanakları ve Öğrenci İzleme Dosyası',
            'Laboratuvar / Atölye / Sınıf Demirbaş ve Etkileşimli Tahta Sağlam Teslim Kontrolü',
          ],
          defaultValue: [
            'Ortak Yazılı Sınav Zarfları (Sınav Kağıtları, Konu-Soru Dağılım Tablosu, Cevap Anahtarı ve Yoklama)',
            'Uygulamalı Sınav / Dinleme-Konuşma / Performans ve Proje Değerlendirme Ölçekleri',
            'Sınav Madde-Kazanım Analizleri ve Telafi Eğitimi Tutanakları',
            'e-Okul Not, Davranış Notu, Kitap Okuma ve Sosyal Etkinlik Girişleri Tamamlandı Beyanı',
          ],
        ),
        const DocQuestionField(key: 'packageCount', label: 'Teslim Edilen Sınav Zarfı / Klasör Adedi Notu (Opsiyonel)', type: DocFieldType.text, hint: 'Örn: Toplam 6 adet mühürlü/imzalı yazılı sınav zarfı'),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Teslim Eden Öğretmen', '${_str(a, "teacher", ctx.currentUser?.fullName ?? "-")} (${_str(a, "branch", "-")})'),
        MapEntry('Teslim Dönemi', _str(a, 'submissionPeriod')),
        MapEntry('Teslim Tarihi', _str(a, 'date', _today())),
        if (_str(a, 'packageCount').isNotEmpty) MapEntry('Zarf / Klasör Adedi', _str(a, 'packageCount')),
      ],
      composeBody: (a, ctx) => '''
ÖĞRETMEN RESMİ EVRAK VE ARŞİV DOSYASI TESLİM-TESELLÜM TUTANAĞI

${ctx.academicYear} Eğitim ve Öğretim Yılı "${_str(a, 'submissionPeriod')}" kapsamında aşağıda maddeler halinde sayılan resmi eğitim-öğretim evrakları kontrol edilerek eksiksiz şekilde Okul İdaresine teslim edilmiş ve arşivlenmek üzere teslim alınmıştır:

TESLİM EDİLEN BELGELER:
${_numberedLines(_list(a, 'deliveredDocs'))}

İşbu evrak teslim tutanağı 2 (iki) nüsha olarak düzenlenmiş olup bir nüshası ilgili öğretmene verilmiştir.''',
      buildSigners: (a, ctx) => [
        DocSigner(name: _str(a, 'teacher', ctx.currentUser?.fullName ?? 'Öğretmen'), title: 'Teslim Eden Öğretmen'),
        DocSigner(
          name: _str(a, 'receiverAdmin', ctx.vicePrincipals.isNotEmpty ? ctx.vicePrincipals.first.fullName : ctx.principalName),
          title: 'Kontrol Ederek Teslim Alan İdareci',
        ),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // BAŞLIK 7: SINIF REHBERLİK VE VELİ GÖRÜŞME EVRAKLARI (ÖĞRETMEN)
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'veli_toplantisi_paketi',
      code: '7.1',
      categoryId: 'ogretmen_sinif_veli',
      title: 'Veli Toplantısı Tutanağı ve Veli İmza Çizelgesi',
      subtitle: 'Zengin veli toplantı gündemi, kararlar ve seçilen şubenin hazır öğrenci-veli imza tablosu',
      audience: DocAudience.teacher,
      layoutKind: DocLayoutKind.circularSignatureTable,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.people_alt_rounded,
      questions: [
        const DocQuestionField(key: 'targetClasses', label: 'Toplantı Yapılan Şube', type: DocFieldType.multiClassSelect, required: true),
        const DocQuestionField(
          key: 'termLabel',
          label: 'Toplantı Dönemi',
          type: DocFieldType.dropdown,
          options: [
            '1. Dönem Başı Genel Veli Toplantısı',
            '1. Dönem Ara Değerlendirme Veli Toplantısı',
            '2. Dönem Başı Genel Veli Toplantısı',
            'Merkezi Sınav (LGS / YKS) Bilgilendirme Veli Toplantısı',
          ],
          defaultValue: '1. Dönem Başı Genel Veli Toplantısı',
        ),
        DocQuestionField(key: 'date', label: 'Toplantı Tarihi ve Saati', type: DocFieldType.text, defaultValue: '${_today()} - 13:00'),
        const DocQuestionField(key: 'advisor', label: 'Sınıf Rehber Öğretmeni', type: DocFieldType.staffSelect),
        const DocQuestionField(
          key: 'agenda',
          label: 'Görüşülen Gündem Maddeleri ve Veli-Okul İş Birliği Kararları',
          type: DocFieldType.multiCheck,
          options: [
            'Açılış, yoklama ve sınıfın genel akademik, sosyal ve gelişimsel durumunun paylaşılması',
            'MEB Kurum Yönetmeliği: devam-devamsızlık sınırları, özür belgesi teslim süreleri (5 iş günü), derse zamanında giriş ve kılık-kıyafet kuralları',
            'Yeni sınav sistemi: açık uçlu ortak yazılı sınavlar, konu-soru dağılım tabloları, uygulamalı sınavlar ve e-Okul takibi',
            'Kurumsal deneme sınavları, kazanım analizleri, etüt/DYK çalışmaları ve eylem planı süreçlerinin değerlendirilmesi',
            'Evde verimli ders çalışma ortamının oluşturulması, düzenli uyku/kahvaltı alışkanlığı ve günlük kitap okuma rutini',
            'Dijital bağımlılıkla mücadele: akıllı telefon, oyun ve sosyal medya ekran sürelerinin ailece sınırlandırılması',
            'Akran nezaketi, siber zorbalığın önlenmesi ve okula cep telefonu/yasaklı eşya getirilmemesi kuralının hatırlatılması',
            'Özel sağlık durumu, alerji veya sürekli ilaç kullanımı olan öğrenciler hakkında sınıf rehber öğretmeninin bilgilendirilmesi',
            'Okul-Aile Birliği çalışmaları, sosyal-kültürel etkinlikler ve veli görüşme saatleri düzeninin paylaşılması',
            'Servis/ulaşım güvenliği, sabah giriş-akşam çıkış saatleri ve okul bahçesi güvenlik kurallarının hatırlatılması',
            'Olumlu davranış geliştirme süreci (sözlü uyarı, EK-9 öğrenci sözleşmesi ve okul-aile iş birliği) hakkında bilgi verilmesi',
            'Proje/performans görevleri teslim takvimi, sorumluluk bilinci ve akademik dürüstlük ilkelerinin paylaşılması',
            '6698 sayılı KVKK kapsamında veli iletişim ve etkinlik görseli açık rıza süreçlerinin hatırlatılması',
            'Dilek, temenniler ve bireysel veli değerlendirmeleriyle kapanış',
          ],
          defaultValue: [
            'Açılış, yoklama ve sınıfın genel akademik, sosyal ve gelişimsel durumunun paylaşılması',
            'MEB Kurum Yönetmeliği: devam-devamsızlık sınırları, özür belgesi teslim süreleri (5 iş günü), derse zamanında giriş ve kılık-kıyafet kuralları',
            'Yeni sınav sistemi: açık uçlu ortak yazılı sınavlar, konu-soru dağılım tabloları, uygulamalı sınavlar ve e-Okul takibi',
            'Evde verimli ders çalışma ortamının oluşturulması, düzenli uyku/kahvaltı alışkanlığı ve günlük kitap okuma rutini',
            'Dijital bağımlılıkla mücadele: akıllı telefon, oyun ve sosyal medya ekran sürelerinin ailece sınırlandırılması',
            'Dilek, temenniler ve bireysel veli değerlendirmeleriyle kapanış',
          ],
        ),
        const DocQuestionField(key: 'extraDecisions', label: 'Şubeye Özel Ek Kararlar / Notlar (Opsiyonel)', type: DocFieldType.multiline),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Şube / Toplantı', '${_list(a, "targetClasses").join(", ")} — ${_str(a, "termLabel")}'),
        MapEntry('Toplantı Tarihi / Saati', _str(a, 'date')),
        MapEntry('Sınıf Rehber Öğretmeni', _str(a, 'advisor', ctx.currentUser?.fullName ?? '-')),
      ],
      composeBody: (a, ctx) {
        final extra = _str(a, 'extraDecisions');
        return '''
SINIF VELİ TOPLANTISI TUTANAĞI VE VELİ KATILIM İMZA ÇİZELGESİ

${ctx.academicYear} Eğitim ve Öğretim Yılı ${ctx.schoolName} ${_list(a, 'targetClasses').join(', ')} şubesi "${_str(a, 'termLabel')}", ${_str(a, 'date')} tarihinde sınıf rehber öğretmeni yönetiminde öğrenci velilerimizin katılımıyla gerçekleştirilmiştir.

GÖRÜŞÜLEN GÜNDEM MADDELERİ VE ALINAN ORTAK KARARLAR:
${_numberedLines(_list(a, 'agenda'))}${extra.isNotEmpty ? '\n\nŞubeye Özel Ek Notlar ve Kararlar:\n$extra' : ''}

Toplantıya katılarak bilgilendirilen öğrenci velilerinin yoklama ve imza çizelgesi aşağıda yer almaktadır:''';
      },
      buildSigners: (a, ctx) => [
        DocSigner(name: _str(a, 'advisor', ctx.currentUser?.fullName ?? 'Sınıf Rehber Öğretmeni'), title: 'Sınıf Rehber Öğretmeni'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'UYGUNDUR'), isApproval: true),
      ],
    ),

    OfficialDocTemplate(
      id: 'bireysel_veli_gorusme_formu',
      code: '7.2',
      categoryId: 'ogretmen_sinif_veli',
      title: 'Bireysel Veli / Öğrenci Görüşme ve İş Birliği Tutanağı',
      subtitle: 'Yüz yüze, telefonla veya ev ziyareti kapsamında yapılan veli görüşmesinin resmi kayıt formu',
      audience: DocAudience.teacher,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.support_agent_rounded,
      questions: [
        const DocQuestionField(key: 'targetClass', label: 'Öğrencinin Şubesi', type: DocFieldType.classSelect, required: true),
        const DocQuestionField(key: 'student', label: 'Öğrenci Seçimi', type: DocFieldType.studentSelect, required: true),
        const DocQuestionField(key: 'parentName', label: 'Görüşülen Veli Adı Soyadı ve Yakınlığı', type: DocFieldType.text, hint: 'Örn: Ayşe Yılmaz (Annesi)'),
        const DocQuestionField(
          key: 'meetingType',
          label: 'Görüşme Türü',
          type: DocFieldType.dropdown,
          options: [
            'Okulda Yüz Yüze Görüşme (Veli Görüşme Saatinde)',
            'İdari / Rehberlik Davetli Yüz Yüze Görüşme',
            'Telefonla Bilgilendirme Görüşmesi',
            'Çevrimiçi (Online) Veli Görüşmesi',
            'Planlı Veli Ev Ziyareti Görüşmesi',
          ],
          defaultValue: 'Okulda Yüz Yüze Görüşme (Veli Görüşme Saatinde)',
        ),
        DocQuestionField(key: 'date', label: 'Görüşme Tarihi ve Saati', type: DocFieldType.text, defaultValue: '${_today()} - ${_nowTime()}'),
        const DocQuestionField(
          key: 'topics',
          label: 'Görüşmede Ele Alınan Konular ve Tespitler',
          type: DocFieldType.multiCheck,
          options: [
            'Öğrencinin ders içi odaklanması, sözlü katılımı ve akademik başarı grafiği değerlendirildi.',
            'Ortak yazılı sınav ve deneme sınavı kazanım analizleri veli ile ayrıntılı paylaşıldı.',
            'Verilen ödev, proje ve günlük konu tekrarı sorumluluklarının takibi ele alındı.',
            'Okula devam-devamsızlık durumu, derse zamanında giriş ve ders araç-gereç hazırlığı görüşüldü.',
            'Sınıf içi davranışları, akran iletişimi ve okul kurallarına uyumu değerlendirildi.',
            'Evdeki çalışma planı, uyku düzeni ve telefon/tablet/oyun ekran süresi yönetimi konuşuldu.',
            'Öğrencinin motivasyonunu artırmaya yönelik Okul Rehberlik Servisi iş birliği önerildi.',
            'Üst öğrenime hazırlık (LGS / YKS) hedef takibi, soru çözüm rutini ve eksik konu telafisi planlandı.',
            'Öğrencinin güçlü yönleri, sanatsal/sportif/bilimsel ilgi alanları ve özgüven gelişimi değerlendirildi.',
            'Sağlık, beslenme, kahvaltı alışkanlığı veya dikkat/odaklanma gözlemleri aile ile paylaşıldı.',
            'Daha önce yapılan sözlü uyarı / EK-9 öğrenci sözleşmesi kapsamındaki davranış gelişimi gözden geçirildi.',
          ],
          defaultValue: [
            'Öğrencinin ders içi odaklanması, sözlü katılımı ve akademik başarı grafiği değerlendirildi.',
            'Verilen ödev, proje ve günlük konu tekrarı sorumluluklarının takibi ele alındı.',
            'Evdeki çalışma planı, uyku düzeni ve telefon/tablet/oyun ekran süresi yönetimi konuşuldu.',
          ],
        ),
        const DocQuestionField(
          key: 'summary',
          label: 'Görüşme Özeti, Veli Beyanı ve Kararlaştırılan Eylem Adımları',
          type: DocFieldType.multiline,
          defaultValue: 'Öğrencimizin evde haftalık çalışma planının veli tarafından günlük kontrol edilmesine, eksik kazanımlar için etüt çalışmasına yönlendirilmesine ve 3 hafta sonra gelişim durumunun tekrar değerlendirilmesine karar verilmiştir.',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Görüşülen Veli', _str(a, 'parentName', 'Öğrenci Velisi')),
        MapEntry('Görüşme Türü / Tarihi', '${_str(a, "meetingType")} • ${_str(a, "date")}'),
        MapEntry('Görüşmeyi Yapan Öğretmen', ctx.currentUser?.fullName ?? '-'),
      ],
      composeBody: (a, ctx) => '''
BİREYSEL VELİ GÖRÜŞME VE İZLEME TUTANAĞI

1. GÖRÜŞÜLEN HUSUSLAR:
${_numberedLines(_list(a, 'topics'))}

2. VELİ GÖRÜŞÜ VE KARARLAŞTIRILAN İŞ BİRLİĞİ ADIMLARI:
${_str(a, 'summary')}

İşbu görüşme tutanağı okul-aile iş birliği kapsamında düzenlenerek imza altına alınmış ve sınıf rehberlik dosyasına eklenmiştir.''',
      buildSigners: (a, ctx) => [
        DocSigner(name: _str(a, 'parentName', 'Öğrenci Velisi'), title: 'Görüşülen Öğrenci Velisi'),
        DocSigner(name: ctx.currentUser?.fullName ?? 'Öğretmen', title: 'Görüşmeyi Yapan Öğretmen'),
      ],
    ),

    OfficialDocTemplate(
      id: 'ogretmen_sinif_ici_tespit_tutanagi',
      code: '7.3',
      categoryId: 'ogretmen_sinif_veli',
      title: 'Öğretmen Sınıf İçi Olay / Kopya / Demirbaş Hasar Tutanağı',
      subtitle: 'Ders düzenini bozma, sınavda kopya veya demirbaş hasarının idareye resmi bildirim tutanağı',
      audience: DocAudience.teacher,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.rule_folder_rounded,
      questions: [
        const DocQuestionField(key: 'targetClass', label: 'Şube Seçimi', type: DocFieldType.classSelect, required: true),
        const DocQuestionField(key: 'students', label: 'İlgili Öğrenci(ler)', type: DocFieldType.multiStudentSelect, required: true),
        DocQuestionField(key: 'date', label: 'Tarih ve Ders Saati', type: DocFieldType.text, defaultValue: '${_today()} - 3. Ders Saati'),
        const DocQuestionField(
          key: 'incidentKind',
          label: 'Tespit Türü',
          type: DocFieldType.dropdown,
          options: [
            'Ders İşleniş Düzenini ve Öğrenme Ortamını Israrla Bozma',
            'Yazılı / Deneme Sınavında Kopya Çekme veya Kopya Girişiminde Bulunma',
            'Okul / Sınıf Demirbaşına (Etkileşimli Tahta, Sıra, Kapı vb.) Zarar Verme',
            'Sınıf İçinde Akran Zorbalığı / Tartışma / Olumsuz İfade Kullanımı',
            'Ders Öğretmeninin İzni Olmadan Sınıfı Terk Etme',
          ],
          defaultValue: 'Ders İşleniş Düzenini ve Öğrenme Ortamını Israrla Bozma',
        ),
        const DocQuestionField(
          key: 'pedagogicalChecks',
          label: 'Yapılan Tespit ve Sınıf İçi İşlem Maddeleri',
          type: DocFieldType.multiCheck,
          options: [
            'Öğrenciye ders işlenişini bozmaması yönünde birden fazla kez uygun pedagojik dille sözlü uyarı yapıldı.',
            'Sınav esnasında sıra üzerinde / kıyafetinde tespit edilen kopya materyali sınav kağıdına eklenerek muhafaza altına alındı.',
            'Sınıf demirbaşında (sıra, masa, etkileşimli tahta, kapı) meydana gelen hasar yerinde tespit edildi.',
            'Sınıfın güvenliği ve ders akışının korunması amacıyla nöbetçi müdür yardımcısına bilgi verildi.',
            'Sınıf rehber öğretmeni ve Okul PDR Servisi ile paylaşılacak gözlem notu oluşturuldu.',
            'Olay anında sınıfta bulunan öğrenci tanık beyanları / oturma planı bilgisi not edildi.',
          ],
          defaultValue: [
            'Öğrenciye ders işlenişini bozmaması yönünde birden fazla kez uygun pedagojik dille sözlü uyarı yapıldı.',
            'Sınıfın güvenliği ve ders akışının korunması amacıyla nöbetçi müdür yardımcısına bilgi verildi.',
          ],
        ),
        const DocQuestionField(
          key: 'details',
          label: 'Olayın Ayrıntılı Açıklaması ve Yapılan Pedagojik Uyarılar',
          type: DocFieldType.multiline,
          defaultValue: 'Belirtilen ders saatinde yapılan pedagojik ve sözlü uyarılara rağmen ilgili davranışın devam ettiği/gerçekleştiği tespit edilmiş olup varsa kanıt niteliğindeki materyal muhafaza altına alınarak işbu tutanak düzenlenmiştir.',
          required: true,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Şube / Tarih-Ders', '${_str(a, "targetClass")} • ${_str(a, "date")}'),
        MapEntry('İlgili Öğrenci(ler)', _list(a, 'students').join(', ')),
        MapEntry('Tespit Konusu', _str(a, 'incidentKind')),
        MapEntry('Ders Öğretmeni', ctx.currentUser?.fullName ?? '-'),
      ],
      composeBody: (a, ctx) => '''
SINIF İÇİ ÖĞRETMEN TESPİT VE BİLDİRİM TUTANAĞI

${_str(a, 'date')} zaman diliminde ${_str(a, 'targetClass')} şubesinde yürütülen ders/sınav esnasında; ${_list(a, 'students').join(', ')} isimli öğrenci(ler) ile ilgili olarak "${_str(a, 'incidentKind')}" kapsamında aşağıdaki somut durum yaşanmıştır:

TESPİT DETAYI:
${_str(a, 'details')}

UYGULANAN SINIF İÇİ İŞLEM VE TESPİTLER:
${_numberedLines(_list(a, 'pedagogicalChecks'))}

İlgili yönetmelik hükümleri çerçevesinde değerlendirilerek gereğinin yapılması hususunda işbu tutanak mahallinde düzenlenerek Okul İdaresine teslim edilmiştir.''',
      buildSigners: (a, ctx) => [
        DocSigner(name: ctx.currentUser?.fullName ?? 'Ders Öğretmeni', title: 'Tutanak Düzenleyen Ders Öğretmeni'),
        DocSigner(name: ctx.vicePrincipals.isNotEmpty ? ctx.vicePrincipals.first.fullName : 'Müdür Yardımcısı', title: 'Teslim Alan Müdür Yardımcısı'),
      ],
    ),

    OfficialDocTemplate(
      id: 'sinif_baskanligi_secim_tutanagi',
      code: '7.4',
      categoryId: 'ogretmen_sinif_veli',
      title: 'Sınıf Başkanlığı ve Öğrenci Temsilcisi Demokratik Seçim Tutanağı',
      subtitle: 'Demokrasi Eğitimi Yönergesine uygun gizli oy - açık tasnif seçim ve oy dağılım tutanağı',
      audience: DocAudience.teacher,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.how_to_vote_rounded,
      questions: [
        const DocQuestionField(key: 'targetClass', label: 'Şube Seçimi', type: DocFieldType.classSelect, required: true),
        DocQuestionField(key: 'date', label: 'Seçim Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'voterCount', label: 'Sınıf Mevcudu / Oy Kullanan Öğrenci Sayısı', type: DocFieldType.text, defaultValue: '26 / 26 Geçerli Oy'),
        const DocQuestionField(key: 'president', label: 'Seçilen Sınıf Başkanı / Öğrenci Temsilcisi', type: DocFieldType.studentSelect, required: true),
        const DocQuestionField(key: 'vicePresident', label: 'Seçilen Sınıf Başkan Yardımcısı', type: DocFieldType.studentSelect),
        const DocQuestionField(key: 'ballotCommittee', label: 'Sandık ve Oy Sayım Kurulu Öğrencileri (Opsiyonel)', type: DocFieldType.text, hint: 'Örn: 2 gönüllü öğrenci gözetiminde sayım yapılmıştır'),
        const DocQuestionField(key: 'voteSummary', label: 'Aday Öğrenciler ve Aldıkları Oy Dağılımı', type: DocFieldType.multiline, hint: 'Örn: 1. Aday: 14 Oy, 2. Aday: 9 Oy, 3. Aday: 3 Oy'),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Şube / Seçim Tarihi', '${_str(a, "targetClass")} • ${_str(a, "date", _today())}'),
        MapEntry('Katılım ve Geçerli Oy', _str(a, 'voterCount')),
        MapEntry('Seçilen Sınıf Başkanı', _str(a, 'president')),
        MapEntry('Sınıf Başkan Yardımcısı', _str(a, 'vicePresident', '-')),
      ],
      composeBody: (a, ctx) {
        final vs = _str(a, 'voteSummary');
        final bc = _str(a, 'ballotCommittee');
        return '''
DEMOKRATİK SINIF BAŞKANLIĞI VE ŞUBE TEMSİLCİSİ SEÇİM TUTANAĞI

MEB Demokrasi Eğitimi ve Okul Meclisleri Yönergesi ilkeleri doğrultusunda ${ctx.academicYear} Eğitim ve Öğretim Yılında ${_str(a, 'targetClass')} şubesinde demokratik katılım ve seçme-seçilme bilincini geliştirmek amacıyla adayların kendilerini tanıtmalarının ardından gizli oy, açık tasnif usulüyle seçim gerçekleştirilmiştir.${bc.isNotEmpty ? '\nSandık / Sayım Gözetimi: $bc' : ''}

Yapılan açık oy sayımı sonucunda en yüksek oyu alan ${_str(a, 'president')} Sınıf Başkanı, ${_str(a, 'vicePresident', 'en çok oy alan ikinci aday')} ise Sınıf Başkan Yardımcısı olarak seçilmiştir.${vs.isNotEmpty ? '\n\nADAYLAR VE OY DAĞILIMI:\n$vs' : ''}''';
      },
      buildSigners: (a, ctx) => [
        DocSigner(name: _str(a, 'president', 'Sınıf Başkanı'), title: 'Seçilen Sınıf Başkanı'),
        DocSigner(name: ctx.currentUser?.fullName ?? 'Sınıf Rehber Öğretmeni', title: 'Sınıf Rehber Öğretmeni'),
      ],
    ),

    OfficialDocTemplate(
      id: 'sinif_rehberlik_yillik_calisma_tutanagi',
      code: '7.5',
      categoryId: 'ogretmen_sinif_veli',
      title: 'Sınıf Rehberlik Yıllık Çalışma, Uyum ve Risk İzleme Tutanağı',
      subtitle: 'Sınıf rehberlik programı hedefleri, oturma düzeni, öğrenci tanıma envanterleri ve izleme planı',
      audience: DocAudience.teacher,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.auto_graph_rounded,
      questions: [
        const DocQuestionField(key: 'targetClass', label: 'Şube Seçimi', type: DocFieldType.classSelect, required: true),
        DocQuestionField(key: 'date', label: 'Planlama / Değerlendirme Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'advisor', label: 'Sınıf Rehber Öğretmeni', type: DocFieldType.staffSelect),
        const DocQuestionField(
          key: 'plannedWorks',
          label: 'Yürütülecek Sınıf Rehberlik Çalışmaları',
          type: DocFieldType.multiCheck,
          options: [
            'MEB Sınıf Rehberlik Programı kazanımlarının (akademik, kariyer ve sosyal-duygusal gelişim) haftalık rehberlik saatlerinde işlenmesi',
            'Öğrenci Tanıma Formları, Otobiyografi ve Yaşam Pencerem / RİBA envanterlerinin Okul PDR Servisi eşgüdümünde uygulanması',
            'Görme/işitme durumu, boy-kilo ve pedagojik ihtiyaçlar gözetilerek sınıf oturma planının hazırlanması ve periyodik rotasyonu',
            'Sınıf başkanlığı, temizlik/kitaplık kolları ve akran dayanışma gruplarının oluşturulması',
            'Özel gereksinimli (BEP), nakil gelen veya devamsızlık/akademik düşüş riski taşıyan öğrencilerin yakından izlenmesi',
            'Aylık deneme sınavı ve ortak yazılı sonuçlarına göre bireysel hedef belirleme görüşmelerinin yapılması',
            'Akran zorbalığı, siber güvenlik ve dijital bağımlılığa karşı önleyici sınıf rehberlik oturumlarının uygulanması',
            'Olumsuz davranış gözlenen öğrencilerde sözlü uyarı, EK-9 öğrenci sözleşmesi ve veli iş birliği basamaklarının işletilmesi',
            'Her dönem en az bir genel veli toplantısı ve ihtiyaç duyulan velilerle bireysel görüşme tutanaklarının düzenlenmesi',
            'Sosyal kulüp, toplum hizmeti ve değerler eğitimi çalışmalarına tüm şube öğrencilerinin aktif katılımının desteklenmesi',
          ],
          defaultValue: [
            'MEB Sınıf Rehberlik Programı kazanımlarının (akademik, kariyer ve sosyal-duygusal gelişim) haftalık rehberlik saatlerinde işlenmesi',
            'Öğrenci Tanıma Formları, Otobiyografi ve Yaşam Pencerem / RİBA envanterlerinin Okul PDR Servisi eşgüdümünde uygulanması',
            'Görme/işitme durumu, boy-kilo ve pedagojik ihtiyaçlar gözetilerek sınıf oturma planının hazırlanması ve periyodik rotasyonu',
            'Özel gereksinimli (BEP), nakil gelen veya devamsızlık/akademik düşüş riski taşıyan öğrencilerin yakından izlenmesi',
          ],
        ),
        const DocQuestionField(key: 'classProfileNote', label: 'Şubenin Genel Profili ve Özel Gözlem Notu (Opsiyonel)', type: DocFieldType.multiline),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Şube / Eğitim Yılı', '${_str(a, "targetClass")} — ${ctx.academicYear}'),
        MapEntry('Sınıf Rehber Öğretmeni', _str(a, 'advisor', ctx.currentUser?.fullName ?? '-')),
        MapEntry('Tarih', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) {
        final note = _str(a, 'classProfileNote');
        return '''
SINIF REHBERLİK YILLIK ÇALIŞMA VE ÖĞRENCİ İZLEME TUTANAĞI

MEB Rehberlik ve Psikolojik Danışma Hizmetleri Yönetmeliği çerçevesinde ${ctx.academicYear} Eğitim ve Öğretim Yılında ${_str(a, 'targetClass')} şubesinde yürütülecek sınıf rehberlik hizmetleri aşağıda planlandığı şekilde uygulanacaktır:

PLANLANAN ÇALIŞMALAR:
${_numberedLines(_list(a, 'plannedWorks'))}${note.isNotEmpty ? '\n\nŞUBE GENEL PROFİL DEĞERLENDİRMESİ:\n$note' : ''}''';
      },
      buildSigners: (a, ctx) => [
        DocSigner(name: _str(a, 'advisor', ctx.currentUser?.fullName ?? 'Sınıf Rehber Öğretmeni'), title: 'Sınıf Rehber Öğretmeni'),
        DocSigner(
          name: ctx.counselors.isNotEmpty ? ctx.counselors.first.fullName : 'Rehber Öğretmen / Psikolojik Danışman',
          title: 'Koordinatör Psikolojik Danışman',
        ),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'UYGUNDUR'), isApproval: true),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // BAŞLIK 8: NÖBET, KULÜP VE REHBERLİK YÖNLENDİRME EVRAKLARI (ÖĞRETMEN)
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'nobetci_ogretmen_vukuat_tutanagi',
      code: '8.1',
      categoryId: 'ogretmen_nobet_kulup_rehberlik',
      title: 'Nöbetçi Öğretmen Günlük Kontrol, Vukuat ve Kapanış Tutanağı',
      subtitle: 'Nöbet bölgesinde gün içi güvenlik/temizlik kontrolleri veya yaşanan vukuatın idareye devir formu',
      audience: DocAudience.teacher,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.shield_outlined,
      questions: [
        DocQuestionField(key: 'date', label: 'Nöbet Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(
          key: 'dutyArea',
          label: 'Nöbet Bölgesi / Katı',
          type: DocFieldType.dropdown,
          options: [
            'Zemin Kat ve Ana Giriş Koridoru',
            '1. Kat Derslikler Koridoru',
            '2. Kat Derslikler Koridoru',
            '3. Kat Derslikler Koridoru',
            'Ön ve Arka Okul Bahçesi / Servis Alanı',
            'Yemekhane, Kantin ve Çok Amaçlı Salon Bölgesi',
            'Spor Salonu ve Laboratuvarlar Katı',
          ],
          defaultValue: '1. Kat Derslikler Koridoru',
        ),
        const DocQuestionField(
          key: 'status',
          label: 'Gün Sonu Genel Durum',
          type: DocFieldType.dropdown,
          options: [
            'Normal — Eğitim-öğretim günü güvenli ve sorunsuz tamamlanmıştır',
            'Arıza / Fiziki Eksiklik Bildirimi Mevcut',
            'Vukuatlı — Öğrenci Kaza / Disiplin / İdari İşlem Gerektiren Durum Mevcut',
          ],
          defaultValue: 'Normal — Eğitim-öğretim günü güvenli ve sorunsuz tamamlanmıştır',
        ),
        const DocQuestionField(
          key: 'checkedControls',
          label: 'Tamamlanan Günlük Nöbet Kontrolleri',
          type: DocFieldType.multiCheck,
          options: [
            'İlk ders öncesi kat/bölge fiziki güvenlik, aydınlatma, ısınma ve ıslak zemin kontrolü yapıldı.',
            'Teneffüslerde koridor, merdiven ve lavabo önlerinde öğrenci güvenliği gözetildi.',
            'Öğretmenleri izinli/raporlu sınıfların durumu nöbetçi idare ile koordine edildi.',
            'Son ders çıkışında sınıfların boşaltılması, pencerelerin/etkileşimli tahtaların kapatılması ve servis düzeni kontrol edildi.',
            'Sabah ve akşam törenlerinde öğrencilerin sıra düzeni ve sınıflara güvenli giriş-çıkışı sağlandı.',
            'Kantin ve yemekhane geçişlerinde izdiham yaşanmaması için sıra ve hijyen gözlemi yapıldı.',
            'Yangın tüpleri, acil çıkış kapıları ve elektrik panolarının önünün açık olduğu kontrol edildi.',
            'Okul bina ve bahçesine yabancı/izinsiz kişi girişinin önlenmesi amacıyla danışma/güvenlikle eşgüdüm sağlandı.',
            'Özel gereksinimli öğrencilerin teneffüs ve merdiven iniş-çıkış güvenliği yakından takip edildi.',
          ],
          defaultValue: [
            'İlk ders öncesi kat/bölge fiziki güvenlik, aydınlatma, ısınma ve ıslak zemin kontrolü yapıldı.',
            'Teneffüslerde koridor, merdiven ve lavabo önlerinde öğrenci güvenliği gözetildi.',
            'Son ders çıkışında sınıfların boşaltılması, pencerelerin/etkileşimli tahtaların kapatılması ve servis düzeni kontrol edildi.',
          ],
        ),
        const DocQuestionField(
          key: 'notes',
          label: 'Gün İçi Özel Gözlem / Vukuat / Arıza Açıklaması',
          type: DocFieldType.multiline,
          defaultValue: 'Nöbet süresince herhangi bir olumsuz vakıa yaşanmamış olup nöbet bölgesi güvenli şekilde devredilmiştir.',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Nöbet Tarihi', _str(a, 'date', _today())),
        MapEntry('Nöbet Bölgesi', _str(a, 'dutyArea')),
        MapEntry('Nöbetçi Öğretmen', ctx.currentUser?.fullName ?? '-'),
        MapEntry('Gün Sonu Durumu', _str(a, 'status')),
      ],
      composeBody: (a, ctx) => '''
GÜNLÜK NÖBET KONTROL, VUKUAT VE KAPANIŞ TUTANAĞI

1. TAMAMLANAN KONTROLLER:
${_numberedLines(_list(a, 'checkedControls'))}

2. VUKUAT / ARIZA / GÖZLEM NOTU:
${_str(a, 'notes')}

Yukarıda belirtilen nöbet bölgesine ait günlük gözetim tamamlanarak nöbetçi müdür yardımcısına bilgi verilmiştir.''',
      buildSigners: (a, ctx) => [
        DocSigner(name: ctx.currentUser?.fullName ?? 'Nöbetçi Öğretmen', title: 'Nöbetçi Öğretmen'),
        DocSigner(
          name: ctx.vicePrincipals.isNotEmpty ? ctx.vicePrincipals.first.fullName : 'Nöbetçi Müdür Yardımcısı',
          title: 'Nöbetçi Müdür Yardımcısı',
        ),
      ],
    ),

    OfficialDocTemplate(
      id: 'ogrenci_kulubu_dosya_tutanagi',
      code: '8.2',
      categoryId: 'ogretmen_nobet_kulup_rehberlik',
      title: 'Öğrenci Kulübü Genel Kurul, Seçim ve Yıllık Çalışma Tutanağı',
      subtitle: 'MEB Sosyal Etkinlikler Yönetmeliğine uygun kulüp yönetim/denetim seçimi ve yıllık çalışma kararları',
      audience: DocAudience.teacher,
      layoutKind: DocLayoutKind.meetingMinutes,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.diversity_3_rounded,
      questions: [
        const DocQuestionField(
          key: 'clubName',
          label: 'Öğrenci Kulübü Adı (MEB Sosyal Etkinlikler Listesi)',
          type: DocFieldType.dropdown,
          options: [
            'Kültür ve Edebiyat Kulübü',
            'Bilim, Fen ve Teknoloji Kulübü',
            'Bilişim, Robotik ve İnternet Kulübü',
            'Çevre Koruma, İklim ve Sıfır Atık Kulübü',
            'Sivil Savunma ve Afetlere Hazırlık Kulübü',
            'Kızılay ve Kan Bağışı / Yardımlaşma Kulübü',
            'Yeşilay ve Bağımlılıkla Mücadele Kulübü',
            'Spor, Geleneksel Çocuk Oyunları ve Satranç Kulübü',
            'Görsel Sanatlar, Müzik ve Tiyatro Kulübü',
            'Kütüphanecilik Kulübü',
            'Demokrasi, İnsan Hakları ve Yurttaşlık Kulübü',
            'Gezi, Tanıtma ve Turizm Kulübü',
            'Trafik Güvenliği ve İlk Yardım Kulübü',
            'Hayvanları Koruma Kulübü',
            'Değerler Eğitimi ve Sosyal Yardımlaşma Kulübü',
          ],
          defaultValue: 'Bilim, Fen ve Teknoloji Kulübü',
        ),
        DocQuestionField(key: 'date', label: 'Genel Kurul Toplantı Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'advisors', label: 'Kulüp Danışman Öğretmen(ler)i', type: DocFieldType.multiStaffSelect),
        const DocQuestionField(
          key: 'boardInfo',
          label: 'Seçilen Kulüp Öğrenci Yönetim ve Denetim Kurulu',
          type: DocFieldType.multiline,
          defaultValue: 'Yönetim Kurulu Başkanı: ..............................\nBaşkan Yardımcısı: ..............................\nYazman / Sayman Üye: ..............................\nDenetim Kurulu Başkanı: ..............................',
        ),
        const DocQuestionField(
          key: 'goals',
          label: 'Kararlaştırılan Yıllık Kulüp Çalışma ve Toplum Hizmeti Hedefleri',
          type: DocFieldType.multiCheck,
          options: [
            'Kulüp iç tüzüğünün ve yıllık çalışma/toplum hizmeti planının yönetim kurulunca hazırlanarak Okul Müdürlüğü onayına sunulması.',
            'Kulüp tanıtım ve farkındalık panosunun oluşturulması; belirli gün ve haftalara uygun olarak aylık güncellenmesi.',
            'Kulübün amacıyla ilişkili en az bir okul içi seminer, sergi, münazara, turnuva veya atölye etkinliğinin düzenlenmesi.',
            'MEB Sosyal Etkinlikler Yönetmeliği kapsamında her dönemde en az bir Toplum Hizmeti / Sosyal Sorumluluk projesinin hayata geçirilmesi.',
            'Yapılan tüm kulüp ve toplum hizmeti faaliyetlerinin öğrenci e-Portfolyo (e-Okul Sosyal Etkinlik Modülü) kayıtlarına zamanında işlenmesi.',
            'Yıl sonunda Kulüp Faaliyet Raporunun hazırlanarak Sosyal Etkinlikler Kuruluna teslim edilmesi.',
          ],
          defaultValue: [
            'Kulüp iç tüzüğünün ve yıllık çalışma/toplum hizmeti planının yönetim kurulunca hazırlanarak Okul Müdürlüğü onayına sunulması.',
            'Kulüp tanıtım ve farkındalık panosunun oluşturulması; belirli gün ve haftalara uygun olarak aylık güncellenmesi.',
            'MEB Sosyal Etkinlikler Yönetmeliği kapsamında her dönemde en az bir Toplum Hizmeti / Sosyal Sorumluluk projesinin hayata geçirilmesi.',
            'Yapılan tüm kulüp ve toplum hizmeti faaliyetlerinin öğrenci e-Portfolyo (e-Okul Sosyal Etkinlik Modülü) kayıtlarına zamanında işlenmesi.',
          ],
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Öğrenci Kulübü', _str(a, 'clubName')),
        MapEntry('Eğitim-Öğretim Yılı', ctx.academicYear),
        MapEntry('Toplantı Tarihi', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
MEB Eğitim Kurumları Sosyal Etkinlikler Yönetmeliği hükümleri uyarınca; ${ctx.academicYear} Eğitim ve Öğretim Yılı ${ctx.schoolName} "${_str(a, 'clubName')}" Genel Kurulu ${_str(a, 'date', _today())} tarihinde danışman öğretmen(ler) rehberliğinde üye öğrencilerin katılımıyla toplanmış, demokratik seçimle yönetim ve denetim organlarını oluşturmuş ve yıllık çalışma ilkelerini kararlaştırmıştır:

SEÇİLEN ÖĞRENCİ YÖNETİM VE DENETİM KURULU:
${_str(a, 'boardInfo')}

YILLIK ÇALIŞMA VE TOPLUM HİZMETİ KARARLARI:
${_numberedLines(_list(a, 'goals'))}''',
      buildSigners: (a, ctx) {
        final adv = _list(a, 'advisors');
        return [
          if (adv.isEmpty)
            DocSigner(name: ctx.currentUser?.fullName ?? 'Danışman Öğretmen', title: 'Kulüp Danışman Öğretmeni')
          else
            for (final s in adv) DocSigner(name: s, title: 'Kulüp Danışman Öğretmeni'),
          DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'UYGUNDUR'), isApproval: true),
        ];
      },
    ),

    OfficialDocTemplate(
      id: 'rehberlik_gozlem_yonlendirme_formu',
      code: '8.3',
      categoryId: 'ogretmen_nobet_kulup_rehberlik',
      title: 'Rehberlik Servisi Öğrenci Gözlem ve Yönlendirme Formu (GİZLİ)',
      subtitle: 'Sınıf içi gözlemlere dayalı olarak öğrencinin Okul PDR Servisine gizli yönlendirme formu',
      audience: DocAudience.teacher,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.psychology_rounded,
      questions: [
        const DocQuestionField(key: 'targetClass', label: 'Öğrencinin Şubesi', type: DocFieldType.classSelect, required: true),
        const DocQuestionField(key: 'student', label: 'Yönlendirilen Öğrenci', type: DocFieldType.studentSelect, required: true),
        DocQuestionField(key: 'date', label: 'Yönlendirme Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(
          key: 'observations',
          label: 'Gözlemlenen Durum / Gelişimsel ve Eğitsel Belirtiler',
          type: DocFieldType.multiCheck,
          options: [
            'Son dönemde belirgin akademik başarı, ders katılımı ve motivasyon düşüşü',
            'Ders içi yoğun dikkat dağınıklığı, odaklanma güçlüğü veya aşırı hareketlilik',
            'İçe kapanıklık, mutsuzluk, duygusal hassasiyet veya akranlarından sosyal izolasyon',
            'Yoğun sınav kaygısı, mükemmeliyetçilik veya fiziksel stres belirtileri',
            'Akran iletişiminde çatışma, öfke kontrol güçlüğü veya dürtüsel tepkiler',
            'Okula uyum güçlüğü, sık devamsızlık veya derse geç kalma eğilimi',
            'Ailevi değişim / yas / travmatik yaşantı kaynaklı duygusal etkilenme şüphesi',
            'Özel yetenek veya öğrenme güçlüğü açısından eğitsel değerlendirme ihtiyacı',
            'Yoğun ekran/oyun kullanımı kaynaklı uykusuzluk, yorgunluk ve dersten kopma belirtileri',
            'Akran zorbalığına maruz kalma veya siber zorbalık etkilenimi şüphesi',
            'Öz bakım, beslenme veya fiziksel görünümde ani ve dikkat çekici ihmal belirtileri',
            'Sözlü uyarı ve EK-9 davranış sözleşmesi sürecinde profesyonel psikolojik danışma desteği ihtiyacı',
          ],
          defaultValue: ['Son dönemde belirgin akademik başarı, ders katılımı ve motivasyon düşüşü'],
        ),
        const DocQuestionField(
          key: 'priorSteps',
          label: 'Öğretmen Tarafından Sınıf İçinde Yapılan Ön Gözlem ve Destek Çalışmaları',
          type: DocFieldType.multiline,
          defaultValue: 'Öğrenci ile yargılayıcı olmayan bireysel destek görüşmesi yapılmış, sınıf içi olumlu sorumluluk verilmiş olup profesyonel psikolojik danışma desteğiyle sürecin güçlendirilmesi uygun görülmüştür.',
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Gizlilik Derecesi', 'GİZLİ — OKUL REHBERLİK VE PSİKOLOJİK DANIŞMA SERVİSİNE'),
        MapEntry('Öğrenci / Şube', '${_str(a, "student")} (${_str(a, "targetClass")})'),
        MapEntry('Yönlendirme Tarihi', _str(a, 'date', _today())),
        MapEntry('Yönlendiren Öğretmen', ctx.currentUser?.fullName ?? '-'),
      ],
      composeBody: (a, ctx) => '''
1. SINIF VE OKUL ORTAMINDA GÖZLEMLENEN BELİRTİLER:
${_numberedLines(_list(a, 'observations'))}

2. ÖĞRETMENİN ÖN ÇALIŞMALARI VE GÖZLEM NOTU:
${_str(a, 'priorSteps')}

Öğrencimizin MEB Rehberlik ve Psikolojik Danışma Hizmetleri Yönetmeliği gizlilik ve gönüllülük ilkeleri çerçevesinde değerlendirilerek desteklenmesi hususunda Okul PDR Servisinin bilgilerine sunulur.''',
      buildSigners: (a, ctx) => [
        DocSigner(name: ctx.currentUser?.fullName ?? 'Öğretmen', title: 'Yönlendiren Öğretmen'),
        DocSigner(
          name: ctx.counselors.isNotEmpty ? ctx.counselors.first.fullName : 'Rehber Öğretmen / Psikolojik Danışman',
          title: 'Teslim Alan Psikolojik Danışman',
        ),
      ],
    ),

    OfficialDocTemplate(
      id: 'kulup_toplum_hizmeti_faaliyet_raporu',
      code: '8.4',
      categoryId: 'ogretmen_nobet_kulup_rehberlik',
      title: 'Öğrenci Kulübü ve Toplum Hizmeti Dönem / Yıl Sonu Faaliyet Raporu',
      subtitle: 'Gerçekleştirilen kulüp etkinlikleri, katılımcı öğrenci sayısı, kazanımlar ve sonuç raporu',
      audience: DocAudience.teacher,
      layoutKind: DocLayoutKind.incidentForm,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.volunteer_activism_rounded,
      questions: [
        const DocQuestionField(key: 'clubName', label: 'Öğrenci Kulübü / Toplum Hizmeti Grubu Adı', type: DocFieldType.text, defaultValue: 'Çevre Koruma ve Sıfır Atık Kulübü', required: true),
        const DocQuestionField(
          key: 'reportPeriod',
          label: 'Rapor Dönemi',
          type: DocFieldType.dropdown,
          options: ['1. Dönem Sonu Faaliyet Raporu', '2. Dönem / Yıl Sonu Genel Faaliyet Raporu', 'Belirli Gün / Proje Sonuç Raporu'],
          defaultValue: '2. Dönem / Yıl Sonu Genel Faaliyet Raporu',
        ),
        DocQuestionField(key: 'date', label: 'Rapor Tarihi', type: DocFieldType.date, defaultValue: _today()),
        const DocQuestionField(key: 'studentCount', label: 'Görev Alan Öğrenci Sayısı ve Toplam Etkinlik Saati', type: DocFieldType.text, defaultValue: '24 Öğrenci — 15 Saat Toplum Hizmeti'),
        const DocQuestionField(
          key: 'completedActivities',
          label: 'Gerçekleştirilen Etkinlikler ve Toplum Hizmeti Çalışmaları',
          type: DocFieldType.multiline,
          defaultValue: '1. Yıllık çalışma planında yer alan farkındalık panoları ve sınıf bilgilendirme sunumları tamamlanmıştır.\n2. Okul genelinde geri dönüşüm / kitap-materyal paylaşım / çevre duyarlılığı kampanyası yürütülmüştür.\n3. Katılımcı öğrencilerin sosyal etkinlik bilgileri e-Okul Sosyal Etkinlik Modülüne işlenmiştir.',
          required: true,
        ),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Kulüp / Çalışma Grubu', _str(a, 'clubName')),
        MapEntry('Rapor Dönemi', '${ctx.academicYear} — ${_str(a, "reportPeriod")}'),
        MapEntry('Katılımcı / Süre', _str(a, 'studentCount')),
        MapEntry('Rapor Tarihi', _str(a, 'date', _today())),
      ],
      composeBody: (a, ctx) => '''
SOSYAL ETKİNLİK VE TOPLUM HİZMETİ FAALİYET DEĞERLENDİRME RAPORU

GERÇEKLEŞTİRİLEN FAALİYETLER VE ÇIKTILAR:
${_str(a, 'completedActivities')}

SONUÇ VE DEĞERLENDİRME:
Planlanan kulüp ve toplum hizmeti çalışmaları öğrencilerin sosyal sorumluluk, iş birliği ve özgüven becerilerine olumlu katkı sağlamış olup hedef takvimine uygun biçimde tamamlanmıştır. Sosyal Etkinlikler Kurulu ve Okul Müdürlüğüne arz olunur.''',
      buildSigners: (a, ctx) => [
        DocSigner(name: ctx.currentUser?.fullName ?? 'Danışman Öğretmen', title: 'Kulüp Danışman Öğretmeni'),
        DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'İNCELENDİ / UYGUNDUR'), isApproval: true),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // BAŞLIK 9: DİNAMİK LİSTE, SINAV SALON YOKLAMASI VE KART ÜRETİCİ (ORTAK)
    // ─────────────────────────────────────────────────────────────────────────
    OfficialDocTemplate(
      id: 'dinamik_pdf_kontrol_imza_cizelgesi',
      code: '9.1',
      categoryId: 'ortak_liste_kart',
      title: 'Dinamik PDF Kontrol, Yoklama ve İmza Çizelgesi',
      subtitle: 'Seçilen şubeler veya öğretmenler için özel sütunlu A4 kontrol / yoklama / imza tablosu',
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.dynamicChecklist,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.table_chart_rounded,
      questions: [
        const DocQuestionField(
          key: 'listTarget',
          label: 'Liste Hedef Kitlesi',
          type: DocFieldType.dropdown,
          options: ['Öğrenci Listesi (Şube Bazlı)', 'Öğretmen ve Personel Listesi'],
          defaultValue: 'Öğrenci Listesi (Şube Bazlı)',
        ),
        const DocQuestionField(
          key: 'targetClasses',
          label: 'Şube Seçimi (Öğrenci Listesi ise)',
          type: DocFieldType.multiClassSelect,
        ),
        const DocQuestionField(
          key: 'chartTitle',
          label: 'Çizelge Başlığı',
          type: DocFieldType.text,
          defaultValue: 'SINIF ÖDEV / MATERYAL TAKİP VE İMZA ÇİZELGESİ',
          required: true,
        ),
        const DocQuestionField(
          key: 'customColumns',
          label: 'Tablo Sütun Başlıkları (Virgülle Ayırın)',
          type: DocFieldType.text,
          defaultValue: '1. Hafta, 2. Hafta, 3. Hafta, 4. Hafta, İmza / Açıklama',
          helperText: 'No ve Ad Soyad sütunları otomatik eklenir; yanına istediğiniz sütunları yazın',
        ),
        const DocQuestionField(
          key: 'orientation',
          label: 'Sayfa Yönü',
          type: DocFieldType.dropdown,
          options: ['Dikey A4', 'Yatay A4 (Çok Sütunlu Tablolar İçin)'],
          defaultValue: 'Dikey A4',
        ),
      ],
      composeBody: (a, ctx) =>
          '${ctx.schoolName} — ${_str(a, "chartTitle", "KONTROL ÇİZELGESİ")} (${ctx.academicYear})',
    ),

    OfficialDocTemplate(
      id: 'qr_yaka_karti_ve_etiket_uretici',
      code: '9.2',
      categoryId: 'ortak_liste_kart',
      title: 'QR Yaka Kartı, Sınıf Kapı Listesi ve Etiket Üretici',
      subtitle: 'Öğrenciler için kesim çizgili QR kodlu yaka kartı, sıra/dolap etiketi veya şık kapı listesi',
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.badgeGrid,
      defaultHeaderStyle: DocHeaderStyle.corporateLogo,
      icon: Icons.qr_code_2_rounded,
      questions: [
        const DocQuestionField(key: 'targetClasses', label: 'Şube Seçimi', type: DocFieldType.multiClassSelect, required: true),
        const DocQuestionField(
          key: 'badgeType',
          label: 'Üretilecek Şablon Türü',
          type: DocFieldType.dropdown,
          options: [
            'QR Kodlu Öğrenci Yaka / Kimlik Kartı (A4\'te 8 Kart)',
            'Öğrenci Dolap / Sıra İsim Etiketi (A4\'te 10 Etiket)',
            'Şık Sınıf Kapı Öğrenci Listesi (A4 Tam Sayfa)',
          ],
          defaultValue: 'QR Kodlu Öğrenci Yaka / Kimlik Kartı (A4\'te 8 Kart)',
        ),
        const DocQuestionField(
          key: 'badgeSubLabel',
          label: 'Kart Alt Başlığı / Etkinlik Adı',
          type: DocFieldType.text,
          defaultValue: 'Öğrenci Tanıtım Kartı',
        ),
        const DocQuestionField(
          key: 'showQr',
          label: 'Kartlarda Öğrenci QR Kodu Bulunsun mu?',
          type: DocFieldType.yesNo,
          defaultValue: true,
        ),
      ],
      composeBody: (a, ctx) =>
          '${ctx.schoolName} — ${_str(a, "badgeType")} (${_list(a, "targetClasses").join(", ")})',
    ),

    OfficialDocTemplate(
      id: 'sinav_salonu_uygulama_yoklama_tutanagi',
      code: '9.3',
      categoryId: 'ortak_liste_kart',
      title: 'Ortak Yazılı / Deneme Sınavı Salon Yoklama ve Uygulama Tutanağı',
      subtitle: 'Gözetmen tutanağı, sınav kuralları ve seçilen şube öğrencileri için kitapçık/katılım/imza listesi',
      audience: DocAudience.common,
      layoutKind: DocLayoutKind.circularSignatureTable,
      defaultHeaderStyle: DocHeaderStyle.mebOfficial,
      icon: Icons.fact_check_rounded,
      questions: [
        const DocQuestionField(key: 'targetClasses', label: 'Sınava Giren Şube / Salon', type: DocFieldType.multiClassSelect, required: true),
        const DocQuestionField(key: 'examName', label: 'Sınav Adı / Ders', type: DocFieldType.text, defaultValue: '1. Dönem Ortak Yazılı / Kurumsal Deneme Sınavı', required: true),
        DocQuestionField(key: 'date', label: 'Sınav Tarihi ve Başlama-Bitiş Saati', type: DocFieldType.text, defaultValue: '${_today()} (09:30 - 10:50)'),
        const DocQuestionField(key: 'proctor1', label: 'Salon Başkanı / 1. Gözetmen Öğretmen', type: DocFieldType.staffSelect),
        const DocQuestionField(key: 'proctor2', label: '2. Gözetmen Öğretmen (Varsa)', type: DocFieldType.staffSelect),
        const DocQuestionField(key: 'hallNote', label: 'Salon Uygulama Notu / Sınava Girmeyen Öğrenciler (Opsiyonel)', type: DocFieldType.text, defaultValue: 'Sınav kuralları okunmuş, sınav evrakları eksiksiz dağıtılıp toplanmıştır.'),
      ],
      buildMetaRows: (a, ctx) => [
        MapEntry('Sınav Adı', _str(a, 'examName')),
        MapEntry('Şube / Salon', _list(a, 'targetClasses').join(', ')),
        MapEntry('Tarih ve Saat', _str(a, 'date')),
        MapEntry('Salon Gözetmen(ler)i', [_str(a, 'proctor1'), _str(a, 'proctor2')].where((e) => e.isNotEmpty).join(' — ')),
      ],
      composeBody: (a, ctx) => '''
SINAV SALONU UYGULAMA TUTANAĞI VE ÖĞRENCİ İMZA LİSTESİ

Yukarıda bilgileri belirtilen sınavda kimlik ve salon düzeni kontrol edilmiş, cep telefonu/akıllı cihaz uyarısı yapılmış; sınav süresince ${_str(a, 'hallNote')}
Sınava katılan öğrencilerin kitapçık/grup ve imza yoklama çizelgesi aşağıdadır:''',
      buildSigners: (a, ctx) {
        final p1 = _str(a, 'proctor1', ctx.currentUser?.fullName ?? 'Salon Başkanı');
        final p2 = _str(a, 'proctor2');
        return [
          DocSigner(name: p1, title: 'Salon Başkanı / Gözetmen'),
          if (p2.isNotEmpty) DocSigner(name: p2, title: 'Gözetmen Öğretmen'),
          DocSigner(name: ctx.principalName, title: _authorityTitle(ctx, 'TESLİM ALINDI'), isApproval: true),
        ];
      },
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // YÖNETMELİK ÖZEL, ÖDDK SÜRECİ VE ÇAPRAZ MEB ŞABLONLARI
    // ─────────────────────────────────────────────────────────────────────────
    ...OfficialDocumentCatalogOddkDisiplin.templates,
    ...OfficialDocumentCatalogIlkogretim.crossCategoryTemplates,
    ...OfficialDocumentCatalogIlkogretim.templates,
    ...OfficialDocumentCatalogOrtaogretim.templates,
    ...OfficialDocumentCatalogOzelKurs.templates,
  ];
}
