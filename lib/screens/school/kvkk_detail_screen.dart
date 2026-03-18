import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class KvkkDetailScreen extends StatefulWidget {
  const KvkkDetailScreen({Key? key}) : super(key: key);

  @override
  State<KvkkDetailScreen> createState() => _KvkkDetailScreenState();
}

class _KvkkDetailScreenState extends State<KvkkDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _reachedBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 50) {
      if (!_reachedBottom) {
        setState(() => _reachedBottom = true);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KVKK Aydınlatma Metni'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E2661),
      ),
      body: Column(
        children: [
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '6698 SAYILI KİŞİSEL VERİLERİN KORUNMASI KANUNU (KVKK) AYDINLATMA METNİ',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E2661),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildSection('1. Veri Sorumlusu', 
                      'eduKN Eğitim Yönetim Sistemi olarak, kişisel verilerinizin güvenliği hususuna azami hassasiyet göstermekteyiz. Bu bilinçle, kuruma ait her türlü kişisel verinin 6698 sayılı Kişisel Verilerin Korunması Kanunu’na uygun olarak işlenmesine ve muhafaza edilmesine büyük önem vermekteyiz.'),
                    _buildSection('2. Kişisel Verilerin İşlenme Amacı', 
                      'Kişisel verileriniz; eğitim faaliyetlerinin sürdürülmesi, öğrenci ve öğretmen kayıt süreçlerinin yönetimi, devam takip sisteminin işletilmesi, duyuru ve bilgilendirme hizmetlerinin sunulması amaçlarıyla Kanun’un 5. ve 6. maddelerinde belirtilen şartlar dahilinde işlenmektedir.'),
                    _buildSection('3. İşlenen Kişisel Veriler', 
                      'Sistem üzerinde ad, soyad, T.C. kimlik numarası, iletişim bilgileri, öğrenim durumu, devam-devamsızlık kayıtları ve eğitimle ilgili diğer gerekli veriler işlenmektedir.'),
                    _buildSection('4. Verilerin Aktarılması', 
                      'Kişisel verileriniz, yasal yükümlülüklerimizin yerine getirilmesi amacıyla yetkili kamu kurum ve kuruluşları ile paylaşılabilmektedir. Bunun dışında üçüncü şahıslara yasal zorunluluk olmadıkça aktarılmamaktadır.'),
                    _buildSection('5. Haklarınız', 
                      'Kanun’un 11. maddesi uyarınca; verilerinizin işlenip işlenmediğini öğrenme, işlenmişse bilgi talep etme, işlenme amacına uygun kullanılıp kullanılmadığını öğrenme ve verilerin düzeltilmesini isteme haklarına sahipsiniz.'),
                    const SizedBox(height: 100), // En aşağı inildiğini anlamak için boşluk
                    Center(
                      child: Text(
                        '--- Metnin Sonu ---',
                        style: TextStyle(color: Colors.grey.shade400, fontStyle: FontStyle.italic),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5)),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _reachedBottom 
                    ? () => Navigator.pop(context, true) 
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4C59BC),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  _reachedBottom ? 'Okudum, Anladım' : 'Lütfen Metnin Tamamını Okuyun',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF4C59BC),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.grey.shade800,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
