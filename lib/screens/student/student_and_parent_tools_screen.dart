import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:url_launcher/url_launcher.dart';

import '../../services/term_service.dart';
import '../../widgets/edukn_app_bar.dart';
import '../school/daily_report/parent_daily_report_screen.dart';
import '../school/guidance/saved_study_programs_screen.dart';
import 'parent_accounting_screen.dart';
import 'parent_early_pickup_screen.dart';
import 'student_etut_stats_screen.dart';
import 'student_exam_stats_screen.dart';
import 'student_homework_stats_screen.dart';
import 'student_personal_academic_tools_screen.dart';
import '../store/store_shop_screen.dart';
import '../canteen_user/canteen_parent_screen.dart';
import '../canteen_user/canteen_student_screen.dart';

/// Öğrenci ve Veli için özel Araçlar Merkezi:
/// - Online İşlemler (Online Eğitim Portalları / LinGoKN SSO, Online Deneme & Sınavlar, Online Etüt Talebi, Online Anketler, Ödev Teslim)
/// - Yemek Listesi (Bugünün Menüsü + Haftalık Okul Yemek Listesi)
/// - Kişisel Akademik Ölçme Araçları (YALNIZCA öğrencinin kendi verileriyle çalışan Simülatör, Net Koçu, Kazanım Karnesi, Takdir/Teşekkür Hesaplayıcı)
/// - Veli Özel Araçları (Erken Alma & Okula Geldim Talebi, Günlük Karne, Ödeme & Taksit Takibi)
class StudentAndParentToolsScreen extends StatefulWidget {
  final String institutionId;
  final String studentId;
  final Map<String, dynamic> studentData;
  final bool isParentUser;
  final bool dailyReportEnabled;
  final bool storeEnabled;
  final bool kantinEnabled;
  final String initialCategory;

  const StudentAndParentToolsScreen({
    super.key,
    required this.institutionId,
    required this.studentId,
    required this.studentData,
    required this.isParentUser,
    this.dailyReportEnabled = false,
    this.storeEnabled = true,
    this.kantinEnabled = false,
    this.initialCategory = 'Tümü',
  });

  @override
  State<StudentAndParentToolsScreen> createState() =>
      _StudentAndParentToolsScreenState();
}

