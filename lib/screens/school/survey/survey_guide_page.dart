import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SurveyGuidePage extends StatelessWidget {
  const SurveyGuidePage({Key? key}) : super(key: key);

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
                    icon: Icons.add_task_rounded,
                    color: Colors.blue,
                    title: '1. Yeni Anket Oluşturma',
                    description:
                        'Ana ekrandaki "+" butonuna tıklayarak yeni bir anket başlatabilirsiniz. Anket başlığı ve açıklamasını açık ve anlaşılır tutmak katılım oranını artıracaktır.',
                  ),
                  _buildGuideSection(
                    icon: Icons.people_alt_rounded,
                    color: Colors.green,
                    title: '2. Hedef Kitle Belirleme',
                    description:
                        'Anketlerinizi tüm kuruma, belirli sınıflara veya sadece öğretmenlere özel olarak yayınlayabilirsiniz. Doğru hedef kitle, daha anlamlı veriler almanızı sağlar.',
                  ),
                  _buildGuideSection(
                    icon: Icons.quiz_rounded,
                    color: Colors.orange,
                    title: '3. Atölye ve Soru Tipleri',
                    description:
                        'Çoktan seçmeli, tek seçmeli veya açık uçlu metin yanıtları arasından seçim yapabilirsiniz. Sorularınızı eklerken "Zorunlu" seçeneğini kullanarak kritik verilerin kaçırılmamasını sağlayabilirsiniz.',
                  ),
                  _buildGuideSection(
                    icon: Icons.schedule_send_rounded,
                    color: Colors.purple,
                    title: '4. Planlama ve Yayınlama',
                    description:
                        'Hazırladığınız anketi hemen yayınlayabilir veya gelecekteki bir tarihte otomatik olarak yayına girecek şekilde planlayabilirsiniz. Taslak olarak kaydedip daha sonra üzerinde çalışmaya devam edebilirsiniz.',
                  ),
                  _buildGuideSection(
                    icon: Icons.analytics_rounded,
                    color: Colors.teal,
                    title: '5. Sonuçları Analiz Etme',
                    description:
                        'Anket kartlarına tıklayarak gerçek zamanlı istatistikleri görebilirsiniz. Yanıt oranlarını izleyebilir, sonuçları Excel olarak dışa aktararak derinlemesine analiz yapabilirsiniz.',
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
      backgroundColor: Colors.blue.shade800,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          'Anket İşlemleri Rehberi',
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
              colors: [Colors.blue.shade900, Colors.blue.shade600],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -50,
                bottom: -50,
                child: Icon(
                  Icons.poll_rounded,
                  size: 250,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              Center(
                child: Icon(
                  Icons.auto_awesome_motion_rounded,
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
          'Kurumunuzu Dinleyin',
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Anket modülü, veliler, öğrenciler ve öğretmenlerden geri bildirim almanın en hızlı ve profesyonel yoludur.',
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
                    color: Colors_blackDE,
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
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_rounded, color: Colors.amber.shade800, size: 32),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'İpucu',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                  ),
                ),
                Text(
                  'Anketlerinizi kısa tutup, görsel ve grafiklerle desteklemek katılım oranını %40 oranında artırır.',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.amber.shade900.withOpacity(0.8),
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

const Color Colors_blackDE = Color(0xFF1A1A1A);
