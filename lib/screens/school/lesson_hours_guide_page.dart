import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LessonHoursGuidePage extends StatelessWidget {
  const LessonHoursGuidePage({Key? key}) : super(key: key);

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
                  _buildGuideSection(
                    icon: Icons.schedule_rounded,
                    color: Colors.blue,
                    title: '1. Haftalık Plan Başlangıcı',
                    description:
                        'Kurumunuzun hangi günlerde eğitim verdiğini seçerek başlayın. Hafta sonu kursları veya sadece hafta içi programları için günleri kolayca özelleştirebilirsiniz.',
                  ),
                  _buildGuideSection(
                    icon: Icons.format_list_numbered_rtl_rounded,
                    color: Colors.indigo,
                    title: '2. Günlük Ders Sayıları',
                    description:
                        'Her gün için kaç ders saati işleneceğini belirleyin. Örneğin; Cuma günleri ders sayısını azaltabilir veya hafta sonları için daha kısa programlar tanımlayabilirsiniz.',
                  ),
                  _buildGuideSection(
                    icon: Icons.timer_rounded,
                    color: Colors.orange,
                    title: '3. Zil Saatleri ve Teneffüsler',
                    description:
                        'Ders başlangıç ve bitiş saatlerini girin. Sistem, ders sürelerini ve teneffüs aralıklarını girdiğiniz saatlere göre otomatik olarak organize eder.',
                  ),
                  _buildGuideSection(
                    icon: Icons.content_copy_rounded,
                    color: Colors.teal,
                    title: '4. Dönemler Arası Transfer',
                    description:
                        'MEB veya kurum standartlarınıza uygun bir programı bir kez hazırlayıp, "Kopyala" özelliği ile diğer tüm alt dönemlere (Yaz Kursu, 2. Dönem vb.) saniyeler içinde aktarabilirsiniz.',
                  ),
                  _buildGuideSection(
                    icon: Icons.notifications_active_rounded,
                    color: Colors.red,
                    title: '5. Akıllı Bildirimler',
                    description:
                        'Tanımladığınız saatler; öğretmenlerin mobil yoklama ekranlarında, sınıfların ders programı tablolarında ve zil sistemlerinde gerçek zamanlı olarak kullanılır.',
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
      expandedHeight: 200.0,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.blue.shade700,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          'Ders Saatleri Rehberi',
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
              colors: [Colors.blue.shade900, Colors.blue.shade500],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -50,
                bottom: -50,
                child: Icon(
                  Icons.access_time_filled_rounded,
                  size: 250,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              Center(
                child: Icon(
                  Icons.av_timer_rounded,
                  size: 80,
                  color: Colors.white.withOpacity(0.2),
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
          'Zamanı Yönetin',
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Ders saatleri, ders programının ve okul yaşamının ritmini belirler. Burada yapacağınız temel ayarlar tüm sistemin doğru işlemesini sağlar.',
          style: GoogleFonts.poppins(
            fontSize: 16,
            color: Colors.grey.shade600,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildGuideSection({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 40),
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
                    color: const Color(0xFF1A1A1A),
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
    );
  }

  Widget _buildProTip() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_rounded, color: Colors.blue.shade800, size: 32),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pratik Bilgi',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
                Text(
                  'Ders programı yapıldıktan sonra saatleri değiştirmek verilerde kaymaya neden olabilir. Bu nedenle programı kesinleştirmeden saatleri netleştirmeniz önerilir.',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.blue.shade900.withOpacity(0.8),
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