class _StudentToolDef {
  final String category;
  final String title;
  final String subtitle;
  final String badge;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _StudentToolDef({
    required this.category,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _StudentAndParentToolsScreenState
    extends State<StudentAndParentToolsScreen> {
  late String _selectedCategory;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
  }

  String get _studentName {
    final full = (widget.studentData['fullName'] ?? '').toString().trim();
    if (full.isNotEmpty) return full;
    return '${widget.studentData['name'] ?? ''} ${widget.studentData['surname'] ?? ''}'
        .trim();
  }

  String get _studentNo =>
      (widget.studentData['studentNo'] ??
              widget.studentData['studentNumber'] ??
              widget.studentData['no'] ??
              '')
          .toString()
          .trim();

  String get _className =>
      (widget.studentData['className'] ?? '').toString().trim();

  String get _classId =>
      (widget.studentData['classId'] ?? '').toString().trim();

  String get _schoolTypeId =>
      (widget.studentData['schoolTypeId'] ?? '').toString().trim();

  String get _classLevel {
    final raw =
        (widget.studentData['classLevel'] ??
                widget.studentData['gradeLevel'] ??
                '')
            .toString()
            .trim();
    if (raw.isNotEmpty) return raw;
    final digits = RegExp(r'\d+').firstMatch(_className)?.group(0) ?? '';
    if (digits.startsWith('10') ||
        digits.startsWith('11') ||
        digits.startsWith('12')) {
      return digits.substring(0, 2);
    }
    return digits.isNotEmpty ? digits.substring(0, 1) : '';
  }

  String get _studentSubtitle {
    final parts = <String>[
      if (widget.isParentUser) 'Veli Paneli',
      if (_studentNo.isNotEmpty) _studentNo,
      if (_studentName.isNotEmpty) _studentName,
      if (_className.isNotEmpty) '($_className)',
    ];
    return parts.join(' • ');
  }

  List<_StudentToolDef> _buildTools() {
    final instUpper = widget.institutionId.toUpperCase();
    return [
      if (widget.isParentUser) ...[
        _StudentToolDef(
          category: 'Veli Özel',
          title: 'Erken Alma & Okula Geldim Talebi',
          subtitle:
              'Çocuğunuzu okuldan erken alma ön bildirimi oluşturun veya kapıya geldiğinizde tek tuşla sınıfına/güvenliğe haber verin.',
          badge: 'Canlı Çıkış',
          icon: Icons.directions_car_filled_rounded,
          color: const Color(0xFF0D9488),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ParentEarlyPickupScreen(
                institutionId: instUpper,
                studentId: widget.studentId,
                initialStudentData: widget.studentData,
              ),
            ),
          ),
        ),
        if (widget.dailyReportEnabled)
          _StudentToolDef(
            category: 'Veli Özel',
            title: 'Günlük Karne & Beslenme/Etkinlik Özeti',
            subtitle:
                'Öğretmenlerin paylaştığı günlük kazanım, beslenme, uyku ve duygu durumu geri bildirimlerini inceleyin.',
            badge: 'Günlük Rapor',
            icon: Icons.auto_awesome_rounded,
            color: const Color(0xFFEC4899),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ParentDailyReportScreen(
                  institutionId: instUpper,
                  studentId: widget.studentId,
                  studentName: _studentName,
                  className: _className,
                ),
              ),
            ),
          ),
        _StudentToolDef(
          category: 'Veli Özel',
          title: 'Ödeme Planı & Muhasebe Takibi',
          subtitle:
              'Kayıt sözleşmesi, taksit vadeleri ve yapılan ödemelerin güncel dökümünü görüntüleyin.',
          badge: 'Finans',
          icon: Icons.account_balance_wallet_rounded,
          color: const Color(0xFF2563EB),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ParentAccountingScreen(
                institutionId: instUpper,
                studentId: widget.studentId,
                studentName: _studentName,
              ),
            ),
          ),
        ),
      ],

      // ── YEMEK LİSTESİ (Öğrenci & Veli) ──
      _StudentToolDef(
        category: 'Yemek Listesi',
        title: 'Günlük & Haftalık Yemek Listesi',
        subtitle:
            'Okul yemekhanesinin bugünkü öğünlerini, haftalık menü takvimini ve kalori bilgilerini görüntüleyin.',
        badge: 'Yemekhane',
        icon: Icons.restaurant_menu_rounded,
        color: const Color(0xFFEA580C),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentMealMenuScreen(
              institutionId: instUpper,
              schoolTypeId: _schoolTypeId,
              studentSubtitle: _studentSubtitle,
            ),
          ),
        ),
      ),

      // ── ONLİNE İŞLEMLER (Öğrenci & Veli) ──
      if (widget.storeEnabled)
        _StudentToolDef(
          category: 'Online İşlemler',
          title: 'Okul & Genel Merkez Mağazası (Online Alışveriş)',
          subtitle:
              'Kitap seti, kırtasiye, okul kıyafeti, deneme paketi ve materyalleri online kartla satın alın ve siparişinizi takip edin.',
          badge: 'Mağaza',
          icon: Icons.storefront_rounded,
          color: Colors.deepOrange,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StoreShopScreen(
                institutionId: instUpper,
                schoolTypeId: _schoolTypeId.isEmpty ? null : _schoolTypeId,
                buyerRole: widget.isParentUser ? 'veli' : 'ogrenci',
                studentId: widget.studentId,
                studentName: _studentName.isEmpty ? null : _studentName,
              ),
            ),
          ),
        ),
      if (widget.kantinEnabled)
        _StudentToolDef(
          category: 'Online İşlemler',
          title: 'Kantin (Bakiye, Hareketler, Ürünler)',
          subtitle:
              'Kantin kartı bakiyesi, günlük limit, ürün bloke, harcama hareketleri ve kantin ürünleri.',
          badge: 'Kantin',
          icon: Icons.fastfood_rounded,
          color: const Color(0xFFE53935),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => widget.isParentUser
                  ? CanteenParentScreen(
                      institutionId: instUpper,
                      studentId: widget.studentId,
                      studentName: _studentName.isEmpty ? null : _studentName,
                    )
                  : CanteenStudentScreen(
                      institutionId: instUpper,
                      studentId: widget.studentId,
                      studentName: _studentName.isEmpty ? null : _studentName,
                    ),
            ),
          ),
        ),
      _StudentToolDef(
        category: 'Online İşlemler',
        title: 'Online Eğitim Portalları & Dijital Hizmetler',
        subtitle:
            'LinGoKN SSO dil platformu ve okulunuzun tanımladığı tüm online eğitim portallarına tek tıkla bağlanın.',
        badge: 'SSO / Web',
        icon: Icons.language_rounded,
        color: const Color(0xFF00897B),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentOnlineServicesScreen(
              institutionId: instUpper,
              studentId: widget.studentId,
              studentData: widget.studentData,
              studentSubtitle: _studentSubtitle,
              initialTab: 0,
            ),
          ),
        ),
      ),
      _StudentToolDef(
        category: 'Online İşlemler',
        title: 'Online Sınav & Deneme Takvimi',
        subtitle:
            'Sınıf seviyene tanımlanan aktif deneme sınavlarını, online sınav bağlantılarını ve kişisel sınav karnelerini incele.',
        badge: 'Online Sınav',
        icon: Icons.computer_rounded,
        color: const Color(0xFF4F46E5),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentOnlineServicesScreen(
              institutionId: instUpper,
              studentId: widget.studentId,
              studentData: widget.studentData,
              studentSubtitle: _studentSubtitle,
              initialTab: 1,
            ),
          ),
        ),
      ),
      _StudentToolDef(
        category: 'Online İşlemler',
        title: 'Online Etüt Talebi Oluştur',
        subtitle:
            'Eksik hissettiğin konularda öğretmenlerinden birebir veya grup etüt talebi oluştur ve onay durumunu takip et.',
        badge: 'Etüt Talep',
        icon: Icons.record_voice_over_rounded,
        color: const Color(0xFF7C3AED),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentEtutStatsScreen(
              institutionId: instUpper,
              studentId: widget.studentId,
              studentName: _studentName,
              classId: _classId,
            ),
          ),
        ),
      ),
      _StudentToolDef(
        category: 'Online İşlemler',
        title: 'Online Anket & Dijital Formlarım',
        subtitle:
            'Okul yönetimi ve rehberlik birimi tarafından paylaşılan aktif anketlere katılın.',
        badge: 'Anket',
        icon: Icons.poll_rounded,
        color: const Color(0xFF0284C7),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentOnlineServicesScreen(
              institutionId: instUpper,
              studentId: widget.studentId,
              studentData: widget.studentData,
              studentSubtitle: _studentSubtitle,
              initialTab: 2,
            ),
          ),
        ),
      ),
      _StudentToolDef(
        category: 'Online İşlemler',
        title: 'Ödev Teslim & Kontrol Takibi',
        subtitle:
            'Öğretmenlerin verdiği aktif ödevleri, son teslim tarihlerini ve kişisel kontrol sonuçlarını anlık gör.',
        badge: 'Ödevlerim',
        icon: Icons.task_alt_rounded,
        color: const Color(0xFF059669),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentHomeworkStatsScreen(
              institutionId: instUpper,
              studentId: widget.studentId,
              classId: _classId,
              studentName: _studentName,
            ),
          ),
        ),
      ),

      // ── KİŞİSEL AKADEMİK ÖLÇME ARAÇLARI (SADECE ÖĞRENCİNİN KENDİ VERİLERİ) ──
      _StudentToolDef(
        category: 'Akademik Analiz',
        title: 'Kişisel LGS / YKS Puan & Hedef Simülatörü',
        subtitle:
            'Kendi son deneme netlerinle puan ve yüzdelik dilimini simüle et, hedef puanına kaç net kaldığını hesapla.',
        badge: 'Kişisel Veri',
        icon: Icons.rocket_launch_rounded,
        color: const Color(0xFF4338CA),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentPersonalAcademicToolsScreen(
              institutionId: instUpper,
              studentId: widget.studentId,
              studentData: widget.studentData,
              initialToolIndex: 0,
              isParentView: widget.isParentUser,
            ),
          ),
        ),
      ),
      _StudentToolDef(
        category: 'Akademik Analiz',
        title: 'Kişisel Deneme Gelişim & Net Koçum',
        subtitle:
            'Yalnızca kendi deneme sınavlarının soru sayısına göre dengelenmiş net grafiğini ve strateji analizini incele.',
        badge: 'Net Koçu',
        icon: Icons.insights_rounded,
        color: const Color(0xFF059669),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentPersonalAcademicToolsScreen(
              institutionId: instUpper,
              studentId: widget.studentId,
              studentData: widget.studentData,
              initialToolIndex: 1,
              isParentView: widget.isParentUser,
            ),
          ),
        ),
      ),
      _StudentToolDef(
        category: 'Akademik Analiz',
        title: 'Branş & Kazanım Eksik Karnem',
        subtitle:
            'Kendi denemelerindeki doğru/yanlış dağılımına göre güçlü derslerini ve öncelikli çalışman gereken konuları gör.',
        badge: 'Konu Analizi',
        icon: Icons.radar_rounded,
        color: const Color(0xFFD97706),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentPersonalAcademicToolsScreen(
              institutionId: instUpper,
              studentId: widget.studentId,
              studentData: widget.studentData,
              initialToolIndex: 2,
              isParentView: widget.isParentUser,
            ),
          ),
        ),
      ),
      _StudentToolDef(
        category: 'Akademik Analiz',
        title: 'Yazılı Ortalaması & Takdir/Teşekkür Hesaplayıcı',
        subtitle:
            'Kendi yazılı notlarınla dönem sonu ağırlıklı ortalamanı ve Takdir / Teşekkür belgesi durumunu canlı hesapla.',
        badge: 'Belge Hesabı',
        icon: Icons.workspace_premium_rounded,
        color: const Color(0xFF9333EA),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentPersonalAcademicToolsScreen(
              institutionId: instUpper,
              studentId: widget.studentId,
              studentData: widget.studentData,
              initialToolIndex: 3,
              isParentView: widget.isParentUser,
            ),
          ),
        ),
      ),
      _StudentToolDef(
        category: 'Akademik Analiz',
        title: 'Çalışma Programlarım',
        subtitle:
            'Rehberlik ve danışman öğretmenlerin tarafından sana özel hazırlanan haftalık ders çalışma programlarını görüntüle.',
        badge: 'Planlama',
        icon: Icons.calendar_month_rounded,
        color: const Color(0xFF0891B2),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SavedStudyProgramsScreen(
              institutionId: instUpper,
              schoolTypeId: _schoolTypeId,
              isTeacher: false,
              allowedStudentIds: [widget.studentId],
            ),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final allTools = _buildTools();
    final categories = <String>[
      'Tümü',
      if (widget.isParentUser) 'Veli Özel',
      'Online İşlemler',
      'Yemek Listesi',
      'Akademik Analiz',
    ];
    final visibleTools = _selectedCategory == 'Tümü'
        ? allTools
        : allTools.where((t) => t.category == _selectedCategory).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        institutionId: widget.institutionId,
        title: widget.isParentUser
            ? 'Veli Araçlar Merkezi'
            : 'Öğrenci Araçlarım',
        subtitle: _studentSubtitle,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 768;
          final hPad = isMobile ? 14.0 : 28.0;
          final usableW = constraints.maxWidth - hPad * 2;
          final cols = isMobile
              ? 2
              : (usableW >= 1200 ? 4 : (usableW >= 860 ? 3 : 2));
          final gap = isMobile ? 10.0 : 16.0;
          final cardW = (usableW - gap * (cols - 1)) / cols;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 18, hPad, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: categories.map((cat) {
                      final selected = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            cat,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: selected
                                  ? Colors.white
                                  : const Color(0xFF334155),
                            ),
                          ),
                          selected: selected,
                          showCheckmark: false,
                          selectedColor: const Color(0xFF4F46E5),
                          backgroundColor: Colors.white,
                          onSelected: (_) =>
                              setState(() => _selectedCategory = cat),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: visibleTools.map((tool) {
                    return SizedBox(
                      width: cardW,
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          onTap: tool.onTap,
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: EdgeInsets.all(isMobile ? 13 : 18),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: tool.color.withValues(alpha: 0.2),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(
                                        isMobile ? 9 : 11,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tool.color.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        tool.icon,
                                        color: tool.color,
                                        size: isMobile ? 20 : 24,
                                      ),
                                    ),
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: tool.color.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: Text(
                                          tool.badge,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: tool.color,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: isMobile ? 10 : 14),
                                Text(
                                  tool.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: isMobile ? 13 : 15,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  tool.subtitle,
                                  maxLines: isMobile ? 3 : 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: isMobile ? 11 : 12.2,
                                    color: const Color(0xFF64748B),
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// YEMEK LİSTESİ EKRANI (Öğrenci & Veli - Günlük & Haftalık Canlı Görünüm)
// ═══════════════════════════════════════════════════════════════════════════

class StudentMealMenuScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String studentSubtitle;

  const StudentMealMenuScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.studentSubtitle,
  });

  @override
  State<StudentMealMenuScreen> createState() => _StudentMealMenuScreenState();
}

class _StudentMealMenuScreenState extends State<StudentMealMenuScreen> {
  bool _loading = true;
  String? _schoolDocId;
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _periods = [];
  // key: yyyy-MM-dd -> periodId -> list of menu items
  final Map<String, Map<String, List<Map<String, dynamic>>>> _weekMenus = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  String _dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final instIds = {
        widget.institutionId,
        widget.institutionId.toUpperCase(),
        widget.institutionId.toLowerCase(),
      }.where((e) => e.isNotEmpty).toList();

      final schoolSnap = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', whereIn: instIds)
          .limit(1)
          .get();

      if (schoolSnap.docs.isNotEmpty) {
        _schoolDocId = schoolSnap.docs.first.id;
      } else {
        final byDoc = await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.institutionId)
            .get();
        if (byDoc.exists) _schoolDocId = byDoc.id;
      }

      if (_schoolDocId != null && _schoolDocId!.isNotEmpty) {
        final pSnap = await FirebaseFirestore.instance
            .collection('schools')
            .doc(_schoolDocId)
            .collection('mealPeriods')
            .get();
        final allPeriods = pSnap.docs
            .map((d) => {'id': d.id, ...d.data()})
            .toList();
        _periods = allPeriods.where((p) {
          if (p['isActive'] == false) return false;
          final typeIds = List<String>.from(p['schoolTypeIds'] ?? []);
          if (typeIds.isEmpty || widget.schoolTypeId.isEmpty) return true;
          return typeIds.contains(widget.schoolTypeId);
        }).toList();

        await _loadWeekMenus(_selectedDate);
      }
    } catch (e) {
      debugPrint('StudentMealMenu bootstrap error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadWeekMenus(DateTime anchor) async {
    if (_schoolDocId == null || _periods.isEmpty) return;
    _weekMenus.clear();
    final monday = _mondayOf(anchor);
    final nextMonday = monday.add(const Duration(days: 7));

    await Future.wait(
      _periods.map((p) async {
        final pid = p['id'].toString();
        try {
          final snap = await FirebaseFirestore.instance
              .collection('schools')
              .doc(_schoolDocId)
              .collection('mealPeriods')
              .doc(pid)
              .collection('menus')
              .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(monday))
              .where('date', isLessThan: Timestamp.fromDate(nextMonday))
              .get();
          for (final doc in snap.docs) {
            final data = doc.data();
            final dt = (data['date'] as Timestamp?)?.toDate();
            if (dt == null) continue;
            final k = _dayKey(dt);
            _weekMenus.putIfAbsent(k, () => {}).putIfAbsent(pid, () => []).add({
              'id': doc.id,
              ...data,
            });
          }
        } catch (_) {}
      }),
    );
  }

  Future<void> _changeWeek(int deltaDays) async {
    final next = _selectedDate.add(Duration(days: deltaDays));
    setState(() {
      _selectedDate = next;
      _loading = true;
    });
    await _loadWeekMenus(next);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final monday = _mondayOf(_selectedDate);
    final weekDays = List.generate(7, (i) => monday.add(Duration(days: i)));
    const dayLabels = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    final selectedKey = _dayKey(_selectedDate);
    final selectedDayMenus = _weekMenus[selectedKey] ?? {};

    int totalCaloriesToday = 0;
    for (final list in selectedDayMenus.values) {
      for (final item in list) {
        totalCaloriesToday += (item['calories'] as num?)?.toInt() ?? 0;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        institutionId: widget.institutionId,
        title: 'Yemek Listesi',
        subtitle: widget.studentSubtitle,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hafta seçici bar
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => _changeWeek(-7),
                              icon: const Icon(Icons.chevron_left_rounded),
                              tooltip: 'Önceki Hafta',
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  '${DateFormat('dd.MM.yyyy').format(monday)} – ${DateFormat('dd.MM.yyyy').format(monday.add(const Duration(days: 6)))} Haftası',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                setState(() {
                                  _selectedDate = DateTime.now();
                                  _loading = true;
                                });
                                await _loadWeekMenus(_selectedDate);
                                if (mounted) setState(() => _loading = false);
                              },
                              child: const Text('Bugün'),
                            ),
                            IconButton(
                              onPressed: () => _changeWeek(7),
                              icon: const Icon(Icons.chevron_right_rounded),
                              tooltip: 'Sonraki Hafta',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: List.generate(7, (i) {
                              final d = weekDays[i];
                              final isSel = _dayKey(d) == selectedKey;
                              final hasMenu =
                                  (_weekMenus[_dayKey(d)]?.isNotEmpty ?? false);
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: InkWell(
                                  onTap: () =>
                                      setState(() => _selectedDate = d),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    width: 64,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSel
                                          ? const Color(0xFFEA580C)
                                          : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isSel
                                            ? const Color(0xFFEA580C)
                                            : const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          dayLabels[i],
                                          style: GoogleFonts.inter(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: isSel
                                                ? Colors.white70
                                                : const Color(0xFF64748B),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${d.day}',
                                          style: GoogleFonts.inter(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900,
                                            color: isSel
                                                ? Colors.white
                                                : const Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: hasMenu
                                                ? (isSel
                                                      ? Colors.white
                                                      : const Color(0xFF10B981))
                                                : Colors.transparent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Seçili gün özeti
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEA580C), Color(0xFFF97316)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.restaurant_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${DateFormat('dd.MM.yyyy').format(_selectedDate)} Günün Menüsü',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                totalCaloriesToday > 0
                                    ? 'Toplam Enerji: $totalCaloriesToday kcal'
                                    : '${_periods.length} öğün tanımlı',
                                style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_periods.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.no_meals_rounded,
                            size: 44,
                            color: Color(0xFF94A3B8),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Henüz Yemekhane Öğünü Tanımlanmamış',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Okul yönetimi yemek listesini yayınladığında günlük ve haftalık menülerin burada görünecektir.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, c) {
                        final isWide = c.maxWidth >= 820;
                        final cols = isWide ? 2 : 1;
                        final gap = 14.0;
                        final itemW = (c.maxWidth - gap * (cols - 1)) / cols;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: _periods.map((period) {
                            final pid = period['id'].toString();
                            final items = selectedDayMenus[pid] ?? [];
                            final startT = (period['startTime'] ?? '')
                                .toString()
                                .trim();
                            final endT = (period['endTime'] ?? '')
                                .toString()
                                .trim();
                            return SizedBox(
                              width: itemW,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(9),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF7ED),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.soup_kitchen_rounded,
                                            color: Color(0xFFEA580C),
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            (period['name'] ?? 'Öğün')
                                                .toString(),
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                              color: const Color(0xFF0F172A),
                                            ),
                                          ),
                                        ),
                                        if (startT.isNotEmpty ||
                                            endT.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF1F5F9),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '$startT${endT.isNotEmpty ? " - $endT" : ""}',
                                              style: GoogleFonts.inter(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFF475569),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const Divider(height: 22),
                                    if (items.isEmpty)
                                      Text(
                                        'Bu tarihte bu öğün için menü girişi bulunmuyor.',
                                        style: GoogleFonts.inter(
                                          fontSize: 12.5,
                                          color: const Color(0xFF94A3B8),
                                        ),
                                      )
                                    else
                                      ...items.map((m) {
                                        final cal = (m['calories'] as num?)
                                            ?.toInt();
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.check_circle_rounded,
                                                size: 16,
                                                color: Color(0xFF10B981),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  (m['foodName'] ?? '')
                                                      .toString(),
                                                  style: GoogleFonts.inter(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13.5,
                                                    color: const Color(
                                                      0xFF1E293B,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              if (cal != null && cal > 0)
                                                Text(
                                                  '$cal kcal',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: const Color(
                                                      0xFFEA580C,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        );
                                      }),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ONLİNE İŞLEMLER MERKEZİ (Online Portallar / SSO, Online Sınavlar, Anketler)
// ═══════════════════════════════════════════════════════════════════════════

class StudentOnlineServicesScreen extends StatefulWidget {
  final String institutionId;
  final String studentId;
  final Map<String, dynamic> studentData;
  final String studentSubtitle;
  final int initialTab;

  const StudentOnlineServicesScreen({
    super.key,
    required this.institutionId,
    required this.studentId,
    required this.studentData,
    required this.studentSubtitle,
    this.initialTab = 0,
  });

  @override
  State<StudentOnlineServicesScreen> createState() =>
      _StudentOnlineServicesScreenState();
}

class _StudentOnlineServicesScreenState
    extends State<StudentOnlineServicesScreen> {
  late int _tab;
  bool _loading = true;
  List<Map<String, dynamic>> _portals = [];
  List<Map<String, dynamic>> _onlineExams = [];
  List<Map<String, dynamic>> _surveys = [];

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 2);
    _loadAll();
  }

  String get _classId =>
      (widget.studentData['classId'] ?? '').toString().trim();

  String get _className =>
      (widget.studentData['className'] ?? '').toString().trim();

  String get _studentName {
    final full = (widget.studentData['fullName'] ?? '').toString().trim();
    if (full.isNotEmpty) return full;
    return '${widget.studentData['name'] ?? ''} ${widget.studentData['surname'] ?? ''}'
        .trim();
  }

  String get _studentNo =>
      (widget.studentData['studentNo'] ??
              widget.studentData['studentNumber'] ??
              widget.studentData['no'] ??
              '')
          .toString()
          .trim();

  String get _classLevel {
    final raw =
        (widget.studentData['classLevel'] ??
                widget.studentData['gradeLevel'] ??
                '')
            .toString()
            .trim();
    if (raw.isNotEmpty) return raw;
    final digits = RegExp(r'\d+').firstMatch(_className)?.group(0) ?? '';
    if (digits.startsWith('10') ||
        digits.startsWith('11') ||
        digits.startsWith('12')) {
      return digits.substring(0, 2);
    }
    return digits.isNotEmpty ? digits.substring(0, 1) : '';
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final instIds = {
        widget.institutionId,
        widget.institutionId.toUpperCase(),
        widget.institutionId.toLowerCase(),
      }.where((s) => s.isNotEmpty).toList();

      final activeTermId =
          await TermService().getSelectedTermId() ??
          await TermService().getActiveTermId();

      // Okul dokümanını bul (online_services hem institutionId hem schoolDocId altında olabilir)
      String schoolDocId = widget.institutionId;
      try {
        final sSnap = await FirebaseFirestore.instance
            .collection('schools')
            .where('institutionId', whereIn: instIds)
            .limit(1)
            .get();
        if (sSnap.docs.isNotEmpty) schoolDocId = sSnap.docs.first.id;
      } catch (_) {}

      final res = await Future.wait([
        FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.institutionId)
            .collection('online_services')
            .get()
            .catchError(
              (_) => FirebaseFirestore.instance
                  .collection('schools')
                  .doc(widget.institutionId)
                  .collection('online_services')
                  .limit(0)
                  .get(),
            ),
        schoolDocId != widget.institutionId
            ? FirebaseFirestore.instance
                  .collection('schools')
                  .doc(schoolDocId)
                  .collection('online_services')
                  .get()
                  .catchError(
                    (_) => FirebaseFirestore.instance
                        .collection('schools')
                        .doc(schoolDocId)
                        .collection('online_services')
                        .limit(0)
                        .get(),
                  )
            : Future.value(null),
        FirebaseFirestore.instance
            .collection('trial_exams')
            .where('institutionId', whereIn: instIds)
            .where('isActive', isEqualTo: true)
            .get()
            .catchError(
              (_) => FirebaseFirestore.instance
                  .collection('trial_exams')
                  .limit(0)
                  .get(),
            ),
        FirebaseFirestore.instance
            .collection('surveys')
            .where('institutionId', whereIn: instIds)
            .get()
            .catchError(
              (_) => FirebaseFirestore.instance
                  .collection('surveys')
                  .limit(0)
                  .get(),
            ),
      ]);

      final p1 = res[0] as QuerySnapshot<Map<String, dynamic>>;
      final p2 = res[1] as QuerySnapshot<Map<String, dynamic>>?;
      final trialsSnap = res[2] as QuerySnapshot<Map<String, dynamic>>;
      final surveysSnap = res[3] as QuerySnapshot<Map<String, dynamic>>;

      final mergedPortals = <String, Map<String, dynamic>>{
        'lingokn': {
          'id': 'lingokn',
          'title': 'LinGoKN Dijital Dil Portalı',
          'subtitle':
              'Güvenli tek tık (SSO) ile dil eğitimi platformuna bağlan',
          'type': 'sso',
          'url': '',
          'isActive': true,
        },
      };
      for (final d in p1.docs) {
        if (d.data()['isActive'] != false) {
          mergedPortals[d.id] = {'id': d.id, ...d.data()};
        }
      }
      if (p2 != null) {
        for (final d in p2.docs) {
          if (d.data()['isActive'] != false) {
            mergedPortals[d.id] = {'id': d.id, ...d.data()};
          }
        }
      }
      _portals = mergedPortals.values.toList();

      final grade = _classLevel;
      final exams = <Map<String, dynamic>>[];
      for (final doc in trialsSnap.docs) {
        final d = doc.data();
        final docTerm = d['termId']?.toString().trim();
        if (activeTermId != null &&
            activeTermId.isNotEmpty &&
            docTerm != null &&
            docTerm.isNotEmpty &&
            docTerm != activeTermId) {
          continue;
        }
        final examGrade = (d['classLevel'] ?? d['gradeLevel'] ?? '')
            .toString()
            .trim();
        if (grade.isNotEmpty && examGrade.isNotEmpty && examGrade != grade) {
          continue;
        }
        exams.add({'id': doc.id, ...d});
      }
      exams.sort((a, b) {
        final da = (a['date'] as Timestamp?)?.toDate() ?? DateTime(2000);
        final db = (b['date'] as Timestamp?)?.toDate() ?? DateTime(2000);
        return db.compareTo(da);
      });
      _onlineExams = exams;

      final activeSurveys = <Map<String, dynamic>>[];
      for (final doc in surveysSnap.docs) {
        final d = doc.data();
        if (d['isActive'] == false || d['status'] == 'closed') continue;
        activeSurveys.add({'id': doc.id, ...d});
      }
      _surveys = activeSurveys;
    } catch (e) {
      debugPrint('StudentOnlineServices load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _launchPortal(Map<String, dynamic> portal) async {
    if (portal['id'] == 'lingokn' || portal['type'] == 'sso') {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      try {
        final callable = FirebaseFunctions.instance.httpsCallable(
          'generateSsoToken',
        );
        final result = await callable.call();
        final token = result.data['token'] as String;
        if (mounted) Navigator.pop(context);
        final url = Uri.parse(
          kDebugMode
              ? 'http://localhost:5501/#/auth?token=$token'
              : 'https://lingokn.web.app/#/auth?token=$token',
        );
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (e) {
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('SSO bağlantı hatası: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      return;
    }

    final rawUrl = (portal['url'] ?? '').toString().trim();
    final uri = Uri.tryParse(rawUrl);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Bağlantı açılamadı: $rawUrl')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        institutionId: widget.institutionId,
        title: 'Online İşlemler Merkezi',
        subtitle: widget.studentSubtitle,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text('Online Portallar (${_portals.length})'),
                    selected: _tab == 0,
                    onSelected: (_) => setState(() => _tab = 0),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(
                      'Deneme & Online Sınavlar (${_onlineExams.length})',
                    ),
                    selected: _tab == 1,
                    onSelected: (_) => setState(() => _tab = 1),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('Online Anketler (${_surveys.length})'),
                    selected: _tab == 2,
                    onSelected: (_) => setState(() => _tab = 2),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _tab == 0
                        ? _buildPortalsTab()
                        : (_tab == 1 ? _buildExamsTab() : _buildSurveysTab()),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortalsTab() {
    return Column(
      children: _portals.map((p) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 8,
            ),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE6FFFA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.language_rounded,
                color: Color(0xFF00897B),
              ),
            ),
            title: Text(
              (p['title'] ?? 'Online Hizmet').toString(),
              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              (p['subtitle'] ?? p['url'] ?? '').toString(),
              style: GoogleFonts.inter(fontSize: 12.5),
            ),
            trailing: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
              ),
              onPressed: () => _launchPortal(p),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Bağlan'),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildExamsTab() {
    if (_onlineExams.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          'Sınıf seviyene tanımlı aktif online sınav veya deneme kaydı bulunmuyor.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13.5,
            color: const Color(0xFF64748B),
          ),
        ),
      );
    }

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudentExamStatsScreen(
                    institutionId: widget.institutionId,
                    studentId: widget.studentId,
                    classId: _classId,
                    classLevel: _classLevel,
                    studentName: _studentName,
                    schoolNumber: _studentNo,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.bar_chart_rounded, size: 18),
            label: const Text('Tüm Sınav Sonuç Karnelerim'),
          ),
        ),
        const SizedBox(height: 10),
        ..._onlineExams.map((exam) {
          final dt = (exam['date'] as Timestamp?)?.toDate();
          final onlineUrl = (exam['onlineExamUrl'] ?? exam['examUrl'] ?? '')
              .toString()
              .trim();
          final hasResults =
              exam['results'] is List && (exam['results'] as List).isNotEmpty;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.quiz_rounded,
                    color: Color(0xFF4F46E5),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (exam['name'] ?? exam['examName'] ?? 'Deneme Sınavı')
                            .toString(),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${dt != null ? DateFormat('dd.MM.yyyy').format(dt) : "Tarih belirtilmedi"}  •  ${hasResults ? "Sonuçlar Açıklandı" : "Planlandı / Aktif"}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                if (onlineUrl.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () async {
                      final uri = Uri.tryParse(onlineUrl);
                      if (uri != null) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Sınava Gir'),
                  )
                else
                  FilledButton.tonal(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StudentExamStatsScreen(
                            institutionId: widget.institutionId,
                            studentId: widget.studentId,
                            classId: _classId,
                            classLevel: _classLevel,
                            studentName: _studentName,
                            schoolNumber: _studentNo,
                          ),
                        ),
                      );
                    },
                    child: Text(hasResults ? 'Karnemi Gör' : 'Detay'),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSurveysTab() {
    if (_surveys.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          'Şu anda yanıt bekleyen aktif anket veya form bulunmuyor.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13.5,
            color: const Color(0xFF64748B),
          ),
        ),
      );
    }

    return Column(
      children: _surveys.map((s) {
        final link = (s['externalUrl'] ?? s['url'] ?? '').toString().trim();
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.poll_rounded,
                color: Color(0xFF0284C7),
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (s['title'] ?? 'Anket').toString(),
                      style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                    ),
                    if ((s['description'] ?? '').toString().isNotEmpty)
                      Text(
                        s['description'].toString(),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                  ],
                ),
              ),
              if (link.isNotEmpty)
                FilledButton(
                  onPressed: () async {
                    final uri = Uri.tryParse(link);
                    if (uri != null) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  child: const Text('Katıl'),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
