import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PortfolioGuidePage extends StatelessWidget {
  const PortfolioGuidePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(context),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 48),
                  
                  // 1. Genel Bilgiler
                  _buildDetailedSection(
                    icon: Icons.badge_rounded,
                    color: Colors.blue,
                    title: '1. Genel Bilgiler',
                    description:
                        'Öğrencinin kimlik bilgileri, fotoğrafı, veli iletişim detayları ve okul demografisi bu bölümde yer alır. Kayıt durumu ve aktiflik bilgileri buradan yönetilir.',
                  ),
                  
                  // 2. Deneme Sınavları
                  _buildDetailedSection(
                    icon: Icons.analytics_rounded,
                    color: Colors.indigo,
                    title: '2. Deneme Sınavları & LGS',
                    description:
                        'Kurum içi ve genel tüm denemelerin sonuçları, net ortalamaları ve zaman içindeki gelişim grafikleri. LGS hazırlık sürecindeki puan projeksiyonlarını detaylı analiz edin.',
                  ),
                  
                  // 3. Yazılı Sınavlar
                  _buildDetailedSection(
                    icon: Icons.edit_note_rounded,
                    color: Colors.orange,
                    title: '3. Yazılı Sınavlar',
                    description:
                        'Müfredat kapsamındaki dönem içi yazılı sonuçları. Öğrencinin sınıf ve dönem ortalamasına göre akademik pozisyonunu buradan takip edebilirsiniz.',
                  ),
                  
                  // 4. Ödevler
                  _buildDetailedSection(
                    icon: Icons.task_rounded,
                    color: Colors.green,
                    title: '4. Ödev Takibi',
                    description:
                        'Atanan dijital ve fiziksel ödevlerin tamamlama durumu. "Yapıldı", "Gecikti" veya "Bekliyor" statüleri ile öğrencinin sorumluluk performansını görün.',
                  ),
                  
                  // 5. Devamsızlık
                  _buildDetailedSection(
                    icon: Icons.event_busy_rounded,
                    color: Colors.red,
                    title: '5. Devamsızlık Kayıtları',
                    description:
                        'Özürlü, özürsüz veya raporlu devamsızlıkların günlük ve saatlik dökümü. Devamlılık durumu öğrencinin akademik disiplin takibi için kritiktir.',
                  ),
                  
                  // 6. Etütler
                  _buildDetailedSection(
                    icon: Icons.groups_rounded,
                    color: Colors.teal,
                    title: '6. Etüt ve Takviye',
                    description:
                        'Bireysel veya grup olarak planlanan tüm ek derslerin kaydı. Hangi dersten, hangi öğretmenle çalışma yapıldığını ve katılım durumunu izleyin.',
                  ),
                  
                  // 7. Kitaplar
                  _buildDetailedSection(
                    icon: Icons.library_books_rounded,
                    color: Colors.brown,
                    title: '7. Kitap ve Kütüphane',
                    description:
                        'Öğrencinin okuma listesi, bitirdiği kitaplar ve kütüphaneden ödünç alınan materyaller. Okuma alışkanlıklarını destekleyen istatistiklere ulaşın.',
                  ),
                  
                  // 8. Görüşmeler
                  _buildDetailedSection(
                    icon: Icons.record_voice_over_rounded,
                    color: Colors.purple,
                    title: '8. Görüşmeler',
                    description:
                        'Birebir yapılan görüşmelerin gizlilik odaklı dökümleri. Görüşme nedenleri ve gelişim notları burada saklanır.',
                  ),
                  
                  // 9. Gelişim Raporu
                  _buildDetailedSection(
                    icon: Icons.description_rounded,
                    color: Colors.deepOrange,
                    title: '9. 360 Gelişim Raporları',
                    description:
                        'Öğrencinin akademik, sosyal ve psikolojik durumunu özetleyen periyodik değerlendirme raporları. Gelişim süreçlerine dair uzman yorumlarını içerir.',
                  ),
                  
                  // 10. Çalışma Programları
                  _buildDetailedSection(
                    icon: Icons.calendar_month_rounded,
                    color: Colors.cyan,
                    title: '10. Çalışma Programları',
                    description:
                        'Öğrenciye özel hazırlanmış haftalık ders çalışma takvimleri. Yazdırılabilir programlar ve öğrencinin bu programlara uyum performansı.',
                  ),
                  
                  // 11. Rehberlik Testleri
                  _buildDetailedSection(
                    icon: Icons.psychology_rounded,
                    color: Colors.deepPurple,
                    title: '11. Envanter ve Testler',
                    description:
                        'Mesleki yönelim, kişilik testleri ve ilgi envanterlerinin profesyonel sonuç dökümleri. Öğrencinin yeteneklerini ve eğilimlerini keşfedin.',
                  ),
                  
                  // 12. Etkinlik Raporları
                  _buildDetailedSection(
                    icon: Icons.auto_awesome_rounded,
                    color: Colors.pink,
                    title: '12. Etkinlik Raporları',
                    description:
                        'Kulüp çalışmaları, sosyal sorumluluk projeleri ve okul gezilerinin katılım dökümleri. Öğrencinin okul dışı aktivitelerdeki varlığını raporlayın.',
                  ),

                  const SizedBox(height: 32),
                  _buildProTip(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 220.0,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.indigo.shade900,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          'Detaylı Portfolyo Rehberi',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [const Color(0xFF1E1B4B), const Color(0xFF4338CA)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -40,
                bottom: -40,
                child: Icon(
                  Icons.folder_copy_rounded,
                  size: 250,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
              Positioned(
                left: -20,
                top: -20,
                child: Icon(
                  Icons.account_tree_rounded,
                  size: 150,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.manage_search_rounded,
                      size: 80,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tam Kapsamlı Öğrenci Arşivi',
          style: GoogleFonts.poppins(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Gelişmiş portfolyo sistemi, bir öğrencinin eğitim hayatındaki tüm izleri tek bir noktada toplar. Aşağıdaki 12 ana modül sayesinde öğrenciyi 360 derece analiz edebilirsiniz.',
          style: GoogleFonts.poppins(
            fontSize: 16,
            color: Colors.grey.shade600,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailedSection({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProTip() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_circle_rounded, color: Colors.indigo.shade800, size: 36),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bütünsel Bakış Açısı',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.indigo.shade900,
                  ),
                ),
                Text(
                  'Portfolyo verileri birbiriyle ilişkilidir. Örneğin; devamsızlık kayıtlarındaki bir artışın deneme sınavı netlerine yansımasını bu panelden hızlıca analiz edebilirsiniz.',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.indigo.shade900.withOpacity(0.8),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
