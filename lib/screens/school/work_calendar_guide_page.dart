import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class WorkCalendarGuidePage extends StatelessWidget {
  const WorkCalendarGuidePage({Key? key}) : super(key: key);

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
                    icon: Icons.calendar_view_month_rounded,
                    color: Colors.green,
                    title: '1. Alt Dönem Yönetimi',
                    description:
                        'Eğitim yılınızı mantıksal bölümlere ayırın. Güz dönemi, Bahar dönemi veya Yaz kursu gibi farklı çalışma aralıkları oluşturarak her dönemi bağımsız yönetebilirsiniz.',
                  ),
                  _buildGuideSection(
                    icon: Icons.edit_calendar_rounded,
                    color: Colors.teal,
                    title: '2. Yıllık Plan Entegrasyonu',
                    description:
                        'Her alt dönem için ders bazlı yıllık planlar hazırlayabilirsiniz. Bu planlar, öğretmenlerin haftalık ders dağılımını ve müfredat takibini otomatik olarak organize eder.',
                  ),
                  _buildGuideSection(
                    icon: Icons.holiday_village_rounded,
                    color: Colors.orange,
                    title: '3. Tatil ve Önemli Günler',
                    description:
                        'Resmi tatilleri, ara tatilleri ve kurumunuza özel önemli günleri takvim üzerinde işaretleyerek ders programlarının bu günlere göre otomatik güncellenmesini sağlayabilirsiniz.',
                  ),
                  _buildGuideSection(
                    icon: Icons.sync_rounded,
                    color: Colors.blue,
                    title: '4. Sistem Çapında Etki',
                    description:
                        'Çalışma takviminde yaptığınız tarihler; yoklama listelerini, sınav tarihlerini ve raporlama dönemlerini doğrudan etkiler. Bu nedenle tarih aralıklarını dikkatli belirlemek önemlidir.',
                  ),
                  _buildGuideSection(
                    icon: Icons.cloud_download_rounded,
                    color: Colors.indigo,
                    title: '5. Veri Aktarımı ve Yedekleme',
                    description:
                        'Hazırladığınız takvimleri dilediğiniz zaman Excel formatında dışa aktarabilir veya sistem üzerinden çıktı alarak fiziksel panolarınızda kullanabilirsiniz.',
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
      backgroundColor: Colors.green.shade800,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          'Takvim ve Plan Rehberi',
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
              colors: [Colors.green.shade900, Colors.green.shade600],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -50,
                bottom: -50,
                child: Icon(
                  Icons.calendar_today_rounded,
                  size: 250,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              Center(
                child: Icon(
                  Icons.event_note_rounded,
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
          'Eğitimi Planlayın',
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Çalışma takvimi, kurumunuzun zaman yönetimindeki ana omurgasıdır. Doğru planlanmış bir takvim, tüm akademik süreci hatasız yürütmenizi sağlar.',
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
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.tips_and_updates_rounded, color: Colors.green.shade800, size: 32),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Uzman Tavsiyesi',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade900,
                  ),
                ),
                Text(
                  'Dönemleri oluştururken aralarında 1-2 günlük boşluklar bırakmak veya çakıştırmamak, raporlama doğruluğu için kritik öneme sahiptir.',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.green.shade900.withOpacity(0.8),
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
