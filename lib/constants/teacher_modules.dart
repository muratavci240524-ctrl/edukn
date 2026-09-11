import 'package:flutter/material.dart';

/// Öğretmen arayüzü modül ve alt modül tanımları
class TeacherModuleInfo {
  final String key;
  final String name;
  final IconData icon;
  final Color color;
  final String description;
  final Map<String, String> subModules;

  const TeacherModuleInfo({
    required this.key,
    required this.name,
    required this.icon,
    required this.color,
    required this.description,
    required this.subModules,
  });
}

class TeacherModules {
  static final Map<String, TeacherModuleInfo> modules = {
    // 1. EĞİTİM İŞLEMLERİ
    'egitim_islemleri': const TeacherModuleInfo(
      key: 'egitim_islemleri',
      name: 'Eğitim İşlemleri',
      icon: Icons.school,
      color: Colors.orange,
      description: 'Ders programı, öğrenci listesi, yoklama, ödev ve sınav raporları',
      subModules: {
        'ders_programi': 'Ders Programı',
        'tanimli_ogrencilerim': 'Tanımlı Öğrencilerim',
        'ders_isleyis_plani': 'Ders İşleyiş Planı',
        'yoklama_istatistikleri': 'Yoklama İstatistikleri / Girişi',
        'odev_istatistikleri': 'Ödev İstatistikleri / Takibi',
        'etut_islemleri': 'Etüt İşlemleri',
        'anket_islemleri': 'Anket İşlemleri',
        'sinav_raporlari': 'Sınav Raporları (Tüm Modül)',
        'sinav_tekil_liste': '├─ Tekil Sınav: Sonuç Listesi & Sıralamalar',
        'sinav_tekil_karne': '├─ Tekil Sınav: Öğrenci Sınav Karnesi',
        'sinav_tekil_ortalama': '├─ Tekil Sınav: Ders & Puan Ortalamaları',
        'sinav_tekil_basari_belgesi': '├─ Tekil Sınav: Başarı Belgeleri',
        'sinav_tekil_kazanim': '├─ Tekil Sınav: Kazanım Analizleri',
        'sinav_tekil_soru': '├─ Tekil Sınav: Soru / Madde Analizleri',
        'sinav_birlestirilmis_raporlar': '├─ Birleştirilmiş Sınav Raporları',
        'sinav_guclendirme_programlari': '├─ Güçlendirme Programları',
        'sinav_agm': '├─ AGM (Akademik Güçlendirme)',
        'sinav_aksiyon_plani': '├─ Aksiyon Planları',
        'sinav_kamp_programi': '├─ Kamp Programı',
        'sinav_veli_raporu': '└─ Veli Bilgilendirme Raporu',
      },
    ),

    // 2. REHBERLİK İŞLEMLERİ
    'rehberlik_islemleri': const TeacherModuleInfo(
      key: 'rehberlik_islemleri',
      name: 'Rehberlik İşlemleri',
      icon: Icons.folder_special,
      color: Colors.deepPurple,
      description: 'Portfolyo, görüşmeler, etkinlikler ve gelişim raporları',
      subModules: {
        'ogrenci_portfolyolari': 'Öğrenci Portfolyoları (Tüm Modül)',
        'portfolyo_genel_bilgiler': '├─ Genel Bilgiler',
        'portfolyo_deneme_sinavlari': '├─ Deneme Sınavları',
        'portfolyo_yazili_sinavlar': '├─ Yazılı Sınavlar',
        'portfolyo_odevler': '├─ Ödevler',
        'portfolyo_devamsizlik': '├─ Devamsızlık',
        'portfolyo_eylem_planlari': '├─ Eylem Planları',
        'portfolyo_etutler': '├─ Etütler',
        'portfolyo_kitaplar': '├─ Kitaplar',
        'portfolyo_gorusmeler': '├─ Görüşmeler',
        'portfolyo_talepler': '├─ Talepler',
        'portfolyo_gelisim_raporu': '├─ Gelişim Raporu',
        'portfolyo_mentor_calismalari': '├─ Mentör Çalışmaları',
        'portfolyo_rehberlik_testleri': '├─ Rehberlik Testleri',
        'portfolyo_etkinlik_raporlari': '└─ Etkinlik Raporları',
        'gorusmeler': 'Görüşmeler',
        'gozlem_ve_etkinlik': 'Gözlem ve Etkinlik İşlemleri (Tüm Modül)',
        'gozlem_etkinlik_goruntule': '├─ Formları Görüntüle',
        'gozlem_etkinlik_form_doldur': '├─ Form Doldurma / Değerlendirme',
        'gozlem_etkinlik_yeni_form': '└─ Yeni Form Açma / Düzenleme',
        'ders_calisma_programi': 'Ders Çalışma Programı',
        'rehberlik_envanterleri': 'Rehberlik Envanterleri',
        'rehberlik_kutuphanesi': 'Rehberlik Kütüphanesi',
        'gelisim_raporlari': '360 Gelişim Raporları',
      },
    ),

    // 3. GÖREVLENDİRME VE İZİN
    'gorevlendirme_ve_izin': const TeacherModuleInfo(
      key: 'gorevlendirme_ve_izin',
      name: 'Görevlendirme ve İzin',
      icon: Icons.assignment_ind,
      color: Colors.brown,
      description: 'Nöbetler, izinler, yapılacaklar ve gezi görevlendirmeleri',
      subModules: {
        'nobetlerim': 'Nöbetlerim',
        'izin_islemleri': 'İzin İşlemleri',
        'yapilacaklar': 'Yapılacaklar (To-Do)',
        'giris_cikis_qr': 'Giriş-Çıkış (QR)',
        'gezi_gorevlendirmeleri': 'Gezi Görevlendirmeleri',
      },
    ),

    // 4. ARAÇLAR
    'araclar': const TeacherModuleInfo(
      key: 'araclar',
      name: 'Araçlar',
      icon: Icons.build_circle_outlined,
      color: Color(0xFFD97706),
      description: 'Sınıf içi yönetim araçları ve kişisel notlar',
      subModules: {
        'sinif_ici_yonetim': 'Sınıf İçi Yönetim ve Etkileşim',
        'notlarim': 'Kişisel Notlarım',
      },
    ),

    // 5. HABERLEŞME & İLETİŞİM
    'iletisim_haberlesme': const TeacherModuleInfo(
      key: 'iletisim_haberlesme',
      name: 'Haberleşme & İletişim',
      icon: Icons.chat_bubble_outline,
      color: Colors.blue,
      description: 'Mesajlaşma, duyurular ve sosyal medya paylaşımları',
      subModules: {
        'mesajlar': 'Mesajlar / Sohbet',
        'duyurular': 'Duyurular',
        'sosyal_medya': 'Sosyal Medya / Akış',
      },
    ),

    // 6. GÖSTERGE PANELİ (DASHBOARD)
    'gosterge_paneli': const TeacherModuleInfo(
      key: 'gosterge_paneli',
      name: 'Gösterge Paneli (Dashboard)',
      icon: Icons.dashboard_outlined,
      color: Colors.teal,
      description: 'Öğretmen ana sayfasındaki bildirimler ve haftalık takvim',
      subModules: {
        'bildirim_akisi': 'Bildirim Akışı & Hatırlatıcılar',
        'takvim_ders_programi': 'Haftalık Ders Takvimi & Programı',
      },
    ),
  };

  static List<String> get allModuleKeys => modules.keys.toList();
  static TeacherModuleInfo? getModule(String key) => modules[key];
}
