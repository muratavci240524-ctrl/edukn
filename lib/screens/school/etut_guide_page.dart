import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EtutGuidePage extends StatelessWidget {
  const EtutGuidePage({Key? key}) : super(key: key);

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
                    icon: Icons.person_search_rounded,
                    color: Colors.indigo,
                    title: '1. Dinamik Seçim Deneyimi',
                    description:
                        'Etüt planlamadan önce sol taraftan öğrenci tabanlı, sağ taraftan ise öğretmen tabanlı seçim yapın. Seçtiğiniz kişilerin mevcudiyetleri takvimde anlık olarak birleşerek size en doğru zamanı fısıldar.',
                  ),
                  _buildGuideSection(
                    icon: Icons.touch_app_rounded,
                    color: Colors.orange,
                    title: '2. Tek Dokunuşla Planlama',
                    description:
                        'Takvim üzerindeki boş bir hücreye dokunduğunuzda, sistem seçili tüm öğrenci ve öğretmenleri otomatik olarak harmanlar. Size sadece konuyu onaylamak kalır.',
                  ),
                  _buildGuideSection(
                    icon: Icons.security_rounded,
                    color: Colors.green,
                    title: '3. Üç Katmanlı Çakışma Denetimi',
                    description:
                        'Sistem sadece takvimi kontrol etmez; seçili öğretmenin ders programını, öğrencilerin diğer etütlerini ve okulun genel çalışma saatlerini aynı anda denetleyerek çakışmaları engeller.',
                  ),
                  _buildGuideSection(
                    icon: Icons.bolt_rounded,
                    color: Colors.blue,
                    title: '4. Hızlı Bildirim Mekanizması',
                    description:
                        'Oluşturulan her etüt, kaydedildiği saniyede velilerin ve öğrencilerin mobil uygulamalarına "Yeni Etüt Atandı" bildirimi olarak gider. Unutulma riskini ortadan kaldırır.',
                  ),
                  _buildGuideSection(
                    icon: Icons.tune_rounded,
                    color: Colors.redAccent,
                    title: '5. Kurumsal Esnek Ayarlar',
                    description:
                        'Sağ üstteki çark simgesiyle kurumunuzun başlangıç-bitiş saatlerini ve hafta sonu çalışma durumlarını dilediğiniz gibi özelleştirebilirsiniz.',
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
      backgroundColor: Colors.indigo.shade800,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          'Etüt Yönetim Rehberi',
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
              colors: [Colors.indigo.shade900, Colors.indigo.shade500],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -40,
                top: -40,
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 200,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
              Positioned(
                left: -20,
                bottom: -20,
                child: Icon(
                  Icons.history_edu_rounded,
                  size: 150,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.tips_and_updates_rounded,
                      size: 70,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    const SizedBox(height: 40), // Spacer for title
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
          'Birebir Başarıyı Planlayın',
          style: GoogleFonts.poppins(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E1E1E),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Etüt işlemleri, öğrencinin eksiğini saptayıp doğru öğretmenle doğru zamanda buluşturma sanatıdır. Bu paneli kullanarak akademik takviyeleri en verimli şekilde yönetin.',
          style: GoogleFonts.poppins(
            fontSize: 15,
            color: Colors.grey.shade600,
            height: 1.6,
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
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2D2D2D),
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
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_rounded, color: Colors.indigo.shade800, size: 30),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Verimlilik İpucu',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade900,
                  ),
                ),
                Text(
                  'Etütleri planlarken takvimdeki gri alanlar "Ders Programı" veya "Yoğunluk" çakışmalarını temsil eder. En temiz beyaz alanı seçmek başarı oranınızı artırır.',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.indigo.shade900.withOpacity(0.8),
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
