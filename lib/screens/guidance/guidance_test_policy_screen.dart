import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GuidanceTestPolicyScreen extends StatelessWidget {
  const GuidanceTestPolicyScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Kullanım Yönergesi', style: GoogleFonts.inter()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 32),
                _buildSection(
                  icon: Icons.search,
                  title: 'Testler Nedir, Ne İşe Yarar?',
                  content:
                      'Bu testler sayesinde:\n'
                      '• Öğrencinin akademik güçlü ve gelişime açık yönleri\n'
                      '• Sınav, kaygı, stres ve dikkat ile ilişkili süreçleri\n'
                      '• Çalışma alışkanlıkları, erteleme eğilimleri ve öğrenme stilleri\n'
                      '• Psikolojik dayanıklılık, öz-yeterlik ve uyum düzeyi\n'
                      '• Teknoloji, uyku ve yaşam düzeninin akademik etkileri\n\n'
                      'bütüncül bir şekilde değerlendirilebilir. Her test tek başına anlamlı olmakla birlikte, birlikte yorumlandığında çok daha sağlıklı sonuçlar verir.',
                ),
                _buildSection(
                  icon: Icons.explore_outlined,
                  title: 'Testleri Uygulama Sırası (Önerilen)',
                  content: 'Testlerin aşağıdaki sırayla uygulanması önerilir:',
                  children: [
                    _buildSubStep(
                      '1. Genel Akademik ve Bilişsel Zemin',
                      'Akademik Benlik Kavramı Ölçeği, Akademik Öz-Yeterlik Algısı Ölçeği, Akademik Dayanıklılık Ölçeği\n👉 Öğrencinin “kendini nasıl gördüğü” ve akademik özgüveni belirlenir.',
                    ),
                    _buildSubStep(
                      '2. Dikkat, Odaklanma ve Performans',
                      'Burdon Dikkat Testi, Dikkat ve Odaklanma Becerisi Ölçeği\n👉 Akademik performansı etkileyen bilişsel süreçler değerlendirilir.',
                    ),
                    _buildSubStep(
                      '3. Sınav Süreci ve Akademik Davranışlar',
                      'Test Çözme Becerileri Ölçeği, Sınavlara Hazırlık Beceri Ölçeği, Akademik Erteleme Ölçeği, Sınav Sonrası Öz Değerlendirme Ölçeği\n👉 Öğrencinin sınav öncesi–anı–sonrası davranışları bütüncül olarak ele alınır.',
                    ),
                    _buildSubStep(
                      '4. Kaygı, Stres ve Duygusal Etmenler',
                      'Sınav Kaygısı Ölçeği, Sınav Kaygısı ile Baş Etme Ölçeği, Kaygı Düzeyi Değerlendirme Ölçeği, Stresle Başa Çıkma Stratejileri Ölçeği, Depresif Eğilim Tarama Ölçeği\n👉 Duygusal süreçlerin akademik yaşama etkisi analiz edilir.',
                    ),
                    _buildSubStep(
                      '5. Yaşam Düzeni ve Çevresel Faktörler',
                      'Uyku Düzeni ve Yeterlilik Ölçeği, Teknoloji Bağımlılığı Ölçeği, Başarısızlık Nedenleri Anketi\n👉 Akademik sorunların okul dışı nedenleri görünür hâle getirilir.',
                    ),
                    _buildSubStep(
                      '6. Sosyal ve Okula Uyum Boyutu',
                      'Sosyal Beceri Envanteri, Okula Uyum Göstergeleri Ölçeği\n👉 Öğrencinin okul ortamındaki sosyal ve duygusal uyumu değerlendirilir.',
                    ),
                  ],
                ),
                _buildSection(
                  icon: Icons.link,
                  title: 'Birlikte Yorumlanması Önerilen Testler',
                  content:
                      'Daha doğru ve güçlü analiz için bazı testlerin birlikte değerlendirilmesi önerilir:',
                  children: [
                    _buildComboItem(
                      'Sınav Kaygısı + Burdon Dikkat',
                      'Kaygının dikkat üzerindeki etkisi',
                    ),
                    _buildComboItem(
                      'Akademik Erteleme + Akademik Öz-Yeterlik',
                      'Ertelemenin özgüvenle ilişkisi',
                    ),
                    _buildComboItem(
                      'Uyku Düzeni + Dikkat/Odaklanma',
                      'Uyku–bilişsel performans ilişkisi',
                    ),
                    _buildComboItem(
                      'Teknoloji Bağımlılığı + Akademik Dayanıklılık',
                      'Dijital alışkanlıkların dirençle ilişkisi',
                    ),
                    _buildComboItem(
                      'Sınav Sonrası Değerlendirme + Test Çözme',
                      'Strateji ve gerçekçi öz değerlendirme',
                    ),
                  ],
                ),
                _buildSection(
                  icon: Icons.psychology_outlined,
                  title: 'Sonuçların Yorumlanması',
                  content:
                      'Test sonuçları;\n'
                      '• Öğrencinin bireysel özellikleri,\n'
                      '• Yaşı, sınıf düzeyi ve gelişimsel durumu\n'
                      '• Öğretmen ve veli gözlemleri\n\n'
                      'ile birlikte değerlendirilmelidir. Sistem tarafından üretilen yapay zekâ destekli yorumlar, rehberlik sürecine destek olmak amacıyla sunulmuştur; kesin yargı niteliği taşımaz.',
                  isLast: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        children: [
          const Icon(Icons.menu_book, size: 48, color: Colors.indigo),
          const SizedBox(height: 16),
          Text(
            'Ölçme Araçları Kullanım Yönergesi',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.indigo.shade900,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Bu katalogda yer alan ölçme araçları; öğrencilerin akademik, duygusal ve bilişsel özelliklerini değerlendirmek amacıyla rehberlik sürecine veri sağlar.',
            style: TextStyle(color: Colors.indigo.shade800, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String content,
    List<Widget>? children,
    bool isLast = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.indigo, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 40),
          child: Text(
            content,
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        if (children != null) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
        if (!isLast) ...[
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 32),
        ],
      ],
    );
  }

  Widget _buildSubStep(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            content,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildComboItem(String title, String desc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.compare_arrows, size: 16, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black87, fontSize: 14),
                children: [
                  TextSpan(
                    text: title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ' → '),
                  TextSpan(
                    text: desc,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
