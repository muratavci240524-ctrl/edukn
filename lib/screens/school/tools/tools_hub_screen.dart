import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../../widgets/edukn_app_bar.dart';
import '../../../services/user_permission_service.dart';
import 'seating_plan/seating_plan_hub_screen.dart';
import 'student_grouping/student_grouping_hub_screen.dart';
import 'random_student_picker/random_student_picker_hub_screen.dart';
import 'quick_performance_tracker/quick_performance_tracker_hub_screen.dart';
import 'classroom_timer/classroom_timer_hub_screen.dart';
import 'noise_meter/noise_meter_hub_screen.dart';
import 'butterfly_exam/butterfly_exam_hub_screen.dart';
import '../notes/personal_notes_screen.dart';

class ToolsHubScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final int initialCategoryIndex;
  final bool isTeacher;
  final String? teacherId;
  final List<String>? allowedClassIds;

  const ToolsHubScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.initialCategoryIndex = 0,
    this.isTeacher = false,
    this.teacherId,
    this.allowedClassIds,
  }) : super(key: key);

  @override
  State<ToolsHubScreen> createState() => _ToolsHubScreenState();
}

class _ToolsHubScreenState extends State<ToolsHubScreen> with SingleTickerProviderStateMixin {
  late int _selectedCategoryIndex;
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  Map<String, dynamic>? _userData;
  List<_OnlineServiceItem> _onlineServices = [];
  bool _loadingServices = true;

