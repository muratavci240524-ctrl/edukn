import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ClassScheduleGuidePage extends StatelessWidget {
  const ClassScheduleGuidePage({Key? key}) : super(key: key);

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
                    icon: Icons.dashboard_customize_rounded,
                    color: Colors.purple,
                    title: '1. Şube ve Ders Temelleri',
                    description:
                        'Program hazırlamaya başlamadan önce, şubelere ders ve öğretmen atamalarının yapılmış olması gerekir. Eksik ders atamaları "Kalan Dersler" listesinde uyarı olarak görünür.',
                  ),
                  _buildGuideSection(
                    icon: Icons.auto_awesome_rounded,
                    color: Colors.deepPurple,
                    title: '2. Otomatik Program Sihirbazı',
                    description:
                        'Karmaşık çakışmaları çözmekle uğraşmayın! "Otomatik Dağıt" özelliğini kullanarak; öğretmen boş günleri ve ders saatlerini gözeterek tüm programı saniyeler içinde oluşturabilirsiniz.',
                  ),
                  _buildGuideSection(
                    icon: Icons.warning_amber_rounded,
                    color: Colors.orange,
                    title: '3. Çakışma ve Hata Kontrolü',
                    description:
                        'Sistem, aynı öğretmenin veya aynı sınıfın çakışan saatlerini otomatik olarak denetler. Kırmızı ile işaretlenen alanlar, bir çakışma olduğunu ve düzeltilmesi gerektiğini belirtir.',
                  ),
                  _buildGuideSection(
                    icon: Icons.publish_rounded,
                    color: Colors.green,
                    title: '4. Yayınlama ve Görünürlük',
                    description:
                        'Hazırladığınız programı "Yayınla" butonu ile aktif hale getirebilirsiniz. Yayınlanmayan programlar öğretmen ve velilerin mobil uygulamalarında görünmez.',
                  ),
                  _buildGuideSection(
                    icon: Icons.ios_share_rounded,
                    color: Colors.blue,
                    title: '5. PDF ve Excel Paylaşımı',
                    description:
                        'Sınıf bazlı veya öğretmen bazlı programları tek bir dokunuşla PDF formatında indirebilir veya WhatsApp üzerinden ilgili gruplara hızlıca paylaşabilirsiniz.',
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
      backgroundColor: Colors.purple.shade700,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          'Ders Programı Rehberi',
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
              colors: [Colors.purple.shade900, Colors.purple.shade500],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -50,
                bottom: -50,
                child: Icon(
                  Icons.calendar_view_week_rounded,
                  size: 250,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              Center(
                child: Icon(
                  Icons.auto_stories_rounded,
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
          'Akademik Düzeni Kurun',
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Ders programı yönetimi, eğitim kalitesinin sürdürülebilirliği için en kritik adımdır. Karmaşık planlamaları basit ve hatasız bir şekilde tamamlayın.',
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
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.psychology_rounded, color: Colors.purple.shade800, size: 32),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Yapay Zeka İpucu',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: Colors.purple.shade900,
                  ),
                ),
                Text(
                  'Otomatik dağıtım yapmadan önce öğretmenlerin "Haftalık Boş Günleri"ni sisteme tanımlarsanız, program çok daha dengeli ve sorunsuz oluşacaktır.',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.purple.shade900.withOpacity(0.8),
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