  static const List<_ToolCategory> _staticCategories = [
    _ToolCategory(
      title: 'Sınıf İçi Yönetim ve Etkileşim Araçları',
      shortTitle: 'Sınıf Yönetim',
      icon: Icons.groups_rounded,
      color: Color(0xFF5C6BC0),
      gradient: [Color(0xFF5C6BC0), Color(0xFF3949AB)],
      tools: [
        _ToolItem(
          title: 'Sınıf Oturma Planı Oluşturucu',
          subtitle: 'Boy, cinsiyet veya özel durum parametrelerine göre otomatik yerleştirme',
          icon: Icons.grid_view_rounded,
          color: Color(0xFF5C6BC0),
        ),
        _ToolItem(
          title: 'Homojen/Rastgele Gruplama',
          subtitle: 'Belirlenen kişi sayısına göre sınıfı çalışma gruplarına bölme',
          icon: Icons.group_work_rounded,
          color: Color(0xFF7E57C2),
        ),
        _ToolItem(
          title: 'Rastgele Öğrenci Seçici',
          subtitle: 'Görsel animasyonla derste söz hakkı verilecek öğrenci seçme',
          icon: Icons.casino_rounded,
          color: Color(0xFFAB47BC),
        ),
        _ToolItem(
          title: 'Hızlı Performans Takibi',
          subtitle: 'Tek tıkla artı/eksi vererek günlük performans değerlendirme',
          icon: Icons.trending_up_rounded,
          color: Color(0xFF26A69A),
        ),
        _ToolItem(
          title: 'Sınıf Zamanlayıcısı / Kronometre',
          subtitle: 'Deneme sınavları veya etkinlikler için tam ekran geri sayım',
          icon: Icons.timer_rounded,
          color: Color(0xFFEF5350),
        ),
        _ToolItem(
          title: 'Sınıf Termometresi (Gürültü Ölçer)',
          subtitle: 'Mikrofon üzerinden desibel ölçüm ve görsel uyarı sistemi',
          icon: Icons.mic_rounded,
          color: Color(0xFFFF7043),
        ),
        _ToolItem(
          title: 'Notlarım',
          subtitle: 'Kişisel ve ders içi notlarınızı kaydedin ve yönetin',
          icon: Icons.edit_note_rounded,
          color: Color(0xFF8E24AA),
        ),
      ],
    ),
    _ToolCategory(
      title: 'Sınav ve Gözetmenlik Araçları',
      shortTitle: 'Sınav',
      icon: Icons.assignment_rounded,
      color: Color(0xFFEF5350),
      gradient: [Color(0xFFEF5350), Color(0xFFE53935)],
      tools: [
        _ToolItem(
          title: 'Kelebek Sınav Dağıtıcı',
          subtitle: 'Farklı seviyedeki öğrencileri matris algoritmasıyla sıraya dizme',
          icon: Icons.view_module_rounded,
          color: Color(0xFFEF5350),
        ),
        _ToolItem(
          title: 'Sınava Özel Oturma Planı ve Kapı Listesi',
          subtitle: 'Salon bazlı şablonlara oturtup PDF çıktı üretme',
          icon: Icons.door_front_door_rounded,
          color: Color(0xFFEC407A),
        ),
        _ToolItem(
          title: 'Optik Form Kodlama Kılavuzu Jeneratörü',
          subtitle: 'Öğrenci bilgilerinin optik forma doldurulmuş halini PDF olarak üretme',
          icon: Icons.qr_code_scanner_rounded,
          color: Color(0xFFAB47BC),
        ),
      ],
    ),
    _ToolCategory(
      title: 'Akademik Ölçme ve Başarı Takibi',
      shortTitle: 'Akademik',
      icon: Icons.analytics_rounded,
      color: Color(0xFF66BB6A),
      gradient: [Color(0xFF66BB6A), Color(0xFF43A047)],
      tools: [
        _ToolItem(
          title: 'LGS / YKS Hedef Simülatörü',
          subtitle: 'Deneme netlerinden puan ve yüzdelik dilim hesaplama',
          icon: Icons.calculate_rounded,
          color: Color(0xFF66BB6A),
        ),
        _ToolItem(
          title: 'Kazanım Isı Haritası (Heat Map)',
          subtitle: 'Deneme sonuçlarını renk kodlamasıyla görsel analiz tablosu',
          icon: Icons.grid_on_rounded,
          color: Color(0xFFFFA726),
        ),
        _ToolItem(
          title: 'Hızlı Test Notu Dönüştürücü',
          subtitle: 'Soru sayısı ve puan değerine göre 100 üzerinden not hesaplama',
          icon: Icons.speed_rounded,
          color: Color(0xFF42A5F5),
        ),
        _ToolItem(
          title: 'Devamsızlık Radar Paneli',
          subtitle: 'Kritik eşiğe yaklaşan öğrencileri otomatik filtreleyen uyarı listesi',
          icon: Icons.radar_rounded,
          color: Color(0xFFEF5350),
        ),
      ],
    ),
    _ToolCategory(
      title: 'Evrak, Liste ve Şablon Otomasyonları',
      shortTitle: 'Evrak',
      icon: Icons.description_rounded,
      color: Color(0xFFFFA726),
      gradient: [Color(0xFFFFA726), Color(0xFFFB8C00)],
      tools: [
        _ToolItem(
          title: 'Dinamik PDF Liste Jeneratörü',
          subtitle: 'Filtreler ile yoklama fişi, imza sirküsü veya gezi listesi şablonları',
          icon: Icons.picture_as_pdf_rounded,
          color: Color(0xFFEF5350),
        ),
        _ToolItem(
          title: 'Toplu Veli İzin Belgesi Üretici',
          subtitle: 'Standart dilekçe şablonundaki değişkenlere basarak toplu PDF üretme',
          icon: Icons.family_restroom_rounded,
          color: Color(0xFF5C6BC0),
        ),
        _ToolItem(
          title: 'Parametrik Tutanak Hazırlayıcı',
          subtitle: 'Disiplin, kaza veya nöbet raporu gibi resmi PDF evrak hazırlama',
          icon: Icons.gavel_rounded,
          color: Color(0xFF78909C),
        ),
        _ToolItem(
          title: 'QR / Barkod ve Yaka Kartı Üretici',
          subtitle: 'Öğrenci listesinden toplu QR kod üretip A4 kağıda grid yerleştirme',
          icon: Icons.qr_code_rounded,
          color: Color(0xFF26A69A),
        ),
        _ToolItem(
          title: 'Çakışmasız Nöbet Dağıtıcı',
          subtitle: 'Öğretmenlerin boş günleriyle nöbet alanlarını matris eşleştirme',
          icon: Icons.calendar_month_rounded,
          color: Color(0xFFAB47BC),
        ),
      ],
    ),
  ];

  // Online Hizmetler category is built dynamically from Firestore
  static const _onlineHizmetlerMeta = _ToolCategory(
    title: 'Online Hizmetler',
    shortTitle: 'Online',
    icon: Icons.language_rounded,
    color: Color(0xFF00897B),
    gradient: [Color(0xFF00897B), Color(0xFF00695C)],
    tools: [], // populated at runtime
  );

  @override
  void initState() {
    super.initState();
    _selectedCategoryIndex = widget.isTeacher ? 0 : widget.initialCategoryIndex;
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _animationController.forward();
    _loadUserAndServices();
  }

  Future<void> _loadUserAndServices() async {
    _userData = await UserPermissionService.loadUserData();
    await _loadOnlineServices();
  }

  Future<void> _loadOnlineServices() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.institutionId)
          .collection('online_services')
          .orderBy('order')
          .get();

      final services = snap.docs.map((doc) {
        final data = doc.data();
        return _OnlineServiceItem(
          id: doc.id,
          title: data['title'] ?? '',
          subtitle: data['subtitle'] ?? '',
          url: data['url'] ?? '',
          iconName: data['icon'] ?? 'language',
          colorHex: data['color'] ?? '00897B',
          type: data['type'] ?? 'web', // 'web', 'sso', 'app'
          order: data['order'] ?? 0,
          isActive: data['isActive'] ?? true,
        );
      }).where((s) => s.isActive).toList();

      // Always add LinGoKN as the first item (built-in)
      final lingoknService = _OnlineServiceItem(
        id: 'lingokn',
        title: 'LinGoKN Portalı',
        subtitle: 'Dil eğitimi platformuna güvenli SSO geçiş',
        url: '',
        iconName: 'translate',
        colorHex: '00897B',
        type: 'sso',
        order: -1,
        isActive: true,
      );

      if (mounted) {
        setState(() {
          _onlineServices = [lingoknService, ...services];
          _loadingServices = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingServices = false);
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  int get _totalCategoryCount => widget.isTeacher ? 1 : (_staticCategories.length + 1); // +1 for Online Hizmetler

  _ToolCategory _getCategoryAt(int index) {
    if (widget.isTeacher) return _staticCategories[0];
    if (index < _staticCategories.length) return _staticCategories[index];
    return _onlineHizmetlerMeta;
  }

  void _switchCategory(int index) {
    if (widget.isTeacher) return;
    if (index == _selectedCategoryIndex) return;
    _animationController.reverse().then((_) {
      setState(() => _selectedCategoryIndex = index);
      _animationController.forward();
    });
  }

  bool get _isAdmin {
    final role = (_userData?['role'] as String?)?.toLowerCase() ?? '';
    return ['super_admin', 'admin', 'manager', 'genel_mudur'].contains(role);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: EduknAppBar(
        title: widget.isTeacher ? 'Sınıf İçi Yönetim Araçları' : 'Araçlar',
        subtitle: widget.schoolTypeName,
      ),
      body: Column(
        children: [
          if (!widget.isTeacher) _buildCategoryTabs(isMobile),
          Expanded(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: _selectedCategoryIndex < _staticCategories.length
                  ? _buildToolsList(isMobile)
                  : _buildOnlineServicesList(isMobile),
            ),
          ),
        ],
      ),
      floatingActionButton: (_selectedCategoryIndex >= _staticCategories.length && _isAdmin)
          ? FloatingActionButton.extended(
              onPressed: () => _showAddServiceDialog(),
              backgroundColor: const Color(0xFF00897B),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text('Hizmet Ekle', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
            )
          : null,
    );
  }

  Widget _buildCategoryTabs(bool isMobile) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: List.generate(_totalCategoryCount, (index) {
            final cat = _getCategoryAt(index);
            final isSelected = _selectedCategoryIndex == index;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _switchCategory(index),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 14 : 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? LinearGradient(colors: cat.gradient)
                          : null,
                      color: isSelected ? null : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: cat.color.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          cat.icon,
                          size: 20,
                          color: isSelected ? Colors.white : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          cat.shortTitle,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected ? Colors.white : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildToolsList(bool isMobile) {
    final category = _staticCategories[_selectedCategoryIndex];
    final crossAxisCount = isMobile ? 1 : (MediaQuery.of(context).size.width > 1200 ? 3 : 2);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Category header
        SliverToBoxAdapter(
          child: _buildCategoryHeader(category, isMobile),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        // Tools grid
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: isMobile ? 2.65 : 2.8,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final tool = category.tools[index];
                return _ToolCard(
                  tool: tool,
                  index: index,
                  onTap: () => _onToolTap(tool),
                );
              },
              childCount: category.tools.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOnlineServicesList(bool isMobile) {
    final category = _onlineHizmetlerMeta;
    final crossAxisCount = isMobile ? 1 : (MediaQuery.of(context).size.width > 1200 ? 3 : 2);

    if (_loadingServices) {
      return const Center(child: CircularProgressIndicator());
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _buildCategoryHeader(category, isMobile),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        if (_onlineServices.isEmpty)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(
                      'Henüz online hizmet eklenmemiş',
                      style: GoogleFonts.inter(fontSize: 16, color: Colors.grey.shade500),
                    ),
                    if (_isAdmin) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Sağ alttaki butona tıklayarak yeni hizmet ekleyebilirsiniz',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: isMobile ? 2.65 : 2.8,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final service = _onlineServices[index];
                  return _OnlineServiceCard(
                    service: service,
                    index: index,
                    isAdmin: _isAdmin,
                    onTap: () => _onServiceTap(service),
                    onEdit: _isAdmin ? () => _showEditServiceDialog(service) : null,
                    onDelete: _isAdmin ? () => _deleteService(service) : null,
                  );
                },
                childCount: _onlineServices.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryHeader(_ToolCategory category, bool isMobile) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: category.gradient),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: category.color.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(category.icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.title,
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 17 : 20,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedCategoryIndex < _staticCategories.length
                      ? '${category.tools.length} araç mevcut'
                      : '${_onlineServices.length} hizmet mevcut',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onToolTap(_ToolItem tool) {
    if (tool.title == 'Sınıf Oturma Planı Oluşturucu') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SeatingPlanHubScreen(
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
            schoolTypeName: widget.schoolTypeName,
            isTeacher: widget.isTeacher,
            teacherId: widget.teacherId,
            allowedClassIds: widget.allowedClassIds,
          ),
        ),
      );
      return;
    } else if (tool.title == 'Homojen/Rastgele Gruplama') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StudentGroupingHubScreen(
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
            schoolTypeName: widget.schoolTypeName,
            isTeacher: widget.isTeacher,
            teacherId: widget.teacherId,
            allowedClassIds: widget.allowedClassIds,
          ),
        ),
      );
      return;
    } else if (tool.title == 'Rastgele Öğrenci Seçici') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RandomStudentPickerHubScreen(
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
            schoolTypeName: widget.schoolTypeName,
            isTeacher: widget.isTeacher,
            teacherId: widget.teacherId,
            allowedClassIds: widget.allowedClassIds,
          ),
        ),
      );
      return;
    } else if (tool.title == 'Hızlı Performans Takibi') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuickPerformanceTrackerHubScreen(
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
            schoolTypeName: widget.schoolTypeName,
            isTeacher: widget.isTeacher,
            teacherId: widget.teacherId,
            allowedClassIds: widget.allowedClassIds,
          ),
        ),
      );
      return;
    } else if (tool.title == 'Notlarım') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PersonalNotesScreen()),
      );
      return;
    } else if (tool.title == 'Sınıf Zamanlayıcısı / Kronometre') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ClassroomTimerHubScreen(
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
            schoolTypeName: widget.schoolTypeName,
          ),
        ),
      );
      return;
    } else if (tool.title == 'Sınıf Termometresi (Gürültü Ölçer)') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NoiseMeterHubScreen(
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
            schoolTypeName: widget.schoolTypeName,
          ),
        ),
      );
      return;
    } else if (tool.title == 'Kelebek Sınav Dağıtıcı' ||
        tool.title == 'Sınava Özel Oturma Planı ve Kapı Listesi') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ButterflyExamHubScreen(
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
            schoolTypeName: widget.schoolTypeName,
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.construction_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${tool.title} — Geliştirme aşamasında',
                style: GoogleFonts.inter(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF5C6BC0),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onServiceTap(_OnlineServiceItem service) async {
    if (service.type == 'sso' && service.id == 'lingokn') {
      await _launchLingoknSso();
    } else if (service.url.isNotEmpty) {
      final uri = Uri.tryParse(service.url);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Bağlantı açılamadı: ${service.url}'),
              backgroundColor: Colors.red.shade400,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    }
  }

  Future<void> _launchLingoknSso() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('LinGoKN Portalına güvenli yönlendirme yapılıyor...',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('generateSsoToken');
      final result = await callable.call();
      final token = result.data['token'] as String;

      if (mounted) Navigator.pop(context);

      final url = Uri.parse(kDebugMode
          ? 'http://localhost:5501/#/auth?token=$token'
          : 'https://lingokn.web.app/#/auth?token=$token');

      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('LinGoKN adresi açılamadı.');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Bağlantı Hatası'),
            content: Text('LinGoKN portalına bağlanırken bir sorun oluştu: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
      }
    }
  }

  // ─── CRUD: Online Services ──────────────────────────────────

  void _showAddServiceDialog() {
    _showServiceFormDialog(null);
  }

  void _showEditServiceDialog(_OnlineServiceItem service) {
    if (service.id == 'lingokn') return; // LinGoKN is built-in, cannot edit
    _showServiceFormDialog(service);
  }

  void _showServiceFormDialog(_OnlineServiceItem? existing) {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final subtitleController = TextEditingController(text: existing?.subtitle ?? '');
    final urlController = TextEditingController(text: existing?.url ?? '');
    String selectedIcon = existing?.iconName ?? 'language';
    String selectedColor = existing?.colorHex ?? '00897B';

    final availableIcons = {
      'language': Icons.language_rounded,
      'translate': Icons.translate_rounded,
      'school': Icons.school_rounded,
      'science': Icons.science_rounded,
      'book': Icons.menu_book_rounded,
      'video': Icons.video_library_rounded,
      'music': Icons.music_note_rounded,
      'code': Icons.code_rounded,
      'calculate': Icons.calculate_rounded,
      'palette': Icons.palette_rounded,
      'sports': Icons.sports_soccer_rounded,
      'psychology': Icons.psychology_rounded,
      'public': Icons.public_rounded,
      'cloud': Icons.cloud_rounded,
      'link': Icons.link_rounded,
      'quiz': Icons.quiz_rounded,
      'chat': Icons.chat_rounded,
      'map': Icons.map_rounded,
    };

    final availableColors = {
      '00897B': const Color(0xFF00897B), // Teal
      '5C6BC0': const Color(0xFF5C6BC0), // Indigo
      'EF5350': const Color(0xFFEF5350), // Red
      '66BB6A': const Color(0xFF66BB6A), // Green
      'FFA726': const Color(0xFFFFA726), // Orange
      '42A5F5': const Color(0xFF42A5F5), // Blue
      'AB47BC': const Color(0xFFAB47BC), // Purple
      'EC407A': const Color(0xFFEC407A), // Pink
      '78909C': const Color(0xFF78909C), // Blue Grey
      'FF7043': const Color(0xFFFF7043), // Deep Orange
    };

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00897B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  existing == null ? Icons.add_link_rounded : Icons.edit_rounded,
                  color: const Color(0xFF00897B),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                existing == null ? 'Yeni Online Hizmet Ekle' : 'Hizmeti Düzenle',
                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: 'Hizmet Adı *',
                      hintText: 'Örn: EBA, Morpa Kampüs, Khan Academy',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.title_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: subtitleController,
                    decoration: InputDecoration(
                      labelText: 'Açıklama',
                      hintText: 'Kısa bir açıklama yazın',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.description_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: urlController,
                    decoration: InputDecoration(
                      labelText: 'Web Adresi (URL) *',
                      hintText: 'https://www.example.com',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.link_rounded),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 20),
                  Text('İkon Seçin', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: availableIcons.entries.map((entry) {
                      final isSelected = selectedIcon == entry.key;
                      return InkWell(
                        onTap: () => setDialogState(() => selectedIcon = entry.key),
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF00897B).withOpacity(0.15)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF00897B) : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            entry.value,
                            size: 22,
                            color: isSelected ? const Color(0xFF00897B) : Colors.grey.shade600,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Text('Renk Seçin', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: availableColors.entries.map((entry) {
                      final isSelected = selectedColor == entry.key;
                      return InkWell(
                        onTap: () => setDialogState(() => selectedColor = entry.key),
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: entry.value,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: isSelected
                                ? [BoxShadow(color: entry.value.withOpacity(0.5), blurRadius: 8)]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('İptal', style: GoogleFonts.inter(color: Colors.grey.shade600)),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final title = titleController.text.trim();
                final url = urlController.text.trim();
                if (title.isEmpty || url.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Hizmet adı ve URL zorunludur')),
                  );
                  return;
                }

                Navigator.pop(context);

                final data = {
                  'title': title,
                  'subtitle': subtitleController.text.trim(),
                  'url': url,
                  'icon': selectedIcon,
                  'color': selectedColor,
                  'type': 'web',
                  'order': existing?.order ?? _onlineServices.length,
                  'isActive': true,
                  'updatedAt': FieldValue.serverTimestamp(),
                };

                final collection = FirebaseFirestore.instance
                    .collection('schools')
                    .doc(widget.institutionId)
                    .collection('online_services');

                if (existing != null) {
                  await collection.doc(existing.id).update(data);
                } else {
                  data['createdAt'] = FieldValue.serverTimestamp();
                  await collection.add(data);
                }

                await _loadOnlineServices();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(existing == null
                          ? '✅ "$title" başarıyla eklendi'
                          : '✅ "$title" güncellendi'),
                      backgroundColor: const Color(0xFF00897B),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      margin: const EdgeInsets.all(16),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              icon: Icon(existing == null ? Icons.add_rounded : Icons.save_rounded, color: Colors.white, size: 18),
              label: Text(
                existing == null ? 'Ekle' : 'Kaydet',
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteService(_OnlineServiceItem service) async {
    if (service.id == 'lingokn') return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hizmeti Sil'),
        content: Text('"${service.title}" hizmetini silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.institutionId)
          .collection('online_services')
          .doc(service.id)
          .delete();

      await _loadOnlineServices();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🗑️ "${service.title}" silindi'),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }
}

// ─── Tool Card Widget ──────────────────────────────────────────
class _ToolCard extends StatefulWidget {
  final _ToolItem tool;
  final int index;
  final VoidCallback onTap;

  const _ToolCard({
    required this.tool,
    required this.index,
    required this.onTap,
  });

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late final AnimationController _entryController;
  late final Animation<double> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300 + (widget.index * 80)),
    );
    _slideAnimation = Tween<double>(begin: 30, end: 0).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOut),
    );
    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _entryController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: child,
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            transform: Matrix4.identity()..scale(_isHovered ? 1.02 : 1.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isHovered
                    ? widget.tool.color.withOpacity(0.4)
                    : Colors.grey.shade200,
                width: _isHovered ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isHovered
                      ? widget.tool.color.withOpacity(0.12)
                      : Colors.black.withOpacity(0.04),
                  blurRadius: _isHovered ? 16 : 8,
                  offset: Offset(0, _isHovered ? 6 : 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: widget.tool.color.withOpacity(_isHovered ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.tool.icon,
                      color: widget.tool.color,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.tool.title,
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A1A2E),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.tool.subtitle,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w400,
                            color: Colors.grey.shade500,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _isHovered
                          ? widget.tool.color.withOpacity(0.1)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 13,
                      color: _isHovered
                          ? widget.tool.color
                          : Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Online Service Card Widget ────────────────────────────────
class _OnlineServiceCard extends StatefulWidget {
  final _OnlineServiceItem service;
  final int index;
  final bool isAdmin;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _OnlineServiceCard({
    required this.service,
    required this.index,
    required this.isAdmin,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<_OnlineServiceCard> createState() => _OnlineServiceCardState();
}

class _OnlineServiceCardState extends State<_OnlineServiceCard> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late final AnimationController _entryController;
  late final Animation<double> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  static final Map<String, IconData> _iconMap = {
    'language': Icons.language_rounded,
    'translate': Icons.translate_rounded,
    'school': Icons.school_rounded,
    'science': Icons.science_rounded,
    'book': Icons.menu_book_rounded,
    'video': Icons.video_library_rounded,
    'music': Icons.music_note_rounded,
    'code': Icons.code_rounded,
    'calculate': Icons.calculate_rounded,
    'palette': Icons.palette_rounded,
    'sports': Icons.sports_soccer_rounded,
    'psychology': Icons.psychology_rounded,
    'public': Icons.public_rounded,
    'cloud': Icons.cloud_rounded,
    'link': Icons.link_rounded,
    'quiz': Icons.quiz_rounded,
    'chat': Icons.chat_rounded,
    'map': Icons.map_rounded,
  };

  IconData get _serviceIcon => _iconMap[widget.service.iconName] ?? Icons.language_rounded;

  Color get _serviceColor {
    try {
      return Color(int.parse('FF${widget.service.colorHex}', radix: 16));
    } catch (_) {
      return const Color(0xFF00897B);
    }
  }

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300 + (widget.index * 80)),
    );
    _slideAnimation = Tween<double>(begin: 30, end: 0).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOut),
    );
    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _serviceColor;

    return AnimatedBuilder(
      animation: _entryController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: child,
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            transform: Matrix4.identity()..scale(_isHovered ? 1.02 : 1.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isHovered ? color.withOpacity(0.4) : Colors.grey.shade200,
                width: _isHovered ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isHovered ? color.withOpacity(0.12) : Colors.black.withOpacity(0.04),
                  blurRadius: _isHovered ? 16 : 8,
                  offset: Offset(0, _isHovered ? 6 : 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(_isHovered ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_serviceIcon, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.service.title,
                                style: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1A1A2E),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.service.type == 'sso')
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.amber.shade200),
                                ),
                                child: Text(
                                  'SSO',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.amber.shade800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (widget.service.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.service.subtitle,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w400,
                              color: Colors.grey.shade500,
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (widget.isAdmin && widget.service.id != 'lingokn') ...[
                    InkWell(
                      onTap: widget.onEdit,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.edit_rounded, size: 16, color: Colors.grey.shade400),
                      ),
                    ),
                    InkWell(
                      onTap: widget.onDelete,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.delete_rounded, size: 16, color: Colors.red.shade300),
                      ),
                    ),
                  ] else
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _isHovered ? color.withOpacity(0.1) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.open_in_new_rounded,
                        size: 14,
                        color: _isHovered ? color : Colors.grey.shade400,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Data Models ──────────────────────────────────────────────
class _ToolCategory {
  final String title;
  final String shortTitle;
  final IconData icon;
  final Color color;
  final List<Color> gradient;
  final List<_ToolItem> tools;

  const _ToolCategory({
    required this.title,
    required this.shortTitle,
    required this.icon,
    required this.color,
    required this.gradient,
    required this.tools,
  });
}

class _ToolItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _ToolItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class _OnlineServiceItem {
  final String id;
  final String title;
  final String subtitle;
  final String url;
  final String iconName;
  final String colorHex;
  final String type;
  final int order;
  final bool isActive;

  const _OnlineServiceItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.url,
    required this.iconName,
    required this.colorHex,
    required this.type,
    required this.order,
    required this.isActive,
  });
}
