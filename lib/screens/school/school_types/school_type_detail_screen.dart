import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:intl/intl.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edukn/services/user_permission_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../../../services/term_service.dart';
import '../../../widgets/haberlesme_hub_widget.dart';
import '../../../widgets/read_only_permission_wrapper.dart';
import '../../../widgets/web_qr_login_scanner_sheet.dart';
import '../student_registration_screen.dart';
import '../registration/pre_registration_screen.dart';
import 'student_promotion_transfer_screens.dart';
import 'chat/chat_screen.dart';
import '../../hr/staff/staff_list_screen.dart';
import '../class_management_screen.dart';
import '../lesson_management_screen.dart';
import '../classroom_management_screen.dart';
import '../work_calendar_screen.dart';
import '../lesson_hours_screen.dart';
import '../class_schedule_screen.dart';
import '../class_schedule_view_screen.dart';
import '../teacher_schedule_view_screen.dart';
import '../curriculum_tracking_screen.dart';
import '../user_profile_screen.dart';
import '../attendance_operations_screen.dart';
import '../survey/survey_list_screen.dart';
import '../assessment/trial_exam_list_screen.dart';
import '../assessment/active_exam_list_screen.dart';
import '../assessment/assessment_definitions_screen.dart';
import '../assessment/assessment_reports_screen.dart';
import '../assessment/error_booklet/error_booklet_dashboard_screen.dart';
import '../assessment/personalized_book/personalized_book_dashboard_screen.dart';
import '../assessment/central_school_reports_screen.dart';
import '../assessment/question_pool/question_pool_screen.dart';
import '../store/school_store_management_screen.dart';
import '../../store/store_shop_screen.dart';
import '../../../services/school_module_guard.dart';
import '../../portfolio/portfolio_screen.dart';
import '../tasks/todo_list_screen.dart';
import '../tasks/substitute_teacher_list_screen.dart';
import '../tasks/duty_management_screen.dart';
import '../tasks/field_trip_list_screen.dart';
import '../tasks/project_assignments/project_assignment_list_screen.dart';
import '../homework/homework_operations_screen.dart';
import '../book_management_screen.dart';
import '../etut_process_screen.dart';
import '../activity/activity_list_screen.dart';
import '../../../../widgets/recipient_selector_field.dart';
import '../../../../widgets/edukn_logo.dart';
import '../../../../widgets/premium_app_bar.dart';
import '../profile_settings_screen.dart';
import '../../teacher/teacher_qr_scan_screen.dart';

import '../hr/school_type_leave_management_screen.dart';
import '../dynamic_groups/course_group_management_screen.dart';
import '../../../models/school/dynamic_course_group_model.dart';
import '../../../../widgets/stylish_bottom_nav.dart';
import '../guidance/guidance_interview_screen.dart';
import '../guidance/mentor_studies_hub_screen.dart';
import '../../guidance/guidance_test_catalog_screen.dart';
import '../../support_services/cafeteria/cafeteria_screen.dart';
import '../../support_services/transportation/transportation_screen.dart';
import '../../support_services/health/health_screen.dart';
import '../../support_services/library/library_screen.dart';
import '../../support_services/cleaning/cleaning_screen.dart';
import '../../support_services/inventory/inventory_screen.dart';
import '../../support_services/inventory/teacher_material_requests_screen.dart';
import '../../guidance/reports/development_report_management_screen.dart';
import '../guidance/demand/demand_dashboard_screen.dart';
import '../notes/personal_notes_screen.dart';
import '../assessment/agm/screens/agm_dashboard_screen.dart';
import 'package:edukn/widgets/safe_stream_builder.dart';
import '../tools/tools_hub_screen.dart';
import '../../support_services/security/security_gate_screen.dart';
import '../daily_report/daily_report_screen.dart';
import '../settings/app_settings_screen.dart';
import '../../../models/school/daily_report_models.dart';

class SchoolTypeDetailScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const SchoolTypeDetailScreen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<SchoolTypeDetailScreen> createState() => _SchoolTypeDetailScreenState();
}

class _SchoolTypeDetailScreenState extends State<SchoolTypeDetailScreen> {
  int _currentIndex = 1;
  Map<String, dynamic>? _userData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final data = await UserPermissionService.loadUserData();

    if (data != null) {
      final role = (data['role'] as String?)?.toLowerCase();
      if (role != 'admin' && role != 'genel_mudur') {
        final schoolTypes = data['schoolTypes'] as List<dynamic>?;
        if (schoolTypes != null && schoolTypes.isNotEmpty) {
          if (!schoolTypes.contains(widget.schoolTypeId)) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Bu okul türüne erişim yetkiniz bulunmamaktadır.',
                  ),
                  backgroundColor: Colors.grey.shade900,
                ),
              );
              Navigator.of(context).pushReplacementNamed('/school-dashboard');
            }
            return;
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _userData = data;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const EduKnLoader(size: 80),
              const SizedBox(height: 24),
              const EduKnLogo(type: EduKnLogoType.noSlogan, iconSize: 32),
            ],
          ),
        ),
      );
    }

    final pages = [
      _CommunicationTab(
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        institutionId: widget.institutionId,
        userData: _userData,
      ),
      _DashboardTab(
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        institutionId: widget.institutionId,
        userData: _userData,
      ),
      _OperationsTab(
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        institutionId: widget.institutionId,
        userData: _userData,
      ),
    ];

    return Scaffold(
      body: Column(
        children: [
          PremiumAppBar(
            schoolTypeId: widget.schoolTypeId,
            schoolTypeName: widget.schoolTypeName,
            institutionId: widget.institutionId,
            subtitle: _currentIndex == 0
                ? 'Haberleşme'
                : _currentIndex == 1
                ? 'Dashboard'
                : 'İşlemler Merkezi',
            showSearch: true,
            showBackButton: true,
          ),
          Expanded(
            child: Stack(
              children: [
                const Positioned.fill(
                  child: ColoredBox(color: Color(0xFFF8FAFC)),
                ),
                const Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: DoodlePainter()),
                  ),
                ),
                IndexedStack(index: _currentIndex, children: pages),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StylishBottomNav(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
          Container(
            color: Colors.white,
            width: double.infinity,
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 4,
              bottom: 2,
            ), // Sadece üst ve alt ince boşluk
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '© 2026 eduKN.',
                  style: TextStyle(
                    color: Colors.blueGrey.shade400,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildFooterLink('Destek'),
                    const SizedBox(width: 16),
                    _buildFooterLink('Gizlilik'),
                    const SizedBox(width: 16),
                    _buildFooterLink('Şartlar'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterLink(String label) {
    return InkWell(
      onTap: () {},
      child: Text(
        label,
        style: TextStyle(
          color: Colors.blueGrey.shade400,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ============== HABERLEŞME TAB ==============
class _CommunicationTab extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;
  final Map<String, dynamic>? userData;

  const _CommunicationTab({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
    this.userData,
  }) : super(key: key);

  @override
  State<_CommunicationTab> createState() => _CommunicationTabState();
}

class _CommunicationTabState extends State<_CommunicationTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  bool get isTeacher {
    final role = (widget.userData?['role'] as String?)?.toLowerCase();
    return role == 'ogretmen' || role == 'öğretmen';
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HaberlesmeHubWidget(
      institutionId: widget.institutionId,
      schoolTypeId: widget.schoolTypeId,
      schoolTypeName: widget.schoolTypeName,
      userData: widget.userData,
      isTeacher: isTeacher,
    );
  }
}

// ============== İŞLEMLER TAB ==============
class _OperationsTab extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;
  final Map<String, dynamic>? userData;

  const _OperationsTab({
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
    this.userData,
  });

  @override
  State<_OperationsTab> createState() => _OperationsTabState();
}

class _OperationsTabState extends State<_OperationsTab> {
  // Seçili kategoriyi takip et (Üst bar için)
  String _selectedCategory = 'Tümü';

  // Dönem bilgileri
  List<Map<String, dynamic>> _terms = [];
  Map<String, dynamic>? _activeTerm;
  Map<String, dynamic>? _selectedTerm;

  Map<String, dynamic>? userData;
  Map<String, dynamic>? schoolData;

  // Arama ve Overlay Kontrol Değişkenleri
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  OverlayEntry? _searchOverlayEntry;
  final LayerLink _searchLayerLink = LayerLink();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _isMobileSearchActive = false;
  bool _suppressFocusListener = false;
  StateSetter? _overlaySetState;

  bool get isTeacher {
    final role = (userData?['role'] as String?)?.toLowerCase();
    return role == 'ogretmen' || role == 'öğretmen';
  }

  @override
  void initState() {
    super.initState();
    userData = widget.userData;
    _loadSchoolData();
    _loadTerms();
    _searchFocusNode.addListener(() {
      if (_suppressFocusListener) return;
      if (_searchFocusNode.hasFocus) {
        _showSearchOverlay();
      } else {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted &&
              !_searchFocusNode.hasFocus &&
              !_suppressFocusListener) {
            _hideSearchOverlay();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _hideSearchOverlay();
    super.dispose();
  }

  Future<void> _loadSchoolData() async {
    try {
      final schoolQuery = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', isEqualTo: widget.institutionId)
          .limit(1)
          .get();

      if (schoolQuery.docs.isNotEmpty) {
        if (mounted) {
          setState(() {
            schoolData = schoolQuery.docs.first.data();
          });
        }
      }
    } catch (e) {
      debugPrint('Okul verisi yüklenemedi: $e');
    }
  }

  Map<String, dynamic>? get _appSettings =>
      schoolData?['appSettings'] as Map<String, dynamic>?;

  bool _hasModuleAccess(String moduleKey) {
    if (!SchoolModuleGuard.isModuleEnabled(schoolData, moduleKey)) {
      return false;
    }
    if (moduleKey == 'sistem_ayarlari') return true;
    return UserPermissionService.isAppSettingEnabled(
      _appSettings,
      moduleKey,
      schoolTypeId: widget.schoolTypeId,
    );
  }

  bool _hasSubModuleAccess(String moduleKey, String subKey) {
    if (!SchoolModuleGuard.isSubModuleEnabled(schoolData, moduleKey, subKey)) {
      return false;
    }
    if (moduleKey == 'sistem_ayarlari' && subKey == 'uygulama_ayarlari') {
      return true;
    }
    return UserPermissionService.isAppSettingEnabled(
      _appSettings,
      '$moduleKey.$subKey',
      schoolTypeId: widget.schoolTypeId,
    );
  }

  bool _hasStModuleAccess(String stModKey) {
    // Süper Admin lisanslaması: kademe (idareci) modülü bu okul için kapatılmış mı?
    if (stModKey != 'ayarlar' &&
        !SchoolModuleGuard.isSchoolTypeModuleEnabled(schoolData, stModKey)) {
      return false;
    }
    if (!UserPermissionService.hasSchoolTypeModuleAccess(stModKey, userData)) {
      return false;
    }
    if (stModKey == 'ayarlar') return true;
    return UserPermissionService.isAppSettingEnabled(
      _appSettings,
      'st.$stModKey',
      schoolTypeId: widget.schoolTypeId,
    );
  }

  bool _hasStSubAccess(String stModKey, String stSubKey) {
    // Süper Admin lisanslaması: kademe alt başlığı bu okul için kapatılmış mı?
    if (stModKey != 'ayarlar' &&
        !SchoolModuleGuard.isSchoolTypeSubEnabled(
          schoolData,
          stModKey,
          UserPermissionService.normalizeSchoolTypeSubKey(stSubKey),
        )) {
      return false;
    }
    if (!UserPermissionService.hasSchoolTypeSubModuleAccess(
      stModKey,
      stSubKey,
      userData,
    )) {
      return false;
    }
    if (stModKey == 'ayarlar' && stSubKey == 'uygulama_ayarlari') return true;
    if (!UserPermissionService.isAppSettingEnabled(
      _appSettings,
      'st.$stModKey',
      schoolTypeId: widget.schoolTypeId,
    )) {
      return false;
    }
    return UserPermissionService.isAppSettingEnabled(
      _appSettings,
      'st.$stModKey.$stSubKey',
      schoolTypeId: widget.schoolTypeId,
    );
  }

  Future<T?> _pushStWithPermission<T>(
    Widget page, {
    required String stModKey,
    String? stSubKey,
    required String title,
  }) {
    final canEdit = stSubKey != null
        ? UserPermissionService.canEditSchoolTypeSubModule(
            stModKey,
            stSubKey,
            userData,
          )
        : UserPermissionService.canEditSchoolTypeModule(stModKey, userData);
    return Navigator.push<T>(
      context,
      ReadOnlyPermissionWrapper.route<T>(
        canEdit: canEdit,
        moduleName: title,
        page: page,
      ),
    );
  }

  bool _hasTeacherItemAccess(String tModKey, [String? tSubKey]) {
    // Süper Admin lisanslaması: öğretmen arayüzü modülü / alt başlığı kapatılmış mı?
    if (tSubKey == null) {
      if (!SchoolModuleGuard.isTeacherModuleEnabled(schoolData, tModKey)) {
        return false;
      }
    } else if (!SchoolModuleGuard.isTeacherSubEnabled(
      schoolData,
      tModKey,
      tSubKey,
    )) {
      return false;
    }
    if (!UserPermissionService.hasTeacherModuleAccess(
      tModKey,
      subModuleKey: tSubKey,
    )) {
      return false;
    }
    final key = tSubKey == null ? 't.$tModKey' : 't.$tModKey.$tSubKey';
    return UserPermissionService.isAppSettingEnabled(
      _appSettings,
      key,
      schoolTypeId: widget.schoolTypeId,
    );
  }

  bool get _isDailyReportEnabledForType {
    if (!_hasSubModuleAccess('egitim', 'gunluk_rapor')) return false;
    if (!_hasStSubAccess('egitim', 'gunluk_rapor')) return false;
    if (schoolData == null) return true;
    final appSettings = _appSettings;
    final cfg = DailyReportConfigModel.fromMap(
      appSettings?['dailyReport'] as Map<String, dynamic>?,
      appDisabledModules: appSettings?['disabledModules'] as List<dynamic>?,
      schoolTypeDisabledModules:
          appSettings?['schoolTypeDisabledModules'] as Map<String, dynamic>?,
    );
    return cfg.isEnabledForSchoolType(widget.schoolTypeId);
  }

  Future<void> _loadTerms() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final email = user.email;
      if (email == null) return;

      // Verileri yükle
      final profileData = await UserPermissionService.loadUserData();

      // instId'yi email'den parçalamak riskli, userData varsa oradan al
      final institutionId = await UserPermissionService.resolveInstitutionId(
        email,
        userData: profileData,
      );

      final snapshot = await FirebaseFirestore.instance
          .collection('terms')
          .where('institutionId', isEqualTo: institutionId)
          .get();

      final termsList = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // Sırala
      termsList.sort((a, b) {
        final aYear = a['startYear'] ?? 0;
        final bYear = b['startYear'] ?? 0;
        return bYear.compareTo(aYear);
      });

      // Aktif dönemi bul
      final active = termsList.firstWhere(
        (t) => t['isActive'] == true,
        orElse: () => termsList.isNotEmpty ? termsList.first : {},
      );

      // SharedPreferences'tan seçili dönemi oku
      final prefs = await SharedPreferences.getInstance();
      final savedTermId = prefs.getString('selected_term_id');

      Map<String, dynamic>? selectedTerm;
      if (savedTermId != null) {
        selectedTerm = termsList.firstWhere(
          (t) => t['id'] == savedTermId,
          orElse: () => {},
        );
        if (selectedTerm.isEmpty) selectedTerm = null;
      }

      if (mounted) {
        setState(() {
          _terms = termsList;
          _activeTerm = active.isNotEmpty ? active : null;
          _selectedTerm = selectedTerm ?? _activeTerm;
        });
      }
    } catch (e) {
      debugPrint('Dönemler yüklenirken hata: $e');
    }
  }

  void _showTermSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(
                  Icons.calendar_month_rounded,
                  color: Colors.indigo.shade900,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Dönem Yönetimi',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_terms.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Henüz dönem tanımlanmamış')),
              )
            else
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: 242),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _terms.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final term = _terms[index];
                      final isActive = term['isActive'] == true;
                      final isSelected = _selectedTerm == null
                          ? isActive
                          : _selectedTerm!['id'] == term['id'];
                      return InkWell(
                        onTap: () async {
                          final isActive = term['isActive'] == true;

                          if (isActive) {
                            await TermService().clearSelectedTerm();
                          } else {
                            await TermService().setSelectedTerm(
                              term['id'],
                              term['name'] ??
                                  '${term['startYear']}-${term['endYear']}',
                            );
                          }

                          setState(() => _selectedTerm = term);
                          if (mounted) Navigator.pop(context);
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isActive
                                      ? '✓ Aktif döneme geri dönüldü'
                                      : '✓ ${term['startYear']}-${term['endYear']} dönemine geçildi',
                                ),
                                backgroundColor: isActive
                                    ? Colors.blue
                                    : Colors.green,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.indigo.shade50
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.indigo.shade200
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: isActive
                                    ? Colors.green.shade100
                                    : (isSelected
                                          ? Colors.indigo.shade100
                                          : Colors.grey.shade100),
                                child: Icon(
                                  isActive
                                      ? Icons.check_circle_rounded
                                      : (isSelected
                                            ? Icons.visibility
                                            : Icons.history),
                                  color: isActive
                                      ? Colors.green.shade700
                                      : (isSelected
                                            ? Colors.indigo
                                            : Colors.blueGrey.shade400),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      term['name'] ??
                                          '${term['startYear']}-${term['endYear']}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: isSelected
                                            ? Colors.indigo.shade900
                                            : Colors.blueGrey.shade900,
                                      ),
                                    ),
                                    Text(
                                      isActive ? 'Aktif Dönem' : 'Geçmiş Dönem',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isActive
                                            ? Colors.green.shade700
                                            : Colors.blueGrey.shade400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                isSelected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: isSelected
                                    ? Colors.indigo.shade700
                                    : Colors.blueGrey.shade300,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: 24),
            if (_hasSubModuleAccess('egitim', 'sinif_atlatma') &&
                UserPermissionService.hasSubModuleAccess(
                  'egitim',
                  'sinif_atlatma',
                  userData,
                )) ...[
              _buildSelectorAction(
                icon: Icons.upgrade_rounded,
                title: 'Sınıf Atlatma İşlemleri',
                subtitle:
                    'Seçili öğrencileri bir üst sınıf seviyesine geçirir.',
                color: Colors.indigo,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ClassPromotionScreen(
                        schoolTypeId: widget.schoolTypeId,
                        schoolTypeName: widget.schoolTypeName,
                        institutionId: widget.institutionId,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
            if (_hasSubModuleAccess('egitim', 'nakil_islemleri') &&
                UserPermissionService.hasSubModuleAccess(
                  'egitim',
                  'nakil_islemleri',
                  userData,
                )) ...[
              _buildSelectorAction(
                icon: Icons.transfer_within_a_station_rounded,
                title: 'Nakil İşlemleri',
                subtitle: 'Seçili öğrencileri farklı bir okul türüne aktarır.',
                color: Colors.teal,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => StudentTransferScreen(
                        sourceSchoolTypeId: widget.schoolTypeId,
                        sourceSchoolTypeName: widget.schoolTypeName,
                        institutionId: widget.institutionId,
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSelectorAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.blueGrey.shade400,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.blueGrey.shade300),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileSearchInput() {
    return CompositedTransformTarget(
      link: _searchLayerLink,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(40),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: Colors.blueGrey,
              ),
              onPressed: () => setState(() => _isMobileSearchActive = false),
            ),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Arayın...',
                  hintStyle: TextStyle(
                    color: Colors.blueGrey.shade300,
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isMobile) {
    return CompositedTransformTarget(
      link: _searchLayerLink,
      child: Container(
        width: 380,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(40),
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Öğrenci veya işlem ara...',
            hintStyle: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13),
            prefixIcon: Icon(
              Icons.search,
              color: Colors.indigo.shade300,
              size: 20,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 11),
          ),
        ),
      ),
    );
  }

  Widget _buildTermSelectorButton(String currentTermName, bool isMobile) {
    return InkWell(
      onTap: _showTermSelector,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: _selectedTerm != null && _selectedTerm!['isActive'] != true
              ? Colors.orange.shade50
              : Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _selectedTerm != null && _selectedTerm!['isActive'] != true
                ? Colors.orange.shade200
                : Colors.indigo.shade100,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _selectedTerm != null && _selectedTerm!['isActive'] != true
                  ? Icons.history
                  : Icons.calendar_today_outlined,
              size: 14,
              color: _selectedTerm != null && _selectedTerm!['isActive'] != true
                  ? Colors.orange.shade800
                  : Colors.indigo,
            ),
            if (!isMobile) ...[
              const SizedBox(width: 8),
              Text(
                currentTermName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 14,
                color: Colors.indigo,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProfileButton() {
    final displayName = _getUserDisplayName();
    final role = _getUserRole();
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';
    final bool isMobile = MediaQuery.of(context).size.width < 1100;
    final String currentTermName = _selectedTerm != null
        ? (_selectedTerm!['termName'] ??
              '${_selectedTerm!['startYear']}-${_selectedTerm!['endYear']}')
        : (_activeTerm != null
              ? (_activeTerm!['termName'] ?? 'Aktif Dönem')
              : 'Dönem Seçin');

    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      onSelected: (value) {
        if (value == 'profile') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) =>
                  const ProfileSettingsScreen(isSchoolSettings: false),
            ),
          );
        } else if (value == 'school_settings') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) =>
                  const ProfileSettingsScreen(isSchoolSettings: true),
            ),
          );
        } else if (value == 'notifications') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) =>
                  const ProfileSettingsScreen(isSchoolSettings: false),
            ),
          );
        } else if (value == 'qr') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TeacherQrScanScreen()),
          );
        } else if (value == 'web_qr_login') {
          WebQrLoginScannerSheet.show(context);
        } else if (value == 'term') {
          _showTermSelector();
        } else if (value == 'logout') {
          _logout();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.indigo.shade100,
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: Colors.indigo.shade800,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        role,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'profile',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  color: Colors.indigo.shade700,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Profilim',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Profili Düzenle',
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (userData == null ||
            userData!['role'] == 'genel_mudur' ||
            userData!['role'] == 'admin') ...[
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'school_settings',
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.business_outlined,
                    color: Colors.blue.shade700,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Okul Bilgileri',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Kurum Ayarlarını Yönet',
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'notifications',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.notifications_active_outlined,
                  color: Colors.teal.shade700,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bildirim Ayarları',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Tercihleri Düzenle',
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                  ),
                ],
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'qr',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Colors.orange.shade700,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Giriş / Çıkış (QR)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Kamera ile QR tarama',
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                  ),
                ],
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'web_qr_login',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.devices_rounded,
                  color: Colors.indigo.shade700,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Web\'de QR ile Oturum Aç',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Bilgisayarda QR okutarak giriş yap',
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (isMobile) ...[
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'term',
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color:
                        _selectedTerm != null &&
                            _selectedTerm!['isActive'] != true
                        ? Colors.orange.shade50
                        : Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _selectedTerm != null && _selectedTerm!['isActive'] != true
                        ? Icons.history
                        : Icons.calendar_today_outlined,
                    color:
                        _selectedTerm != null &&
                            _selectedTerm!['isActive'] != true
                        ? Colors.orange.shade700
                        : Colors.indigo.shade700,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dönem İşlemleri',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      currentTermName,
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            _selectedTerm != null &&
                                _selectedTerm!['isActive'] != true
                            ? Colors.orange.shade700
                            : Colors.blueGrey,
                        fontWeight:
                            _selectedTerm != null &&
                                _selectedTerm!['isActive'] != true
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.logout_rounded,
                  color: Colors.red.shade600,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Çıkış Yap',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade700,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: CircleAvatar(
          radius: 17,
          backgroundColor: Colors.indigo.shade50,
          child: Text(
            initial,
            style: const TextStyle(
              color: Colors.indigo,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  void _safeNavigate(Function action) {
    _suppressFocusListener = true;
    action();
    _hideSearchOverlay();
    _overlaySetState = null;
    _searchFocusNode.unfocus();
    _suppressFocusListener = false;
    if (mounted) {
      setState(() {
        _isMobileSearchActive = false;
        _searchController.clear();
        _searchResults = [];
      });
    }
  }

  void _showSearchOverlay() {
    if (_searchOverlayEntry != null) return;
    _searchOverlayEntry = _createSearchOverlayEntry();
    Overlay.of(context).insert(_searchOverlayEntry!);
  }

  void _hideSearchOverlay() {
    _searchOverlayEntry?.remove();
    _searchOverlayEntry = null;
  }

  OverlayEntry _createSearchOverlayEntry() {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 1100;
    final overlayWidth = isMobile ? (size.width - 32) : 450.0;
    final double appBarHeight =
        kToolbarHeight + MediaQuery.of(context).padding.top;

    return OverlayEntry(
      builder: (overlayCtx) {
        if (isMobile) {
          return Stack(
            children: [
              Positioned(
                top: appBarHeight + 4,
                left: 16,
                right: 16,
                child: StatefulBuilder(
                  builder: (_, setOverlayState) {
                    _overlaySetState = setOverlayState;
                    return Material(
                      elevation: 8,
                      shadowColor: Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(24),
                      color: Colors.white,
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 400),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.indigo.shade100,
                            width: 1.2,
                          ),
                        ),
                        child: _isSearching
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : _searchResults.isEmpty &&
                                  _searchController.text.isNotEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: Text(
                                    'Sonuç bulunamadı.',
                                    style: TextStyle(
                                      color: Colors.blueGrey,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              )
                            : _searchResults.isEmpty
                            ? _buildInitialSearchItems()
                            : ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                itemCount: _searchResults.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: Colors.indigo.withValues(alpha: 0.05),
                                ),
                                itemBuilder: (_, index) {
                                  final item = _searchResults[index];
                                  final isStudent = item['type'] == 'student';
                                  final onTapAction =
                                      item['onTap'] as Function?;
                                  final onRegTapAction =
                                      item['onRegTap'] as Function?;
                                  return ListTile(
                                    onTap: () {
                                      if (onTapAction != null)
                                        _safeNavigate(onTapAction);
                                    },
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 4,
                                    ),
                                    leading: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        item['icon'] as IconData,
                                        color: Colors.indigo,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(
                                      item['title'] as String,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                    subtitle: Text(
                                      item['subtitle'] as String,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blueGrey.shade400,
                                      ),
                                    ),
                                    trailing: isStudent
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.folder_shared_outlined,
                                                  size: 18,
                                                  color: Colors.indigo,
                                                ),
                                                onPressed: () {
                                                  if (onTapAction != null)
                                                    _safeNavigate(onTapAction);
                                                },
                                                constraints:
                                                    const BoxConstraints(),
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.how_to_reg_outlined,
                                                  size: 18,
                                                  color: Colors.orange,
                                                ),
                                                onPressed: () {
                                                  if (onRegTapAction != null)
                                                    _safeNavigate(
                                                      onRegTapAction,
                                                    );
                                                },
                                                constraints:
                                                    const BoxConstraints(),
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                              ),
                                            ],
                                          )
                                        : null,
                                  );
                                },
                              ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        }

        return Stack(
          children: [
            CompositedTransformFollower(
              link: _searchLayerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 52),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: overlayWidth,
                  child: StatefulBuilder(
                    builder: (_, setOverlayState) {
                      _overlaySetState = setOverlayState;
                      return Material(
                        elevation: 8,
                        shadowColor: Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(24),
                        color: Colors.white,
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 400),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.indigo.shade100,
                              width: 1.2,
                            ),
                          ),
                          child: _isSearching
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : _searchResults.isEmpty &&
                                    _searchController.text.isNotEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Center(
                                    child: Text(
                                      'Sonuç bulunamadı.',
                                      style: TextStyle(
                                        color: Colors.blueGrey,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                )
                              : _searchResults.isEmpty
                              ? _buildInitialSearchItems()
                              : ListView.separated(
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  itemCount: _searchResults.length,
                                  separatorBuilder: (_, __) => Divider(
                                    height: 1,
                                    color: Colors.indigo.withValues(
                                      alpha: 0.05,
                                    ),
                                  ),
                                  itemBuilder: (_, index) {
                                    final item = _searchResults[index];
                                    final isStudent = item['type'] == 'student';
                                    final onTapAction =
                                        item['onTap'] as Function?;
                                    final onRegTapAction =
                                        item['onRegTap'] as Function?;
                                    return ListTile(
                                      onTap: () {
                                        if (onTapAction != null)
                                          _safeNavigate(onTapAction);
                                      },
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 4,
                                          ),
                                      leading: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.indigo.shade50,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Icon(
                                          item['icon'] as IconData,
                                          color: Colors.indigo,
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(
                                        item['title'] as String,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                      subtitle: Text(
                                        item['subtitle'] as String,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.blueGrey.shade400,
                                        ),
                                      ),
                                      trailing: isStudent
                                          ? Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons
                                                        .folder_shared_outlined,
                                                    size: 18,
                                                    color: Colors.indigo,
                                                  ),
                                                  onPressed: () {
                                                    if (onTapAction != null)
                                                      _safeNavigate(
                                                        onTapAction,
                                                      );
                                                  },
                                                  constraints:
                                                      const BoxConstraints(),
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.how_to_reg_outlined,
                                                    size: 18,
                                                    color: Colors.orange,
                                                  ),
                                                  onPressed: () {
                                                    if (onRegTapAction != null)
                                                      _safeNavigate(
                                                        onRegTapAction,
                                                      );
                                                  },
                                                  constraints:
                                                      const BoxConstraints(),
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : null,
                                    );
                                  },
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInitialSearchItems() {
    final List<Map<String, dynamic>> shortcuts = [
      if (_hasSubModuleAccess('egitim', 'ogrenci_kaydi') &&
          _hasStSubAccess('kayit', 'ogrenci_listesi'))
        {
          'title': 'Öğrenci Kaydı',
          'subtitle': 'Eğitim Modülü',
          'icon': Icons.person_add_outlined,
          'onTap': () => _pushStWithPermission(
            StudentRegistrationScreen(
              fixedSchoolTypeId: widget.schoolTypeId,
              fixedSchoolTypeName: widget.schoolTypeName,
              fixedInstitutionId: widget.institutionId,
            ),
            stModKey: 'kayit',
            stSubKey: 'ogrenci_listesi',
            title: 'Öğrenci Listesi',
          ),
        },
      if (_hasStSubAccess('kayit', 'sube_listesi'))
        {
          'title': 'Şube Listesi',
          'subtitle': 'Yönetim Modülü',
          'icon': Icons.group_outlined,
          'onTap': () => _pushStWithPermission(
            ClassManagementScreen(
              institutionId: widget.institutionId,
              schoolTypeId: widget.schoolTypeId,
              schoolTypeName: widget.schoolTypeName,
            ),
            stModKey: 'kayit',
            stSubKey: 'sube_listesi',
            title: 'Şube Listesi',
          ),
        },
      if (_hasModuleAccess('magaza') && _hasStModuleAccess('magaza'))
        {
          'title': 'Mağaza & Online Satış',
          'subtitle': 'Mağaza Modülü',
          'icon': Icons.storefront_rounded,
          'onTap': () => _pushStWithPermission(
            SchoolStoreManagementScreen(
              institutionId: widget.institutionId,
              schoolId: schoolData?['id']?.toString(),
              schoolName:
                  schoolData?['schoolName']?.toString() ??
                  widget.schoolTypeName,
              schoolTypeId: widget.schoolTypeId,
            ),
            stModKey: 'magaza',
            title: 'Mağaza & Online Satış',
          ),
        },
    ];
    return ListView(
      shrinkWrap: true,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Text(
            'HIZLI ERİŞİM',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.indigo.shade300,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ...shortcuts.map((s) {
          final shortcutAction = s['onTap'] as Function?;
          return ListTile(
            onTap: () {
              if (shortcutAction != null) _safeNavigate(shortcutAction);
            },
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 4,
            ),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                s['icon'] as IconData,
                color: Colors.indigo,
                size: 18,
              ),
            ),
            title: Text(
              s['title'] as String,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF1E293B),
              ),
            ),
            subtitle: Text(
              s['subtitle'] as String,
              style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
          );
        }).toList(),
      ],
    );
  }

  void _onSearchChanged(String value) async {
    if (value.isEmpty) {
      if (mounted) setState(() => _searchResults = []);
      _overlaySetState?.call(() {});
      return;
    }
    if (mounted) setState(() => _isSearching = true);
    _overlaySetState?.call(() {});
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .get();
      final matches = snapshot.docs
          .where((doc) {
            final name = (doc['fullName'] ?? '').toString().toLowerCase();
            final number = (doc['studentNumber'] ?? '')
                .toString()
                .toLowerCase();
            final query = value.toLowerCase();
            return name.contains(query) || number.contains(query);
          })
          .take(5)
          .map((doc) {
            final data = doc.data();
            final studentId = doc.id;
            final stId = data['schoolTypeId'] ?? '';
            final stName = data['schoolTypeName'] ?? 'Okul Türü';

            return {
              'type': 'student',
              'title': data['fullName'],
              'subtitle': 'Öğrenci No: ${data['studentNumber']}',
              'icon': Icons.person_outline,
              'onTap': () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PortfolioScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: stId,
                      schoolTypeName: stName,
                      initialStudentId: studentId,
                    ),
                  ),
                );
              },
              'onRegTap': () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        StudentRegistrationScreen(initialStudentId: studentId),
                  ),
                );
              },
            };
          })
          .toList();
      if (mounted) {
        setState(() {
          _searchResults = matches;
          _isSearching = false;
        });
        _overlaySetState?.call(() {});
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
      _overlaySetState?.call(() {});
    }
  }

  String _getUserDisplayName() {
    if (userData != null) return userData!['fullName'] ?? 'Kullanıcı';
    return schoolData?['adminFullName'] ?? 'Yönetici';
  }

  String _getUserRole() {
    if (userData != null) {
      final role = userData!['role'] ?? '';
      const roleMap = {
        'admin': 'Kurum Admini',
        'genel_mudur': 'Genel Müdür',
        'mudur': 'Müdür',
        'mudir_yardimcisi': 'Müdür Yardımcısı',
        'ogretmen': 'Öğretmen',
        'personel': 'Personel',
      };
      return roleMap[role] ?? role;
    }
    return 'Yönetici';
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.logout_rounded,
                color: Colors.grey.shade900,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Çıkış Yap',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'Hesabınızdan çıkış yapmak istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade900,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      UserPermissionService.clearCache();
      TermService().clearCache();
      await FirebaseAuth.instance.signOut();
      if (mounted) Navigator.pushReplacementNamed(context, '/school-login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 1100;

    return Column(
      children: [
        // Main Content
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      _buildCategorySelector(isMobile),
                      Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 1400),
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 16 : 24,
                            vertical: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildGridSections(isMobile),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGridSections(bool isMobile) {
    final bool isFiltered = _selectedCategory != 'Tümü';
    final double cardPadding = isMobile ? 16 : 24;
    final double screenWidth = MediaQuery.of(context).size.width;
    const double maxLayoutWidth = 1400.0;
    final double constrainedWidth = screenWidth > maxLayoutWidth
        ? maxLayoutWidth
        : screenWidth;
    final double availableWidth = constrainedWidth - (cardPadding * 2);

    double gridCardWidth;
    if (availableWidth > 1000) {
      gridCardWidth = (availableWidth - 48) / 3;
    } else if (availableWidth > 700) {
      gridCardWidth = (availableWidth - 24) / 2;
    } else {
      gridCardWidth = availableWidth;
    }

    final double currentCardWidth = isFiltered ? availableWidth : gridCardWidth;

    if (isTeacher) {
      return _buildTeacherGrid(isMobile, currentCardWidth, isFiltered);
    }

    final allModules = <_ModuleCardWidget>[
      if ((_hasModuleAccess('egitim') ||
              _hasModuleAccess('insan_kaynaklari')) &&
          _hasStModuleAccess('kayit'))
        _ModuleCardWidget(
          key: const ValueKey('kayit'),
          title: 'ÖĞRENCİ VE PERSONEL',
          badge: 'Kayıt',
          icon: Icons.people_outline,
          color: Colors.blue,
          cardWidth: currentCardWidth,
          isMobile: isMobile,
          category: 'Kayıt',
          showAllItems: isFiltered,
          items: [
            if (_hasSubModuleAccess('egitim', 'on_kayit') &&
                _hasStSubAccess('kayit', 'on_kayit'))
              {
                'title': 'Ön Kayıt',
                'onTap': () => _pushStWithPermission(
                  PreRegistrationScreen(
                    fixedSchoolTypeId: widget.schoolTypeId,
                    fixedSchoolTypeName: widget.schoolTypeName,
                    fixedInstitutionId: widget.institutionId,
                  ),
                  stModKey: 'kayit',
                  stSubKey: 'on_kayit',
                  title: 'Ön Kayıt',
                ),
              },
            if (_hasSubModuleAccess('egitim', 'ogrenci_kaydi') &&
                _hasStSubAccess('kayit', 'ogrenci_listesi'))
              {
                'title': 'Öğrenci Listesi',
                'onTap': () => _pushStWithPermission(
                  StudentRegistrationScreen(
                    fixedSchoolTypeId: widget.schoolTypeId,
                    fixedSchoolTypeName: widget.schoolTypeName,
                    fixedInstitutionId: widget.institutionId,
                  ),
                  stModKey: 'kayit',
                  stSubKey: 'ogrenci_listesi',
                  title: 'Öğrenci Listesi',
                ),
              },
            if (_hasSubModuleAccess('insan_kaynaklari', 'personel_bilgi') &&
                _hasStSubAccess('kayit', 'personel_listesi'))
              {
                'title': 'Personel Listesi',
                'onTap': () => _pushStWithPermission(
                  StaffListScreen(
                    fixedSchoolTypeId: widget.schoolTypeId,
                    fixedSchoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'kayit',
                  stSubKey: 'personel_listesi',
                  title: 'Personel Listesi',
                ),
              },
            if (_hasStSubAccess('kayit', 'sube_listesi'))
              {
                'title': 'Şube Listesi',
                'onTap': () => _pushStWithPermission(
                  ClassManagementScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'kayit',
                  stSubKey: 'sube_listesi',
                  title: 'Şube Listesi',
                ),
              },
            if (_hasStSubAccess('kayit', 'ders_listesi'))
              {
                'title': 'Ders Listesi',
                'onTap': () => _pushStWithPermission(
                  LessonManagementScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'kayit',
                  stSubKey: 'ders_listesi',
                  title: 'Ders Listesi',
                ),
              },
            if (_hasStSubAccess('kayit', 'kurs_listesi'))
              {
                'title': 'Kurs Listesi',
                'onTap': () => _pushStWithPermission(
                  CourseGroupManagementScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                    initialType: DynamicCourseGroupType.track,
                  ),
                  stModKey: 'kayit',
                  stSubKey: 'kurs_listesi',
                  title: 'Kurs Listesi',
                ),
              },
            if (_hasStSubAccess('kayit', 'kulup_listesi'))
              {
                'title': 'Kulüp Listesi',
                'onTap': () => _pushStWithPermission(
                  CourseGroupManagementScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                    initialType: DynamicCourseGroupType.club,
                  ),
                  stModKey: 'kayit',
                  stSubKey: 'kulup_listesi',
                  title: 'Kulüp Listesi',
                ),
              },
            if (_hasStSubAccess('kayit', 'derslik_listesi'))
              {
                'title': 'Derslik Listesi',
                'onTap': () => _pushStWithPermission(
                  ClassroomManagementScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'kayit',
                  stSubKey: 'derslik_listesi',
                  title: 'Derslik Listesi',
                ),
              },
            if (_hasStSubAccess('kayit', 'kitap_listesi'))
              {
                'title': 'Kitap Listesi',
                'onTap': () => _pushStWithPermission(
                  BookManagementScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'kayit',
                  stSubKey: 'kitap_listesi',
                  title: 'Kitap Listesi',
                ),
              },
          ],
          onTap: () => setState(() => _selectedCategory = 'Kayıt'),
        ),
      if (_hasModuleAccess('egitim') && _hasStModuleAccess('egitim'))
        _ModuleCardWidget(
          key: const ValueKey('egitim'),
          title: 'EĞİTİM İŞLEMLERİ',
          badge: 'Eğitim',
          icon: Icons.school,
          color: Colors.green,
          cardWidth: currentCardWidth,
          isMobile: isMobile,
          category: 'Eğitim',
          showAllItems: isFiltered,
          items: [
            if (_isDailyReportEnabledForType)
              {
                'title': 'Günlük Rapor (Günlük Karne)',
                'onTap': () => _pushStWithPermission(
                  DailyReportScreen(
                    institutionId: widget.institutionId,
                    fixedSchoolTypeId: widget.schoolTypeId,
                    fixedSchoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'egitim',
                  stSubKey: 'gunluk_rapor',
                  title: 'Günlük Rapor (Günlük Karne)',
                ),
              },
            if (_hasStSubAccess('egitim', 'calisma_takvimi'))
              {
                'title': 'Çalışma Takvimi',
                'onTap': () => _pushStWithPermission(
                  WorkCalendarScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'egitim',
                  stSubKey: 'calisma_takvimi',
                  title: 'Çalışma Takvimi',
                ),
              },
            if (_hasStSubAccess('egitim', 'ders_saatleri'))
              {
                'title': 'Ders Saatleri',
                'onTap': () => _pushStWithPermission(
                  LessonHoursScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'egitim',
                  stSubKey: 'ders_saatleri',
                  title: 'Ders Saatleri',
                ),
              },
            if (_hasStSubAccess('egitim', 'ders_programi'))
              {
                'title': 'Ders Programı',
                'onTap': () => _pushStWithPermission(
                  ClassScheduleScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'egitim',
                  stSubKey: 'ders_programi',
                  title: 'Ders Programı',
                ),
              },
            if (_hasStSubAccess('egitim', 'sube_ders_programi'))
              {
                'title': 'Şube Ders Programı',
                'onTap': () => _pushStWithPermission(
                  ClassScheduleViewScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'egitim',
                  stSubKey: 'sube_ders_programi',
                  title: 'Şube Ders Programı',
                ),
              },
            if (_hasStSubAccess('egitim', 'ogretmen_ders_programi'))
              {
                'title': 'Öğretmen Ders Programı',
                'onTap': () => _pushStWithPermission(
                  TeacherScheduleViewScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'egitim',
                  stSubKey: 'ogretmen_ders_programi',
                  title: 'Öğretmen Ders Programı',
                ),
              },
            if (_hasStSubAccess('egitim', 'kazanim_takip'))
              {
                'title': 'Kazanım Takip Sistemi',
                'onTap': () => _pushStWithPermission(
                  CurriculumTrackingScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'egitim',
                  stSubKey: 'kazanim_takip',
                  title: 'Kazanım Takip Sistemi',
                ),
              },
            if (_hasStSubAccess('egitim', 'anket_islemleri'))
              {
                'title': 'Anket İşlemleri',
                'onTap': () => _pushStWithPermission(
                  SurveyListScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'egitim',
                  stSubKey: 'anket_islemleri',
                  title: 'Anket İşlemleri',
                ),
              },
            if (_hasStSubAccess('egitim', 'etut_islemleri'))
              {
                'title': 'Etüt İşlemleri',
                'onTap': () => _pushStWithPermission(
                  EtutProcessScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'egitim',
                  stSubKey: 'etut_islemleri',
                  title: 'Etüt İşlemleri',
                ),
              },
          ],
          onTap: () => setState(() => _selectedCategory = 'Eğitim'),
        ),
      if (_hasModuleAccess('rehberlik') && _hasStModuleAccess('rehberlik'))
        _ModuleCardWidget(
          key: const ValueKey('rehberlik'),
          title: 'REHBERLİK İŞLEMLERİ',
          badge: 'Rehberlik',
          icon: Icons.folder_special,
          color: Colors.purple,
          cardWidth: currentCardWidth,
          isMobile: isMobile,
          category: 'Rehberlik',
          showAllItems: isFiltered,
          items: [
            if (_hasSubModuleAccess('rehberlik', 'ogrenci_portfolyosu') &&
                _hasStSubAccess('rehberlik', 'portfolyo'))
              {
                'title': 'Portfolyo',
                'onTap': () => _pushStWithPermission(
                  PortfolioScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'rehberlik',
                  stSubKey: 'portfolyo',
                  title: 'Portfolyo',
                ),
              },
            if (_hasSubModuleAccess('rehberlik', 'talepler') &&
                _hasStSubAccess('rehberlik', 'talepler'))
              {
                'title': 'Talepler (Yönlendirmeler)',
                'onTap': () => _pushStWithPermission(
                  DemandDashboardScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'rehberlik',
                  stSubKey: 'talepler',
                  title: 'Talepler (Yönlendirmeler)',
                ),
              },
            if (_hasSubModuleAccess('rehberlik', 'gorusme_kayitlari') &&
                _hasStSubAccess('rehberlik', 'gorusmeler'))
              {
                'title': 'Görüşmeler',
                'onTap': () => _pushStWithPermission(
                  GuidanceInterviewScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'rehberlik',
                  stSubKey: 'gorusmeler',
                  title: 'Görüşmeler',
                ),
              },
            if (_hasStSubAccess('rehberlik', 'toplu_gozlem'))
              {
                'title': 'Toplu Gözlem Girişi',
                'onTap': () => _pushStWithPermission(
                  ActivityListScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'rehberlik',
                  stSubKey: 'toplu_gozlem',
                  title: 'Toplu Gözlem Girişi',
                ),
              },
            if (_hasStSubAccess('rehberlik', 'mentor_calismalari'))
              {
                'title': 'Mentör Çalışmaları',
                'onTap': () => _pushStWithPermission(
                  MentorStudiesHubScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'rehberlik',
                  stSubKey: 'mentor_calismalari',
                  title: 'Mentör Çalışmaları',
                ),
              },
            if (_hasStSubAccess('rehberlik', 'rehberlik_ajandasi'))
              {
                'title': 'Rehberlik Ajandası',
                'onTap': () => _pushStWithPermission(
                  PersonalNotesScreen(),
                  stModKey: 'rehberlik',
                  stSubKey: 'rehberlik_ajandasi',
                  title: 'Rehberlik Ajandası',
                ),
              },
            if (_hasSubModuleAccess('rehberlik', 'rehberlik_testleri') &&
                _hasStSubAccess('rehberlik', 'envanterler'))
              {
                'title': 'Envanterler',
                'onTap': () => _pushStWithPermission(
                  GuidanceTestCatalogScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'rehberlik',
                  stSubKey: 'envanterler',
                  title: 'Envanterler',
                ),
              },
            if (_hasStSubAccess('rehberlik', 'gelisim_raporlari'))
              {
                'title': '360 Gelişim Raporları',
                'onTap': () => _pushStWithPermission(
                  DevelopmentReportManagementScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'rehberlik',
                  stSubKey: 'gelisim_raporlari',
                  title: '360 Gelişim Raporları',
                ),
              },
          ],
          onTap: () => setState(() => _selectedCategory = 'Rehberlik'),
        ),
      if (_hasModuleAccess('olcme_degerlendirme') &&
          _hasStModuleAccess('olcme'))
        _ModuleCardWidget(
          key: const ValueKey('olcme'),
          title: 'ÖLÇME DEĞERLENDİRME',
          badge: 'Ölçme',
          icon: Icons.analytics,
          color: Colors.orange,
          cardWidth: currentCardWidth,
          isMobile: isMobile,
          category: 'Ölçme',
          showAllItems: isFiltered,
          items: [
            if (_hasSubModuleAccess('olcme_degerlendirme', 'tanimlar') &&
                _hasStSubAccess('olcme', 'tanimlar'))
              {
                'title': 'Tanımlar',
                'onTap': () => _pushStWithPermission(
                  AssessmentDefinitionsScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'olcme',
                  stSubKey: 'tanimlar',
                  title: 'Tanımlar',
                ),
              },
            if (_hasSubModuleAccess('olcme_degerlendirme', 'raporlar') &&
                _hasStSubAccess('olcme', 'raporlar'))
              {
                'title': 'Raporlar',
                'onTap': () => _pushStWithPermission(
                  AssessmentReportsScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'olcme',
                  stSubKey: 'raporlar',
                  title: 'Raporlar',
                ),
              },
            if (_hasSubModuleAccess('olcme_degerlendirme', 'denemeler') &&
                _hasStSubAccess('olcme', 'denemeler'))
              {
                'title': 'Denemeler',
                'onTap': () => _pushStWithPermission(
                  TrialExamListScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'olcme',
                  stSubKey: 'denemeler',
                  title: 'Denemeler',
                ),
              },
            if (_hasSubModuleAccess('olcme_degerlendirme', 'sinavlar') &&
                _hasStSubAccess('olcme', 'sinavlar'))
              {
                'title': 'Sınavlar',
                'onTap': () => _pushStWithPermission(
                  ActiveExamListScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'olcme',
                  stSubKey: 'sinavlar',
                  title: 'Sınavlar',
                ),
              },
            if (_hasSubModuleAccess('olcme_degerlendirme', 'hata_kitapcigi') &&
                _hasStSubAccess('olcme', 'hata_kitapcigi'))
              {
                'title': 'Hata Kitapçığı',
                'onTap': () => _pushStWithPermission(
                  ErrorBookletDashboardScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'olcme',
                  stSubKey: 'hata_kitapcigi',
                  title: 'Hata Kitapçığı',
                ),
              },
            if (_hasSubModuleAccess('olcme_degerlendirme', 'fokus_kitap') &&
                _hasStSubAccess('olcme', 'fokus_kitap'))
              {
                'title': 'Fokus Kitap (Kişiye Özel)',
                'onTap': () => _pushStWithPermission(
                  PersonalizedBookDashboardScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                  ),
                  stModKey: 'olcme',
                  stSubKey: 'fokus_kitap',
                  title: 'Fokus Kitap (Kişiye Özel)',
                ),
              },
            if (_hasSubModuleAccess(
                  'olcme_degerlendirme',
                  'merkezi_deneme_raporlari',
                ) &&
                _hasStSubAccess('olcme', 'merkezi_deneme_raporlari'))
              {
                'title': 'Genel Merkez Raporları',
                'onTap': () => _pushStWithPermission(
                  CentralSchoolReportsScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                  ),
                  stModKey: 'olcme',
                  stSubKey: 'merkezi_deneme_raporlari',
                  title: 'Genel Merkez Raporları',
                ),
              },
            if (_hasSubModuleAccess('olcme_degerlendirme', 'soru_havuzu') &&
                _hasStSubAccess('olcme', 'soru_havuzu'))
              {
                'title': 'Soru havuzu',
                'onTap': () => _pushStWithPermission(
                  QuestionPoolScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'olcme',
                  stSubKey: 'soru_havuzu',
                  title: 'Soru Havuzu',
                ),
              },
          ],
          onTap: () => setState(() => _selectedCategory = 'Ölçme'),
        ),
      if (_hasStModuleAccess('araclar'))
        _ModuleCardWidget(
          key: const ValueKey('araclar'),
          title: 'ARAÇLAR',
          badge: 'Araçlar',
          icon: Icons.build_circle_outlined,
          color: Colors.amber.shade700,
          cardWidth: currentCardWidth,
          isMobile: isMobile,
          category: 'Araçlar',
          showAllItems: isFiltered,
          items: [
            if (_hasStSubAccess('araclar', 'sinif_ici_yonetim'))
              {
                'title': 'Sınıf İçi Yönetim ve Etkileşim',
                'onTap': () => _pushStWithPermission(
                  ToolsHubScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                    initialCategoryIndex: 0,
                  ),
                  stModKey: 'araclar',
                  stSubKey: 'sinif_ici_yonetim',
                  title: 'Sınıf İçi Yönetim ve Etkileşim',
                ),
              },
            if (_hasStSubAccess('araclar', 'sinav_gozetmenlik'))
              {
                'title': 'Sınav ve Gözetmenlik',
                'onTap': () => _pushStWithPermission(
                  ToolsHubScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                    initialCategoryIndex: 1,
                  ),
                  stModKey: 'araclar',
                  stSubKey: 'sinav_gozetmenlik',
                  title: 'Sınav ve Gözetmenlik',
                ),
              },
            if (_hasStSubAccess('araclar', 'akademik_olcme'))
              {
                'title': 'Akademik Ölçme ve Başarı Takibi',
                'onTap': () => _pushStWithPermission(
                  ToolsHubScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                    initialCategoryIndex: 2,
                  ),
                  stModKey: 'araclar',
                  stSubKey: 'akademik_olcme',
                  title: 'Akademik Ölçme ve Başarı Takibi',
                ),
              },
            if (_hasStSubAccess('araclar', 'evrak_otomasyon'))
              {
                'title': 'Evrak, Liste ve Şablon Otomasyonları',
                'onTap': () => _pushStWithPermission(
                  ToolsHubScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                    initialCategoryIndex: 3,
                  ),
                  stModKey: 'araclar',
                  stSubKey: 'evrak_otomasyon',
                  title: 'Evrak, Liste ve Şablon Otomasyonları',
                ),
              },
            if (_hasStSubAccess('araclar', 'ogrenci_hareket_takip'))
              {
                'title': 'Geç - İzin - Revir - Görüşme (Canlı İzleme)',
                'onTap': () => _pushStWithPermission(
                  ToolsHubScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                    initialCategoryIndex: 4,
                  ),
                  stModKey: 'araclar',
                  stSubKey: 'ogrenci_hareket_takip',
                  title: 'Geç - İzin - Revir - Görüşme (Canlı İzleme)',
                ),
              },
            if (_hasStSubAccess('araclar', 'online_hizmetler'))
              {
                'title': 'Online Hizmetler',
                'onTap': () => _pushStWithPermission(
                  ToolsHubScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                    initialCategoryIndex: 6,
                  ),
                  stModKey: 'araclar',
                  stSubKey: 'online_hizmetler',
                  title: 'Online Hizmetler',
                ),
              },
            if (_hasStSubAccess('araclar', 'notlarim'))
              {
                'title': 'Notlarım',
                'onTap': () => _pushStWithPermission(
                  const PersonalNotesScreen(),
                  stModKey: 'araclar',
                  stSubKey: 'notlarim',
                  title: 'Notlarım',
                ),
              },
          ],
          onTap: () {
            if (_selectedCategory == 'Araçlar') {
              _pushStWithPermission(
                ToolsHubScreen(
                  institutionId: widget.institutionId,
                  schoolTypeId: widget.schoolTypeId,
                  schoolTypeName: widget.schoolTypeName,
                  initialCategoryIndex: 0,
                ),
                stModKey: 'araclar',
                title: 'Araçlar',
              );
            } else {
              setState(() => _selectedCategory = 'Araçlar');
            }
          },
        ),
      if (_hasModuleAccess('insan_kaynaklari') && _hasStModuleAccess('gorev'))
        _ModuleCardWidget(
          key: const ValueKey('gorev'),
          title: 'GÖREVLENDİRME VE İZİN',
          badge: 'Görev',
          icon: Icons.assignment_ind,
          color: Colors.teal,
          cardWidth: currentCardWidth,
          isMobile: isMobile,
          category: 'Görev',
          showAllItems: isFiltered,
          items: [
            if (_hasStSubAccess('gorev', 'todo_list'))
              {
                'title': 'To do List',
                'onTap': () => _pushStWithPermission(
                  ToDoListScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                  ),
                  stModKey: 'gorev',
                  stSubKey: 'todo_list',
                  title: 'To do List',
                ),
              },
            if (_hasSubModuleAccess('insan_kaynaklari', 'devam_mesai_izin') &&
                _hasStSubAccess('gorev', 'izin_yonetimi'))
              {
                'title': 'İzin Yönetimi',
                'onTap': () => _pushStWithPermission(
                  SchoolTypeLeaveManagementScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                  ),
                  stModKey: 'gorev',
                  stSubKey: 'izin_yonetimi',
                  title: 'İzin Yönetimi',
                ),
              },
            if (_hasStSubAccess('gorev', 'gecici_ogretmen'))
              {
                'title': 'Geçici Öğretmen',
                'onTap': () => _pushStWithPermission(
                  SubstituteTeacherListScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'gorev',
                  stSubKey: 'gecici_ogretmen',
                  title: 'Geçici Öğretmen',
                ),
              },
            if (_hasStSubAccess('gorev', 'nobet_islemleri'))
              {
                'title': 'Nöbet İşlemleri',
                'onTap': () => _pushStWithPermission(
                  DutyManagementScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'gorev',
                  stSubKey: 'nobet_islemleri',
                  title: 'Nöbet İşlemleri',
                ),
              },
            if (_hasStSubAccess('gorev', 'gezi_gorevlendirmeleri'))
              {
                'title': 'Gezi Görevlendirmeleri',
                'onTap': () => _pushStWithPermission(
                  FieldTripListScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'gorev',
                  stSubKey: 'gezi_gorevlendirmeleri',
                  title: 'Gezi Görevlendirmeleri',
                ),
              },
            if (_hasStSubAccess('gorev', 'proje_gorevlendirmeleri'))
              {
                'title': 'Proje Görevlendirmeleri',
                'onTap': () => _pushStWithPermission(
                  ProjectAssignmentListScreen(
                    institutionId: widget.institutionId,
                  ),
                  stModKey: 'gorev',
                  stSubKey: 'proje_gorevlendirmeleri',
                  title: 'Proje Görevlendirmeleri',
                ),
              },
            if (_hasStSubAccess('gorev', 'nobet_cizelgesi'))
              {
                'title': 'Nöbet Çizelgesi',
                'onTap': () => debugPrint('Nöbet Çizelgesi'),
              },
          ],
          onTap: () => setState(() => _selectedCategory = 'Görev'),
        ),
      if (_hasModuleAccess('hizmetler') && _hasStModuleAccess('destek'))
        _ModuleCardWidget(
          key: const ValueKey('destek'),
          title: 'DESTEK HİZMETLERİ',
          badge: 'Destek',
          icon: Icons.support_agent,
          color: Colors.cyan,
          cardWidth: currentCardWidth,
          isMobile: isMobile,
          category: 'Destek',
          showAllItems: isFiltered,
          items: [
            if (_hasSubModuleAccess('hizmetler', 'yemekhane_islemleri') &&
                _hasStSubAccess('destek', 'yemekhane'))
              {
                'title': 'Yemekhane İşlemleri',
                'onTap': () => _pushStWithPermission(
                  CafeteriaScreen(
                    fixedSchoolTypeId: widget.schoolTypeId,
                    fixedSchoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'destek',
                  stSubKey: 'yemekhane',
                  title: 'Yemekhane İşlemleri',
                ),
              },
            if (_hasSubModuleAccess('hizmetler', 'servis_islemleri') &&
                _hasStSubAccess('destek', 'servis'))
              {
                'title': 'Servis İşlemleri',
                'onTap': () => _pushStWithPermission(
                  TransportationScreen(
                    fixedSchoolTypeId: widget.schoolTypeId,
                    fixedSchoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'destek',
                  stSubKey: 'servis',
                  title: 'Servis İşlemleri',
                ),
              },
            if (_hasSubModuleAccess('hizmetler', 'guvenlik_kapi') &&
                _hasStSubAccess('destek', 'guvenlik'))
              {
                'title': 'Güvenlik Kapı & Misafir Giriş-Çıkış',
                'onTap': () => _pushStWithPermission(
                  SecurityGateScreen(
                    fixedInstitutionId: widget.institutionId,
                    fixedSchoolTypeId: widget.schoolTypeId,
                    fixedSchoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'destek',
                  stSubKey: 'guvenlik',
                  title: 'Güvenlik Kapı & Misafir Giriş-Çıkış',
                ),
              },
            if (_hasSubModuleAccess('hizmetler', 'saglik_islemleri') &&
                _hasStSubAccess('destek', 'saglik'))
              {
                'title': 'Sağlık İşlemleri',
                'onTap': () => _pushStWithPermission(
                  HealthScreen(
                    fixedSchoolTypeId: widget.schoolTypeId,
                    fixedSchoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'destek',
                  stSubKey: 'saglik',
                  title: 'Sağlık İşlemleri',
                ),
              },
            if (_hasSubModuleAccess('hizmetler', 'kutuphane_islemleri') &&
                _hasStSubAccess('destek', 'kutuphane'))
              {
                'title': 'Kütüphane İşlemleri',
                'onTap': () => _pushStWithPermission(
                  LibraryScreen(
                    fixedSchoolTypeId: widget.schoolTypeId,
                    fixedSchoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'destek',
                  stSubKey: 'kutuphane',
                  title: 'Kütüphane İşlemleri',
                ),
              },
            if (_hasSubModuleAccess('hizmetler', 'temizlik_islemleri') &&
                _hasStSubAccess('destek', 'temizlik'))
              {
                'title': 'Temizlik İşlemleri',
                'onTap': () => _pushStWithPermission(
                  CleaningScreen(
                    fixedSchoolTypeId: widget.schoolTypeId,
                    fixedSchoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'destek',
                  stSubKey: 'temizlik',
                  title: 'Temizlik İşlemleri',
                ),
              },
            if (_hasSubModuleAccess('hizmetler', 'depo_satin_alma') &&
                _hasStSubAccess('destek', 'depo_satin_alma'))
              {
                'title': 'Depo ve Stok Yönetimi',
                'onTap': () => _pushStWithPermission(
                  InventoryScreen(
                    fixedSchoolTypeId: widget.schoolTypeId,
                    fixedSchoolTypeName: widget.schoolTypeName,
                    initialTabIndex: 0,
                  ),
                  stModKey: 'destek',
                  stSubKey: 'depo_satin_alma',
                  title: 'Depo ve Stok Yönetimi',
                ),
              },
            if ((_hasSubModuleAccess('hizmetler', 'satin_alma_islemleri') ||
                    _hasSubModuleAccess('hizmetler', 'depo_satin_alma')) &&
                (_hasStSubAccess('destek', 'satin_alma') ||
                    _hasStSubAccess('destek', 'depo_satin_alma')))
              {
                'title': 'Satın Alma ve Malzeme Talepleri',
                'onTap': () => _pushStWithPermission(
                  InventoryScreen(
                    fixedSchoolTypeId: widget.schoolTypeId,
                    fixedSchoolTypeName: widget.schoolTypeName,
                    initialTabIndex: 1,
                  ),
                  stModKey: 'destek',
                  stSubKey: 'satin_alma',
                  title: 'Satın Alma ve Malzeme Talepleri',
                ),
              },
            if (_hasStSubAccess('destek', 'envanter'))
              {
                'title': 'Okul Envanteri',
                'onTap': () => debugPrint('Okul Envanteri'),
              },
          ],
          onTap: () => setState(() => _selectedCategory = 'Destek'),
        ),
      if ((_hasModuleAccess('olcme_degerlendirme') ||
              _hasModuleAccess('egitim')) &&
          _hasStModuleAccess('raporlar'))
        _ModuleCardWidget(
          key: const ValueKey('raporlar'),
          title: 'RAPORLAR İŞLEMLERİ',
          badge: 'Rapor',
          icon: Icons.analytics_outlined,
          color: Colors.indigo,
          cardWidth: currentCardWidth,
          isMobile: isMobile,
          category: 'Raporlar',
          showAllItems: isFiltered,
          items: [
            if (_hasSubModuleAccess('insan_kaynaklari', 'devam_mesai_izin') &&
                _hasStSubAccess('raporlar', 'yoklama_raporlari'))
              {
                'title': 'Yoklama Raporları',
                'onTap': () => _pushStWithPermission(
                  AttendanceOperationsScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'raporlar',
                  stSubKey: 'yoklama_raporlari',
                  title: 'Yoklama Raporları',
                ),
              },
            if (_hasSubModuleAccess('egitim', 'ogrenci_kaydi') &&
                _hasStSubAccess('raporlar', 'odev_raporlari'))
              {
                'title': 'Ödev Raporları',
                'onTap': () => _pushStWithPermission(
                  HomeworkOperationsScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                  ),
                  stModKey: 'raporlar',
                  stSubKey: 'odev_raporlari',
                  title: 'Ödev Raporları',
                ),
              },
            if (_hasSubModuleAccess('olcme_degerlendirme', 'raporlar') &&
                _hasStSubAccess('raporlar', 'olcme_raporlari'))
              {
                'title': 'Ölçme Raporları',
                'onTap': () => _pushStWithPermission(
                  AssessmentReportsScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                  ),
                  stModKey: 'raporlar',
                  stSubKey: 'olcme_raporlari',
                  title: 'Ölçme Raporları',
                ),
              },
            if (_hasStSubAccess('raporlar', 'gelisim_istatistikleri'))
              {
                'title': 'Gelişim İstatistikleri',
                'onTap': () => debugPrint('Gelişim İstatistikleri'),
              },
          ],
          onTap: () => setState(() => _selectedCategory = 'Raporlar'),
        ),
      if (_hasModuleAccess('magaza') && _hasStModuleAccess('magaza'))
        _ModuleCardWidget(
          key: const ValueKey('magaza'),
          title: 'MAĞAZA & ONLİNE SATIŞ',
          badge: 'Mağaza',
          icon: Icons.storefront_rounded,
          color: Colors.deepOrange,
          cardWidth: currentCardWidth,
          isMobile: isMobile,
          category: 'Mağaza',
          showAllItems: isFiltered,
          items: [
            if (_hasSubModuleAccess('magaza', 'magaza_alisveris') &&
                _hasStSubAccess('magaza', 'magaza_alisveris'))
              {
                'title': 'Mağaza Vitrini & Online Alışveriş',
                'onTap': () => _pushStWithPermission(
                  StoreShopScreen(
                    institutionId: widget.institutionId,
                    schoolId: schoolData?['id']?.toString(),
                    schoolName:
                        schoolData?['schoolName']?.toString() ??
                        widget.schoolTypeName,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                    buyerRole: 'idareci',
                  ),
                  stModKey: 'magaza',
                  stSubKey: 'magaza_alisveris',
                  title: 'Mağaza Vitrini & Online Alışveriş',
                ),
              },
            if (_hasSubModuleAccess('magaza', 'magaza_urun_yonetimi') &&
                _hasStSubAccess('magaza', 'magaza_urun_yonetimi'))
              {
                'title': 'Okul Ürün & Stok Yönetimi',
                'onTap': () => _pushStWithPermission(
                  SchoolStoreManagementScreen(
                    institutionId: widget.institutionId,
                    schoolId: schoolData?['id']?.toString(),
                    schoolName:
                        schoolData?['schoolName']?.toString() ??
                        widget.schoolTypeName,
                    schoolTypeId: widget.schoolTypeId,
                    initialTabIndex: 0,
                  ),
                  stModKey: 'magaza',
                  stSubKey: 'magaza_urun_yonetimi',
                  title: 'Okul Ürün & Stok Yönetimi',
                ),
              },
            if (_hasSubModuleAccess('magaza', 'magaza_siparis_yonetimi') &&
                _hasStSubAccess('magaza', 'magaza_siparis_yonetimi'))
              {
                'title': 'Sipariş & Teslimat Yönetimi',
                'onTap': () => _pushStWithPermission(
                  SchoolStoreManagementScreen(
                    institutionId: widget.institutionId,
                    schoolId: schoolData?['id']?.toString(),
                    schoolName:
                        schoolData?['schoolName']?.toString() ??
                        widget.schoolTypeName,
                    schoolTypeId: widget.schoolTypeId,
                    initialTabIndex: 1,
                  ),
                  stModKey: 'magaza',
                  stSubKey: 'magaza_siparis_yonetimi',
                  title: 'Sipariş & Teslimat Yönetimi',
                ),
              },
          ],
          onTap: () => _pushStWithPermission(
            SchoolStoreManagementScreen(
              institutionId: widget.institutionId,
              schoolId: schoolData?['id']?.toString(),
              schoolName:
                  schoolData?['schoolName']?.toString() ??
                  widget.schoolTypeName,
              schoolTypeId: widget.schoolTypeId,
            ),
            stModKey: 'magaza',
            title: 'Mağaza & Online Satış',
          ),
        ),
      if (_hasModuleAccess('sistem_ayarlari') && _hasStModuleAccess('ayarlar'))
        _ModuleCardWidget(
          key: const ValueKey('ayarlar'),
          title: 'SİSTEM AYARLARI',
          badge: 'Ayarlar',
          icon: Icons.settings,
          color: Colors.blueGrey,
          cardWidth: currentCardWidth,
          isMobile: isMobile,
          category: 'Ayarlar',
          showAllItems: isFiltered,
          items: [
            if (_hasSubModuleAccess('sistem_ayarlari', 'yetki_tanimlama') &&
                _hasStSubAccess('ayarlar', 'yetki_tanimlama'))
              {
                'title': 'Yetki Tanımlama',
                'onTap': () =>
                    Navigator.pushNamed(context, '/permission-definition'),
              },
            if (_hasSubModuleAccess('sistem_ayarlari', 'kullanici_yonetimi') &&
                _hasStSubAccess('ayarlar', 'kullanici_yetkilendirme'))
              {
                'title': 'Kullanıcı Yetkilendirme',
                'onTap': () => Navigator.pushNamed(context, '/user-management'),
              },
            if (_hasSubModuleAccess('sistem_ayarlari', 'uygulama_ayarlari') &&
                _hasStSubAccess('ayarlar', 'uygulama_ayarlari'))
              {
                'title': 'Uygulama Ayarları',
                'onTap': () => _pushStWithPermission(
                  AppSettingsScreen(
                    initialSchoolTypeId: widget.schoolTypeId,
                    initialSchoolTypeName: widget.schoolTypeName,
                  ),
                  stModKey: 'ayarlar',
                  stSubKey: 'uygulama_ayarlari',
                  title: 'Uygulama Ayarları',
                ).then((_) => _loadSchoolData()),
              },
            if (_hasStSubAccess('ayarlar', 'okul_bilgileri'))
              {
                'title': 'Okul Genel Bilgileri',
                'onTap': () => debugPrint('Okul Bilgileri'),
              },
          ],
          onTap: () => setState(() => _selectedCategory = 'Ayarlar'),
        ),
    ].where((m) => m.items.isNotEmpty).toList();

    final filteredModules = isFiltered
        ? allModules.where((m) => m.category == _selectedCategory).toList()
        : allModules;

    return Wrap(
      key: const ValueKey('stable_modules_grid'),
      spacing: 24,
      runSpacing: 24,
      children: filteredModules,
    );
  }

  Widget _buildTeacherGrid(
    bool isMobile,
    double currentCardWidth,
    bool isFiltered,
  ) {
    final teacherModules = <_ModuleCardWidget>[
      if (_hasTeacherItemAccess('egitim_islemleri'))
        _ModuleCardWidget(
          key: const ValueKey('t_ders'),
          title: 'DERSLERİM VE YOKLAMA',
          badge: 'Ders',
          icon: Icons.class_outlined,
          color: Colors.blue,
          cardWidth: currentCardWidth,
          isMobile: isMobile,
          category: 'Ders',
          showAllItems: isFiltered,
          items: [
            if (_isDailyReportEnabledForType &&
                _hasTeacherItemAccess('egitim_islemleri', 'gunluk_rapor'))
              {
                'title': 'Günlük Rapor (Günlük Karne)',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DailyReportScreen(
                      institutionId: widget.institutionId,
                      fixedSchoolTypeId: widget.schoolTypeId,
                      fixedSchoolTypeName: widget.schoolTypeName,
                    ),
                  ),
                ),
              },
            if (_hasTeacherItemAccess('egitim_islemleri', 'ders_programi'))
              {
                'title': 'Haftalık Ders Programım',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TeacherScheduleViewScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                      schoolTypeName: widget.schoolTypeName,
                      isTeacherView: true,
                    ),
                  ),
                ),
              },
            if (_hasTeacherItemAccess(
              'egitim_islemleri',
              'yoklama_istatistikleri',
            ))
              {
                'title': 'Yoklama Girişi',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AttendanceOperationsScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                      schoolTypeName: widget.schoolTypeName,
                    ),
                  ),
                ),
              },
            if (_hasTeacherItemAccess('egitim_islemleri', 'ders_isleyis_plani'))
              {
                'title': 'Kazanım Takip',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CurriculumTrackingScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                      schoolTypeName: widget.schoolTypeName,
                    ),
                  ),
                ),
              },
            if (_hasTeacherItemAccess(
              'egitim_islemleri',
              'odev_istatistikleri',
            ))
              {
                'title': 'Ödev Takibi',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HomeworkOperationsScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                    ),
                  ),
                ),
              },
            if (_hasTeacherItemAccess('egitim_islemleri', 'etut_islemleri'))
              {
                'title': 'Etütlerim',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EtutProcessScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                      schoolTypeName: widget.schoolTypeName,
                    ),
                  ),
                ),
              },
            if (_hasTeacherItemAccess('egitim_islemleri', 'ders_programi'))
              {
                'title': 'AGM Ders Programım',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AgmDashboardScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                    ),
                  ),
                ),
              },
          ],
          onTap: () => setState(() => _selectedCategory = 'Ders'),
        ),
      if (_hasStModuleAccess('olcme') &&
          _hasTeacherItemAccess('egitim_islemleri'))
        _ModuleCardWidget(
          key: const ValueKey('t_sinav'),
          title: 'SINAV VE BAŞARI',
          badge: 'Sınav',
          icon: Icons.analytics_outlined,
          color: Colors.orange,
          cardWidth: currentCardWidth,
          isMobile: isMobile,
          category: 'Sınav',
          showAllItems: isFiltered,
          items: [
            if (_hasTeacherItemAccess('egitim_islemleri', 'sinav_raporlari') &&
                _hasStSubAccess('olcme', 'raporlar'))
              {
                'title': 'Sınav Sonuç Raporları',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AssessmentReportsScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                    ),
                  ),
                ),
              },
            if (_hasTeacherItemAccess('egitim_islemleri', 'sinav_raporlari'))
              {
                'title': 'AGM Sonuçları',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AgmDashboardScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                    ),
                  ),
                ),
              },
            if (_hasStSubAccess('olcme', 'hata_kitapcigi'))
              {
                'title': 'Hata Kitapçığı Stüdyosu',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ErrorBookletDashboardScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                    ),
                  ),
                ),
              },
            if (_hasStSubAccess('olcme', 'fokus_kitap'))
              {
                'title': 'Fokus Kitap (Kişiye Özel Soru Bankası)',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PersonalizedBookDashboardScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                    ),
                  ),
                ),
              },
            if (_hasStSubAccess('olcme', 'denemeler'))
              {
                'title': 'Deneme Sınavları',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TrialExamListScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                    ),
                  ),
                ),
              },
            if (_hasStSubAccess('olcme', 'soru_havuzu'))
              {
                'title': 'Soru Havuzu',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => QuestionPoolScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                    ),
                  ),
                ),
              },
          ],
          onTap: () => setState(() => _selectedCategory = 'Sınav'),
        ),
      if (_hasTeacherItemAccess('rehberlik_islemleri'))
        _ModuleCardWidget(
          key: const ValueKey('t_ogrenci'),
          title: 'ÖĞRENCİ VE REHBERLİK',
          badge: 'Rehberlik',
          icon: Icons.face_outlined,
          color: Colors.purple,
          cardWidth: currentCardWidth,
          isMobile: isMobile,
          category: 'Rehberlik',
          showAllItems: isFiltered,
          items: [
            if (_hasTeacherItemAccess(
              'rehberlik_islemleri',
              'ogrenci_portfolyolari',
            ))
              {
                'title': 'Öğrenci Portfolyosu',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PortfolioScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                      schoolTypeName: widget.schoolTypeName,
                    ),
                  ),
                ),
              },
            if (_hasTeacherItemAccess('rehberlik_islemleri', 'gorusmeler'))
              {
                'title': 'Görüşme Kayıtları',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GuidanceInterviewScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                      schoolTypeName: widget.schoolTypeName,
                    ),
                  ),
                ),
              },
            if (_hasStSubAccess('rehberlik', 'talepler'))
              {
                'title': 'Rehberlik Taleplerim',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DemandDashboardScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                    ),
                  ),
                ),
              },
            if (_hasTeacherItemAccess(
              'rehberlik_islemleri',
              'gozlem_ve_etkinlik',
            ))
              {
                'title': 'Toplu Gözlem Girişi',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ActivityListScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                      schoolTypeName: widget.schoolTypeName,
                    ),
                  ),
                ),
              },
            if (_hasTeacherItemAccess('egitim_islemleri', 'anket_islemleri'))
              {
                'title': 'Anket Uygulama',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SurveyListScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                      schoolTypeName: widget.schoolTypeName,
                    ),
                  ),
                ),
              },
          ],
          onTap: () => setState(() => _selectedCategory = 'Rehberlik'),
        ),
      if (_hasTeacherItemAccess('gorevlendirme_ve_izin'))
        _ModuleCardWidget(
          key: const ValueKey('t_idari'),
          title: 'İDARİ VE GÖREVLER',
          badge: 'Görev',
          icon: Icons.assignment_ind_outlined,
          color: Colors.teal,
          cardWidth: currentCardWidth,
          isMobile: isMobile,
          category: 'Görev',
          showAllItems: isFiltered,
          items: [
            if (_hasTeacherItemAccess(
              'gorevlendirme_ve_izin',
              'izin_islemleri',
            ))
              {
                'title': 'İzin Taleplerim',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SchoolTypeLeaveManagementScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                    ),
                  ),
                ),
              },
            if (_hasTeacherItemAccess('gorevlendirme_ve_izin', 'nobetlerim'))
              {
                'title': 'Nöbet Programım',
                'onTap': () => debugPrint('Nöbetlerim'),
              },
            if (_hasTeacherItemAccess(
              'gorevlendirme_ve_izin',
              'gezi_gorevlendirmeleri',
            ))
              {
                'title': 'Gezi Görevlerim',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FieldTripListScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                      schoolTypeName: widget.schoolTypeName,
                    ),
                  ),
                ),
              },
            if (_hasTeacherItemAccess('gorevlendirme_ve_izin', 'yapilacaklar'))
              {
                'title': 'To-Do List',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ToDoListScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                    ),
                  ),
                ),
              },
            if (_hasStSubAccess('kisisel', 'profilim'))
              {
                'title': 'Profil Bilgilerim',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => const UserProfileScreen(),
                  ),
                ),
              },
          ],
          onTap: () => setState(() => _selectedCategory = 'Görev'),
        ),
      if (_hasTeacherItemAccess('araclar'))
        _ModuleCardWidget(
          key: const ValueKey('t_araclar'),
          title: 'ARAÇLAR',
          badge: 'Araçlar',
          icon: Icons.build_circle_outlined,
          color: Colors.amber.shade700,
          cardWidth: currentCardWidth,
          isMobile: isMobile,
          category: 'Araçlar',
          showAllItems: isFiltered,
          items: [
            if (_hasTeacherItemAccess('araclar', 'sinif_ici_yonetim'))
              {
                'title': 'Sınıf İçi Yönetim ve Etkileşim',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ToolsHubScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                      schoolTypeName: widget.schoolTypeName,
                      initialCategoryIndex: 0,
                      isTeacher: true,
                    ),
                  ),
                ),
              },
            if (_hasTeacherItemAccess('araclar', 'ogrenci_hareket_takip'))
              {
                'title': 'Geç - İzin - Revir - Görüşme (Canlı İzleme)',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ToolsHubScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                      schoolTypeName: widget.schoolTypeName,
                      initialCategoryIndex: 4,
                      isTeacher: true,
                    ),
                  ),
                ),
              },
            if (_hasTeacherItemAccess('araclar', 'notlarim'))
              {
                'title': 'Notlarım',
                'onTap': () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PersonalNotesScreen(),
                  ),
                ),
              },
          ],
          onTap: () {
            if (_selectedCategory == 'Araçlar') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ToolsHubScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                    initialCategoryIndex: 0,
                    isTeacher: true,
                  ),
                ),
              );
            } else {
              setState(() => _selectedCategory = 'Araçlar');
            }
          },
        ),
      if (_hasTeacherItemAccess('destek_birimi') &&
          _hasTeacherItemAccess('destek_birimi', 'malzeme_talep'))
        _ModuleCardWidget(
          key: const ValueKey('t_destek'),
          title: 'DESTEK BİRİMİ',
          badge: 'Destek',
          icon: Icons.support_agent_rounded,
          color: const Color(0xFF0D9488),
          cardWidth: currentCardWidth,
          isMobile: isMobile,
          category: 'Destek',
          showAllItems: isFiltered,
          items: [
            {
              'title': 'Malzeme Talep',
              'onTap': () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TeacherMaterialRequestsScreen(
                    institutionId: widget.institutionId,
                    fixedSchoolTypeId: widget.schoolTypeId,
                    fixedSchoolTypeName: widget.schoolTypeName,
                  ),
                ),
              ),
            },
          ],
          onTap: () => setState(() => _selectedCategory = 'Destek'),
        ),
      if (_hasModuleAccess('magaza') && _hasStModuleAccess('magaza'))
        _ModuleCardWidget(
          key: const ValueKey('t_magaza'),
          title: 'MAĞAZA & ONLİNE SATIŞ',
          badge: 'Mağaza',
          icon: Icons.storefront_rounded,
          color: Colors.deepOrange,
          cardWidth: currentCardWidth,
          isMobile: isMobile,
          category: 'Mağaza',
          showAllItems: isFiltered,
          items: [
            {
              'title': 'Mağaza Vitrini & Online Alışveriş',
              'onTap': () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => StoreShopScreen(
                    institutionId: widget.institutionId,
                    schoolId: schoolData?['id']?.toString(),
                    schoolName:
                        schoolData?['schoolName']?.toString() ??
                        widget.schoolTypeName,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                    buyerRole: 'ogretmen',
                  ),
                ),
              ),
            },
          ],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StoreShopScreen(
                institutionId: widget.institutionId,
                schoolId: schoolData?['id']?.toString(),
                schoolName:
                    schoolData?['schoolName']?.toString() ??
                    widget.schoolTypeName,
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
                buyerRole: 'ogretmen',
              ),
            ),
          ),
        ),
    ].where((m) => m.items.isNotEmpty).toList();

    final filteredModules = teacherModules
        .where(
          (m) => _selectedCategory == 'Tümü' || m.category == _selectedCategory,
        )
        .toList();

    return Wrap(
      spacing: isMobile ? 0 : 24,
      runSpacing: isMobile ? 12 : 24,
      children: filteredModules,
    );
  }

  Widget _buildCategorySelector(bool isMobile) {
    final categories = [
      {'label': 'Tümü', 'icon': Icons.grid_view_rounded},
      if (isTeacher
          ? _hasTeacherItemAccess('siniflar_subeler')
          : ((_hasModuleAccess('egitim') ||
                    _hasModuleAccess('insan_kaynaklari')) &&
                _hasStModuleAccess('kayit')))
        {'label': 'Kayıt', 'icon': Icons.app_registration},
      if (isTeacher
          ? (_hasTeacherItemAccess('ders_programi') ||
                _hasTeacherItemAccess('yoklama_islemleri') ||
                _hasTeacherItemAccess('odev_islemleri') ||
                _hasTeacherItemAccess('etut_islemleri') ||
                _hasTeacherItemAccess('ogrenci_portfolyosu') ||
                _hasTeacherItemAccess('calisma_takvimi') ||
                _hasTeacherItemAccess('kazanim_takip') ||
                _hasTeacherItemAccess('proje_gorevlendirmeleri'))
          : (_hasModuleAccess('egitim') && _hasStModuleAccess('egitim')))
        {'label': 'Eğitim', 'icon': Icons.school},
      if (isTeacher
          ? _hasTeacherItemAccess('rehberlik_envanterleri')
          : (_hasModuleAccess('rehberlik') && _hasStModuleAccess('rehberlik')))
        {'label': 'Rehberlik', 'icon': Icons.folder_special},
      if (isTeacher
          ? _hasTeacherItemAccess('olcme_degerlendirme')
          : (_hasModuleAccess('olcme_degerlendirme') &&
                _hasStModuleAccess('olcme')))
        {'label': 'Ölçme', 'icon': Icons.bar_chart},
      if (isTeacher
          ? _hasTeacherItemAccess('araclar')
          : _hasStModuleAccess('araclar'))
        {'label': 'Araçlar', 'icon': Icons.build_circle_outlined},
      if (isTeacher
          ? (_hasTeacherItemAccess('gorevlerim_izinler') ||
                _hasTeacherItemAccess('nobet_cizelgesi'))
          : (_hasModuleAccess('insan_kaynaklari') &&
                _hasStModuleAccess('gorev')))
        {'label': 'Görev', 'icon': Icons.assignment_ind},
      if (isTeacher
          ? _hasTeacherItemAccess('destek_birimi')
          : (_hasModuleAccess('hizmetler') && _hasStModuleAccess('destek')))
        {'label': 'Destek', 'icon': Icons.support_agent},
      if (!isTeacher &&
          (_hasModuleAccess('olcme_degerlendirme') ||
              _hasModuleAccess('egitim')) &&
          _hasStModuleAccess('raporlar'))
        {'label': 'Raporlar', 'icon': Icons.analytics_outlined},
      if (_hasModuleAccess('magaza') && _hasStModuleAccess('magaza'))
        {'label': 'Mağaza', 'icon': Icons.storefront_rounded},
      if (!isTeacher &&
          _hasModuleAccess('sistem_ayarlari') &&
          _hasStModuleAccess('ayarlar'))
        {'label': 'Ayarlar', 'icon': Icons.settings},
    ];

    final screenWidth = MediaQuery.of(context).size.width;
    const double maxLayoutWidth = 1400.0;
    final double contentWidth = screenWidth > maxLayoutWidth
        ? maxLayoutWidth
        : screenWidth;
    final double availableWidth = contentWidth - (isMobile ? 32 : 48);

    return Container(
      width: double.infinity,
      height: 100,
      color: Colors.white.withValues(alpha: 0.5),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            constraints: BoxConstraints(
              minWidth: availableWidth.isNegative ? 0.0 : availableWidth,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: categories.map((cat) {
                final isSelected = _selectedCategory == cat['label'];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: InkWell(
                    onTap: () => setState(
                      () => _selectedCategory = cat['label'] as String,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      width: isMobile ? 75 : 80,
                      height: isMobile ? 75 : 80,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF3F51B5)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isSelected ? 0.2 : 0.03,
                            ),
                            blurRadius: isSelected ? 12 : 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: isSelected
                              ? Colors.indigo
                              : Colors.indigo.withValues(alpha: 0.05),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            cat['icon'] as IconData,
                            color: isSelected
                                ? Colors.white
                                : Colors.indigo.shade400,
                            size: isMobile ? 20 : 24,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            cat['label'] as String,
                            style: TextStyle(
                              fontSize: isMobile ? 9 : 10,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.blueGrey.shade600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  bool _hasLingoknAccess() {
    final role = userData?['role']?.toString().toLowerCase() ?? '';
    if (['super_admin', 'admin', 'manager', 'genel_mudur'].contains(role)) {
      return true;
    }

    if (schoolData == null) return false;
    final access = schoolData!['lingoknAccess'] as Map<String, dynamic>?;
    if (access == null) return false;

    if (access['enabledAll'] == true) return true;

    final userClass = userData?['className'] ?? userData?['class'] ?? '';
    final userId = FirebaseAuth.instance.currentUser?.uid;

    final allowedClassIds = List<String>.from(access['allowedClassIds'] ?? []);
    final allowedUserIds = List<String>.from(access['allowedUserIds'] ?? []);
    final allowedTeacherIds = List<String>.from(
      access['allowedTeacherIds'] ?? [],
    );

    if (allowedClassIds.contains(userClass)) return true;
    if (userId != null && allowedUserIds.contains(userId)) return true;
    if (userId != null &&
        role == 'ogretmen' &&
        allowedTeacherIds.contains(userId))
      return true;

    return false;
  }

  void _showLingoknAccessDialog() async {
    final schoolId =
        schoolData?['id'] ??
        schoolData?['institutionId'] ??
        widget.institutionId;
    if (schoolId == null) return;

    Map<String, dynamic> access = Map<String, dynamic>.from(
      schoolData?['lingoknAccess'] ?? {},
    );
    bool enabledAll = access['enabledAll'] == true;
    List<String> allowedClassIds = List<String>.from(
      access['allowedClassIds'] ?? [],
    );

    final classesSnap = await FirebaseFirestore.instance
        .collection('classes')
        .where('schoolId', isEqualTo: schoolId)
        .get();

    final classNames = classesSnap.docs
        .map(
          (d) =>
              d.data()['className']?.toString() ??
              d.data()['name']?.toString() ??
              d.id,
        )
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Row(
                children: [
                  Icon(Icons.translate_rounded, color: Colors.teal),
                  SizedBox(width: 8),
                  Text('LinGoKN Erişim Yönetimi'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: const Text('Tüm Okula Erişimi Aç'),
                      subtitle: const Text(
                        'Tüm öğretmen ve öğrenciler LinGoKN portalına geçiş yapabilir.',
                      ),
                      value: enabledAll,
                      activeThumbColor: Colors.teal,
                      onChanged: (val) =>
                          setDialogState(() => enabledAll = val),
                    ),
                    const Divider(),
                    if (!enabledAll) ...[
                      const Text(
                        'Sınıf Bazlı İzinler:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      if (classNames.isEmpty)
                        const Text(
                          'Kayıtlı sınıf bulunamadı.',
                          style: TextStyle(color: Colors.grey),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          children: classNames.map((className) {
                            final isSelected = allowedClassIds.contains(
                              className,
                            );
                            return FilterChip(
                              label: Text(className),
                              selected: isSelected,
                              selectedColor: Colors.teal.shade100,
                              onSelected: (selected) {
                                setDialogState(() {
                                  if (selected) {
                                    allowedClassIds.add(className);
                                  } else {
                                    allowedClassIds.remove(className);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () async {
                    final updatedAccess = {
                      'enabledAll': enabledAll,
                      'allowedClassIds': allowedClassIds,
                      'allowedUserIds': access['allowedUserIds'] ?? [],
                      'allowedTeacherIds': access['allowedTeacherIds'] ?? [],
                    };

                    final schoolDocRef = FirebaseFirestore.instance
                        .collection('schools')
                        .doc(schoolId);
                    await schoolDocRef.set({
                      'lingoknAccess': updatedAccess,
                    }, SetOptions(merge: true));

                    if (mounted) {
                      setState(() {
                        if (schoolData != null) {
                          schoolData!['lingoknAccess'] = updatedAccess;
                        }
                      });
                      if (mounted) Navigator.pop(context);
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'LinGoKN erişim izinleri başarıyla güncellendi.',
                            ),
                          ),
                        );
                    }
                  },
                  child: const Text(
                    'Kaydet',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _launchDilknSso() async {
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
                Text(
                  'LinGoKN Portalına güvenli yönlendirme yapılıyor...',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
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
}

// ============== DASHBOARD TAB ==============
class _DashboardTab extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;
  final Map<String, dynamic>? userData;

  const _DashboardTab({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
    this.userData,
  }) : super(key: key);

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWideScreen = constraints.maxWidth > 900;

        if (isWideScreen) {
          return Row(
            children: [
              // Sol Panel: Bildirimler
              Expanded(
                flex: 2,
                child: SharedNotificationSection(
                  schoolTypeId: widget.schoolTypeId,
                  institutionId: widget.institutionId,
                  userData: widget.userData,
                ),
              ),
              // Sağ Panel: Takvim
              Expanded(
                flex: 3,
                child: SharedCalendarSection(
                  schoolTypeId: widget.schoolTypeId,
                  institutionId: widget.institutionId,
                  userData: widget.userData,
                ),
              ),
            ],
          );
        } else {
          return DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Container(
                  color: Colors.white,
                  child: TabBar(
                    labelColor: Colors.blue.shade700,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Colors.blue.shade700,
                    indicatorSize: TabBarIndicatorSize.label,
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_none_rounded, size: 20),
                            SizedBox(width: 8),
                            Text('Bildirimler'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 18),
                            SizedBox(width: 8),
                            Text('Takvim'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      SharedNotificationSection(
                        schoolTypeId: widget.schoolTypeId,
                        institutionId: widget.institutionId,
                        userData: widget.userData,
                      ),
                      SharedCalendarSection(
                        schoolTypeId: widget.schoolTypeId,
                        institutionId: widget.institutionId,
                        userData: widget.userData,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
      },
    );
  }
}

class SharedNotificationSection extends StatefulWidget {
  final String schoolTypeId;
  final String institutionId;
  final Map<String, dynamic>? userData;

  const SharedNotificationSection({
    Key? key,
    required this.schoolTypeId,
    required this.institutionId,
    this.userData,
  }) : super(key: key);

  @override
  State<SharedNotificationSection> createState() =>
      _SharedNotificationSectionState();
}

class _SharedNotificationSectionState extends State<SharedNotificationSection> {
  static final Map<String, List<Map<String, dynamic>>> _memoryNotifCache = {};
  static final Set<String> _memoryDismissedIds = {};
  List<Map<String, dynamic>> _cachedItems = [];
  Set<String> _dismissedIds = {};

  String _getCacheKey() => '${widget.institutionId}_${widget.schoolTypeId}';

  String _getDismissPrefsKey() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
    return 'edukn_shared_dismissed_notifs_$uid';
  }

  /// Ziyaretçi Giriş/Çıkış, Güvenlik Kapı Çıkış Onayı, Öğrenci Çıkış İzni, Erken Alma ve Revir
  /// gibi operasyonel bildirimleri tespit eder (eski takılı kalmış kayıtlar dahil).
  static bool _isOperationalMovementData(Map<String, dynamic> data) {
    if (data['isOperationalNotification'] == true) return true;
    if (data['category'] == 'gate_movement') return true;
    final entityId = (data['entityId'] ?? '').toString().trim();
    if (entityId.isNotEmpty) return true;

    final rawType = (data['type'] ?? '').toString().toLowerCase();
    if (rawType.startsWith('visitor_') ||
        rawType.startsWith('student_exit_') ||
        rawType.startsWith('early_pickup_') ||
        rawType.startsWith('infirmary_') ||
        rawType.startsWith('student_late_') ||
        rawType.startsWith('student_interview_')) {
      return true;
    }

    final text = '${data['title'] ?? ''} ${data['subtitle'] ?? ''}';
    const operationalMarkers = [
      'Ziyaretçi Giriş',
      'Ziyaretçi Çıkış',
      'Öğrenci Çıkış İzni',
      'Güvenlik Çıkış Onayı',
      'Veliye Erken Teslim',
      'Veli Kapıda Bekliyor',
      'Erken Alma Ön Bildirimi',
      'Veli Okula Ulaştı',
      'VELİ OKULA GELDİ',
      'Yeni Revir Sevki',
      'Geç Kağıdı Verildi',
    ];
    for (final marker in operationalMarkers) {
      if (text.contains(marker)) return true;
    }
    return false;
  }

  bool _canCurrentUserSeeLegacyOperationalActivity() {
    final role = (widget.userData?['role'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final title = (widget.userData?['title'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    return role == 'mudur' ||
        role == 'mudur_yardimcisi' ||
        role == 'genel_mudur' ||
        role == 'admin' ||
        role.contains('guvenlik') ||
        title.contains('müdür') ||
        title.contains('mudur') ||
        title.contains('güvenlik') ||
        title.contains('guvenlik');
  }

  @override
  void initState() {
    super.initState();
    _dismissedIds = Set<String>.from(_memoryDismissedIds);
    _loadDismissedIds();

    final key = _getCacheKey();
    if (_memoryNotifCache.containsKey(key)) {
      _cachedItems = _sanitizeCachedList(_memoryNotifCache[key]!);
    } else {
      _loadFromDiskCache(key);
    }
  }

  List<Map<String, dynamic>> _sanitizeCachedList(
    List<Map<String, dynamic>> raw,
  ) {
    return raw.where((item) {
      if (widget.schoolTypeId.isEmpty && _isOperationalMovementData(item)) {
        return false;
      }
      final id = (item['id'] ?? '').toString();
      if (id.isNotEmpty && _dismissedIds.contains(id)) return false;
      return true;
    }).toList();
  }

  Future<void> _loadDismissedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_getDismissPrefsKey()) ?? const [];
      if (saved.isNotEmpty) {
        _memoryDismissedIds.addAll(saved);
        if (mounted) {
          setState(() {
            _dismissedIds = Set<String>.from(_memoryDismissedIds);
            _cachedItems = _sanitizeCachedList(_cachedItems);
          });
        }
      }
    } catch (silentError) {
      debugPrint('[school_type_detail_screen] hata yutuldu: $silentError');
    }
  }

  Future<void> _dismissNotificationItem(String notifId) async {
    if (notifId.isEmpty) return;
    try {
      _memoryDismissedIds.add(notifId);
      if (mounted) {
        setState(() {
          _dismissedIds.add(notifId);
          _cachedItems.removeWhere(
            (e) => (e['id'] ?? '').toString() == notifId,
          );
        });
      }

      if (notifId.startsWith('unotif_')) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        final docId = notifId.substring('unotif_'.length);
        if (uid != null && docId.isNotEmpty) {
          FirebaseFirestore.instance
              .collection('notifications')
              .doc(uid)
              .collection('items')
              .doc(docId)
              .update({'isRead': true})
              .catchError((_) {});
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final trimmed = _memoryDismissedIds.toList();
      if (trimmed.length > 400) {
        trimmed.removeRange(0, trimmed.length - 400);
      }
      await prefs.setStringList(_getDismissPrefsKey(), trimmed);
      await _saveToDiskCache(_getCacheKey(), _cachedItems);
    } catch (silentError) {
      debugPrint('[school_type_detail_screen] hata yutuldu: $silentError');
    }
  }

  Future<void> _dismissAllVisibleItems(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      for (final notifId in ids) {
        _memoryDismissedIds.add(notifId);
        if (uid != null && notifId.startsWith('unotif_')) {
          final docId = notifId.substring('unotif_'.length);
          if (docId.isNotEmpty) {
            FirebaseFirestore.instance
                .collection('notifications')
                .doc(uid)
                .collection('items')
                .doc(docId)
                .update({'isRead': true})
                .catchError((_) {});
          }
        }
      }
      if (mounted) {
        setState(() {
          _dismissedIds.addAll(ids);
          _cachedItems.removeWhere(
            (e) => ids.contains((e['id'] ?? '').toString()),
          );
        });
      }
      final prefs = await SharedPreferences.getInstance();
      final trimmed = _memoryDismissedIds.toList();
      if (trimmed.length > 400) {
        trimmed.removeRange(0, trimmed.length - 400);
      }
      await prefs.setStringList(_getDismissPrefsKey(), trimmed);
      await _saveToDiskCache(_getCacheKey(), _cachedItems);
    } catch (silentError) {
      debugPrint('[school_type_detail_screen] hata yutuldu: $silentError');
    }
  }

  Future<void> _loadFromDiskCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('edukn_notif_cache_$key');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List decoded = json.decode(jsonStr);
        final list = _sanitizeCachedList(
          decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        );
        if (mounted && list.isNotEmpty) {
          setState(() {
            _cachedItems = list;
            _memoryNotifCache[key] = list;
          });
        }
      }
    } catch (silentError) {
      debugPrint('[school_type_detail_screen] hata yutuldu: $silentError');
    }
  }

  Future<void> _saveToDiskCache(
    String key,
    List<Map<String, dynamic>> items,
  ) async {
    try {
      final clean = _sanitizeCachedList(items);
      _memoryNotifCache[key] = clean;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('edukn_notif_cache_$key', json.encode(clean));
    } catch (silentError) {
      debugPrint('[school_type_detail_screen] hata yutuldu: $silentError');
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = (widget.userData?['role'] as String?)?.toLowerCase();
    final isTeacher = role == 'ogretmen' || role == 'öğretmen';
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Container(
      padding: const EdgeInsets.all(16),
      child: SafeStreamBuilder<QuerySnapshot>(
        stream: currentUid != null
            ? FirebaseFirestore.instance
                  .collection('conversations')
                  .where('participantIds', arrayContains: currentUid)
                  .snapshots()
            : const Stream.empty(),
        builder: (context, chatSnapshot) {
          int unreadMessagesCount = 0;
          int missedCallsCount = 0;

          if (chatSnapshot.hasData && currentUid != null) {
            for (var doc in chatSnapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final unreadCounts =
                  data['unreadCounts'] as Map<String, dynamic>? ?? {};
              final count = (unreadCounts[currentUid] as num?)?.toInt() ?? 0;

              if (count > 0) {
                final lastMsg = data['lastMessage'] as Map<String, dynamic>?;
                if (lastMsg != null) {
                  final type = lastMsg['type'] as String?;
                  final content = lastMsg['content'] as String? ?? '';
                  final senderId = lastMsg['senderId'] as String?;

                  if (type == 'call' &&
                      content.contains('Cevapsız') &&
                      senderId != currentUid) {
                    missedCallsCount += 1;
                    if (count > 1) {
                      unreadMessagesCount += (count - 1);
                    }
                  } else {
                    unreadMessagesCount += count;
                  }
                } else {
                  unreadMessagesCount += count;
                }
              }
            }
          }

          // Okul Türü içerisindeyken (`widget.schoolTypeId.isNotEmpty`) kullanıcının
          // hedefe yönelik kişisel bildirimlerini (`notifications/{uid}/items`) de dinle.
          // Genel Kısımda (`widget.schoolTypeId.isEmpty`) kesinlikle dinleme / gösterme!
          final Stream<QuerySnapshot> personalNotifStream =
              (currentUid != null && widget.schoolTypeId.isNotEmpty)
              ? FirebaseFirestore.instance
                    .collection('notifications')
                    .doc(currentUid)
                    .collection('items')
                    .orderBy('createdAt', descending: true)
                    .limit(30)
                    .snapshots()
              : const Stream.empty();

          return SafeStreamBuilder<QuerySnapshot>(
            stream: personalNotifStream,
            builder: (context, personalSnapshot) {
              return SafeStreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('activities')
                    .where('institutionId', isEqualTo: widget.institutionId)
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  final isActivitiesWaiting =
                      snapshot.connectionState == ConnectionState.waiting;
                  final isChatWaiting =
                      chatSnapshot.connectionState == ConnectionState.waiting;

                  // 1. Okul Türü İçi Hedefli Anlık Bildirimler (`notifications/{uid}/items`)
                  final List<Map<String, dynamic>> targetedList = [];
                  final Set<String> seenOperationalEntities = {};
                  if (widget.schoolTypeId.isNotEmpty &&
                      personalSnapshot.hasData) {
                    final sevenDaysAgo = DateTime.now().subtract(
                      const Duration(days: 7),
                    );
                    for (final pDoc in personalSnapshot.data!.docs) {
                      final pData = pDoc.data() as Map<String, dynamic>;
                      if (pData['isRead'] == true) continue;
                      final itemId = 'unotif_${pDoc.id}';
                      if (_dismissedIds.contains(itemId)) continue;

                      final pStId = (pData['schoolTypeId'] ?? '')
                          .toString()
                          .trim();
                      if (pStId != widget.schoolTypeId) continue;

                      final ts = pData['createdAt'] as Timestamp?;
                      final dt = ts?.toDate() ?? DateTime.now();
                      if (dt.isBefore(sevenDaysAgo)) continue;

                      final entId = (pData['entityId'] ?? '').toString().trim();
                      if (entId.isNotEmpty) {
                        seenOperationalEntities.add(entId);
                      }

                      final rawType = (pData['type'] ?? 'gate_notif')
                          .toString();
                      targetedList.add({
                        'id': itemId,
                        'title': (pData['title'] ?? 'Bildirim').toString(),
                        'subtitle': (pData['body'] ?? pData['message'] ?? '')
                            .toString(),
                        'time': DateFormat('dd.MM HH:mm').format(dt),
                        'type': rawType,
                      });
                    }
                  }

                  // 2. Duyuru / Etkinlik Akışı (`activities`)
                  List<Map<String, dynamic>> announcementList = [];
                  if (snapshot.hasData) {
                    final docs = snapshot.data?.docs ?? [];
                    final filteredDocs = docs
                        .where((doc) {
                          final itemId = 'act_${doc.id}';
                          if (_dismissedIds.contains(itemId)) return false;

                          final data = doc.data() as Map<String, dynamic>;
                          final isOperational = _isOperationalMovementData(
                            data,
                          );

                          // KURAL 1: Genel Kısımda (`schoolTypeId.isEmpty`) hiçbir Ziyaretçi / Güvenlik /
                          // Öğrenci Çıkış İzni / Erken Alma / Revir bildirimi GÖSTERİLMEZ!
                          if (widget.schoolTypeId.isEmpty && isOperational) {
                            return false;
                          }

                          final sId = (data['schoolTypeId'] ?? '')
                              .toString()
                              .trim();

                          // KURAL 2: Okul Türü içerisindeyken `schoolTypeId` eşleşmeyen hiçbir kaydı gösterme;
                          // operasyonel bir eski kayıtsa boş `sId` olsa dahi gösterme ve yalnızca idare/güvenliğe göster.
                          if (widget.schoolTypeId.isNotEmpty) {
                            if (isOperational) {
                              if (sId.isEmpty || sId != widget.schoolTypeId) {
                                return false;
                              }
                              if (!_canCurrentUserSeeLegacyOperationalActivity()) {
                                return false;
                              }
                              final entId = (data['entityId'] ?? '')
                                  .toString()
                                  .trim();
                              if (entId.isNotEmpty &&
                                  seenOperationalEntities.contains(entId)) {
                                return false;
                              }
                            } else if (sId.isNotEmpty &&
                                sId != widget.schoolTypeId) {
                              return false;
                            }
                          }

                          final createdAtTs = data['createdAt'] as Timestamp?;
                          if (createdAtTs != null) {
                            final difference = DateTime.now().difference(
                              createdAtTs.toDate(),
                            );
                            if (difference.inDays > 30) return false;
                          } else {
                            return false;
                          }

                          if (isTeacher) {
                            final targetRoles =
                                data['targetRoles'] as List<dynamic>?;
                            if (targetRoles != null &&
                                !targetRoles.contains('ogretmen') &&
                                !targetRoles.contains('öğretmen')) {
                              return false;
                            }
                          }
                          return true;
                        })
                        .take(15)
                        .toList();

                    for (var doc in filteredDocs) {
                      final data = doc.data() as Map<String, dynamic>;
                      final title = data['title'] ?? 'Duyuru';
                      final type = data['type'] ?? 'Genel';
                      final ts = data['createdAt'] as Timestamp?;
                      final timeStr = ts != null
                          ? DateFormat('HH:mm').format(ts.toDate())
                          : '';
                      announcementList.add({
                        'id': 'act_${doc.id}',
                        'title': title.toString(),
                        'subtitle': '$type - $timeStr',
                        'time': ts != null
                            ? DateFormat('dd.MM').format(ts.toDate())
                            : '',
                        'type': type == 'Önemli' ? 'announcement' : 'report',
                      });
                    }
                    _saveToDiskCache(_getCacheKey(), announcementList);
                  } else if (_cachedItems.isNotEmpty) {
                    announcementList = _sanitizeCachedList(_cachedItems);
                  }

                  final List<Widget> items = [];
                  final List<String> visibleDismissibleIds = [];

                  final unreadChatId = 'chat_unread_$unreadMessagesCount';
                  if (unreadMessagesCount > 0 &&
                      !_dismissedIds.contains(unreadChatId)) {
                    visibleDismissibleIds.add(unreadChatId);
                    items.add(
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                schoolTypeId: widget.schoolTypeId.isEmpty
                                    ? ''
                                    : widget.schoolTypeId,
                                schoolTypeName: widget.schoolTypeId.isEmpty
                                    ? 'Tüm Okul Türleri'
                                    : widget.schoolTypeId,
                                institutionId: widget.institutionId,
                              ),
                            ),
                          );
                        },
                        child: _buildNotificationCard(
                          id: unreadChatId,
                          title: 'Okunmamış Mesaj',
                          subtitle:
                              '$unreadMessagesCount adet okunmamış mesajınız bulunmaktadır.',
                          time: DateFormat('HH:mm').format(DateTime.now()),
                          type: 'chat_message',
                        ),
                      ),
                    );
                  }

                  final missedCallId = 'chat_missed_$missedCallsCount';
                  if (missedCallsCount > 0 &&
                      !_dismissedIds.contains(missedCallId)) {
                    visibleDismissibleIds.add(missedCallId);
                    items.add(
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                schoolTypeId: widget.schoolTypeId.isEmpty
                                    ? ''
                                    : widget.schoolTypeId,
                                schoolTypeName: widget.schoolTypeId.isEmpty
                                    ? 'Tüm Okul Türleri'
                                    : widget.schoolTypeId,
                                institutionId: widget.institutionId,
                              ),
                            ),
                          );
                        },
                        child: _buildNotificationCard(
                          id: missedCallId,
                          title: 'Cevapsız Çağrı',
                          subtitle:
                              '$missedCallsCount adet cevapsız çağrınız bulunmaktadır.',
                          time: DateFormat('HH:mm').format(DateTime.now()),
                          type: 'chat_call',
                        ),
                      ),
                    );
                  }

                  for (final tItem in targetedList) {
                    final id = (tItem['id'] ?? '').toString();
                    if (id.isNotEmpty) visibleDismissibleIds.add(id);
                    items.add(
                      GestureDetector(
                        onTap: () => _showNotificationDetailDialog(
                          id: id,
                          title: tItem['title'] ?? 'Bildirim',
                          subtitle: tItem['subtitle'] ?? '',
                        ),
                        child: _buildNotificationCard(
                          id: id,
                          title: tItem['title'] ?? 'Bildirim',
                          subtitle: tItem['subtitle'] ?? '',
                          time: tItem['time'] ?? '',
                          type: tItem['type'] ?? 'gate_notif',
                        ),
                      ),
                    );
                  }

                  for (var ann in announcementList) {
                    final fallbackId =
                        'legacy_${ann['title'] ?? ''}_${ann['time'] ?? ''}';
                    final id = (ann['id'] ?? fallbackId).toString();
                    if (_dismissedIds.contains(id)) continue;
                    visibleDismissibleIds.add(id);
                    items.add(
                      GestureDetector(
                        onTap: () => _showNotificationDetailDialog(
                          id: id,
                          title: ann['title'] ?? 'Duyuru',
                          subtitle: ann['subtitle'] ?? '',
                        ),
                        child: _buildNotificationCard(
                          id: id,
                          title: ann['title'] ?? 'Duyuru',
                          subtitle: ann['subtitle'] ?? '',
                          time: ann['time'] ?? '',
                          type: ann['type'] ?? 'report',
                        ),
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'DUYURULAR VE BİLDİRİMLER',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade600,
                                  letterSpacing: 1.1,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (visibleDismissibleIds.isNotEmpty)
                              TextButton.icon(
                                onPressed: () => _dismissAllVisibleItems(
                                  visibleDismissibleIds,
                                ),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: Colors.grey.shade600,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.clear_all_rounded,
                                  size: 16,
                                ),
                                label: const Text(
                                  'Tümünü Kapat',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: items.isEmpty
                            ? (isActivitiesWaiting &&
                                      isChatWaiting &&
                                      _cachedItems.isEmpty)
                                  ? const SizedBox.shrink()
                                  : Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.notifications_none_rounded,
                                            size: 48,
                                            color: Colors.grey.shade300,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Henüz bir duyuru veya bildirim yok.',
                                            style: TextStyle(
                                              color: Colors.grey.shade400,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                            : ListView(children: items),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showNotificationDetailDialog({
    required String id,
    required String title,
    required String subtitle,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close_rounded, size: 20),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        content: Text(
          subtitle,
          style: const TextStyle(fontSize: 13.8, height: 1.45),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _dismissNotificationItem(id);
            },
            icon: const Icon(Icons.delete_outline_rounded, size: 17),
            label: const Text('Bildirimi Kapat'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard({
    required String id,
    required String title,
    required String subtitle,
    required String time,
    required String type,
  }) {
    IconData icon;
    Color color;

    if (type == 'announcement') {
      icon = Icons.campaign_rounded;
      color = Colors.blue;
    } else if (type == 'chat_message') {
      icon = Icons.chat_bubble_outline_rounded;
      color = Colors.blue.shade500;
    } else if (type == 'chat_call') {
      icon = Icons.phone_missed_rounded;
      color = Colors.red.shade500;
    } else if (type.startsWith('visitor_')) {
      icon = type == 'visitor_check_out'
          ? Icons.logout_rounded
          : Icons.how_to_reg_rounded;
      color = const Color(0xFF0D9488);
    } else if (type.startsWith('student_exit_')) {
      icon = type == 'student_exit_confirmed'
          ? Icons.verified_user_rounded
          : Icons.exit_to_app_rounded;
      color = type == 'student_exit_confirmed'
          ? const Color(0xFF059669)
          : const Color(0xFF0284C7);
    } else if (type.startsWith('early_pickup_')) {
      icon = Icons.directions_car_filled_rounded;
      color = const Color(0xFFD97706);
    } else if (type.startsWith('infirmary_')) {
      icon = Icons.local_hospital_rounded;
      color = Colors.red.shade600;
    } else {
      icon = Icons.analytics_rounded;
      color = Colors.orange;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.06),
            spreadRadius: 2,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 6, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.8,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (time.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    time,
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12.6,
                                height: 1.35,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Bildirimi Kapat',
                        child: InkWell(
                          onTap: () => _dismissNotificationItem(id),
                          borderRadius: BorderRadius.circular(99),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 15,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SharedCalendarSection extends StatefulWidget {
  final String schoolTypeId;
  final String institutionId;
  final Map<String, dynamic>? userData;

  const SharedCalendarSection({
    super.key,
    required this.schoolTypeId,
    required this.institutionId,
    this.userData,
  });

  @override
  State<SharedCalendarSection> createState() => _SharedCalendarSectionState();
}

class _SharedCalendarSectionState extends State<SharedCalendarSection>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ⚡ Cache-First Hızlı Takvim Önbelleği (Girişte bekleme yapmaz, anında gösterir)
  static final Map<String, List<Map<String, dynamic>>> _memoryEventsCache = {};
  static final Map<String, String> _memoryActiveTermName = {};
  static final Map<String, Map<String, dynamic>> _globalDutyLocationsMap = {};
  static final Map<String, DateTime> _lastFetchTime = {};

  // ⚡ Global Dönem ve Çalışma Dönemleri Önbelleği (Tekrar tekrar Firestore'a sormaz)
  static Map<String, dynamic>? _cachedTermInfo;
  static Set<String>? _cachedValidWorkPeriodIds;
  static Map<String, Map<String, dynamic>>? _cachedWpLocationConfigs;
  static String? _cachedInstForWp;

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = false;
  bool _isWeeklyView = false;
  String? _activeTermName;

  final List<String> _daysOfWeek = ['Pt', 'Sa', 'Çr', 'Pr', 'Cu', 'Ct', 'Pz'];
  final List<String> _months = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];
  final List<String> _shortMonths = [
    'Oca',
    'Şub',
    'Mar',
    'Nis',
    'May',
    'Haz',
    'Tem',
    'Ağu',
    'Eyl',
    'Eki',
    'Kas',
    'Ara',
  ];

  String _getCacheKey() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    return '${widget.institutionId}_${uid}_${widget.schoolTypeId}_${_focusedDay.year}_${_focusedDay.month}';
  }

  static Map<String, dynamic> _serializeEventForDisk(Map<String, dynamic> e) {
    final copy = Map<String, dynamic>.from(e);
    copy.forEach((k, v) {
      if (v is Timestamp) {
        copy[k] = {'__type': 'Timestamp', 'ms': v.millisecondsSinceEpoch};
      } else if (v is DateTime) {
        copy[k] = {'__type': 'DateTime', 'ms': v.millisecondsSinceEpoch};
      }
    });
    return copy;
  }

  static Map<String, dynamic> _deserializeEventFromDisk(
    Map<String, dynamic> e,
  ) {
    final copy = Map<String, dynamic>.from(e);
    copy.forEach((k, v) {
      if (v is Map && v['__type'] == 'Timestamp' && v['ms'] is num) {
        copy[k] = Timestamp.fromMillisecondsSinceEpoch(v['ms'] as int);
      } else if (v is Map && v['__type'] == 'DateTime' && v['ms'] is num) {
        copy[k] = DateTime.fromMillisecondsSinceEpoch(v['ms'] as int);
      }
    });
    return copy;
  }

  static bool _eventsAreEqual(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final itemA = a[i];
      final itemB = b[i];
      if (itemA['id'] != itemB['id']) return false;
      if (itemA['title'] != itemB['title']) return false;
      if (itemA['source'] != itemB['source']) return false;

      final dateA = itemA['date'] is Timestamp
          ? (itemA['date'] as Timestamp).millisecondsSinceEpoch
          : (itemA['date'] is DateTime
                ? (itemA['date'] as DateTime).millisecondsSinceEpoch
                : null);
      final dateB = itemB['date'] is Timestamp
          ? (itemB['date'] as Timestamp).millisecondsSinceEpoch
          : (itemB['date'] is DateTime
                ? (itemB['date'] as DateTime).millisecondsSinceEpoch
                : null);
      if (dateA != dateB) return false;
    }
    return true;
  }

  Future<void> _loadFromDiskCache(String cacheKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('edukn_cal_cache_$cacheKey');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List decoded = json.decode(jsonStr);
        final loadedEvents = decoded
            .map(
              (item) => _deserializeEventFromDisk(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
        if (loadedEvents.isNotEmpty && mounted) {
          setState(() {
            _events = loadedEvents;
            _isLoading = false;
          });
          _memoryEventsCache[cacheKey] = loadedEvents;
        }
      }
    } catch (e) {
      debugPrint('Disk cache okuma hatası: $e');
    }
  }

  Future<void> _saveToDiskCache(
    String cacheKey,
    List<Map<String, dynamic>> events,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serialized = events.map((e) => _serializeEventForDisk(e)).toList();
      await prefs.setString(
        'edukn_cal_cache_$cacheKey',
        json.encode(serialized),
      );
    } catch (e) {
      debugPrint('Disk cache yazma hatası: $e');
    }
  }

  String _formatDateTr(dynamic dateVal, {bool short = false}) {
    DateTime? dt;
    if (dateVal is Timestamp) dt = dateVal.toDate();
    if (dateVal is DateTime) dt = dateVal;
    if (dateVal is String) dt = DateTime.tryParse(dateVal);
    if (dt == null) return '';
    final m = short ? _shortMonths[dt.month - 1] : _months[dt.month - 1];
    return '${dt.day} $m';
  }

  String _formatFullDateTr(dynamic dateVal) {
    DateTime? dt;
    if (dateVal is Timestamp) dt = dateVal.toDate();
    if (dateVal is DateTime) dt = dateVal;
    if (dateVal is String) dt = DateTime.tryParse(dateVal);
    if (dt == null) return '';
    return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
  }

  DateTime? _parseDateTime(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String) {
      final clean = val.trim();
      final isoParsed = DateTime.tryParse(clean);
      if (isoParsed != null) return isoParsed;

      try {
        final regex = RegExp(
          r'(\d{2})\.(\d{2})\.(\d{4})(?:\s+(\d{2}):(\d{2}))?',
        );
        final match = regex.firstMatch(clean);
        if (match != null) {
          final day = int.parse(match.group(1)!);
          final month = int.parse(match.group(2)!);
          final year = int.parse(match.group(3)!);
          final hour = match.group(4) != null ? int.parse(match.group(4)!) : 0;
          final minute = match.group(5) != null
              ? int.parse(match.group(5)!)
              : 0;
          return DateTime(year, month, day, hour, minute);
        }
      } catch (silentError) {
        debugPrint('[school_type_detail_screen] hata yutuldu: $silentError');
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    // ⚡ 1. Adım: RAM Önbelleğinden Oku (Anında Açılış)
    final cacheKey = _getCacheKey();
    final cached = _memoryEventsCache[cacheKey];
    if (cached != null && cached.isNotEmpty) {
      _events = List<Map<String, dynamic>>.from(cached);
      _activeTermName = _memoryActiveTermName[cacheKey];
      _isLoading = false;
      _loadEvents(isSilent: true);
    } else {
      // ⚡ 2. Adım: RAM'de yoksa Diskten Oku (Önceki oturumdan kalan kalıcı veri)
      _initCalendarWithCache(cacheKey);
    }
  }

  @override
  void didUpdateWidget(covariant SharedCalendarSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userData != oldWidget.userData ||
        widget.institutionId != oldWidget.institutionId ||
        widget.schoolTypeId != oldWidget.schoolTypeId) {
      _loadEvents(isSilent: _events.isNotEmpty);
    }
  }

  Future<void> _initCalendarWithCache(String cacheKey) async {
    await _loadFromDiskCache(cacheKey);
    if (mounted) {
      _loadEvents(isSilent: _events.isNotEmpty);
    }
  }

  Future<void> _loadEvents({bool isSilent = false, bool force = false}) async {
    final cacheKey = _getCacheKey();
    final lastFetch = _lastFetchTime[cacheKey];
    if (!force &&
        lastFetch != null &&
        _events.isNotEmpty &&
        DateTime.now().difference(lastFetch) < const Duration(seconds: 45)) {
      if (_isLoading) setState(() => _isLoading = false);
      return;
    }

    if (!isSilent && _events.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final startOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
      final endOfMonth = DateTime(
        _focusedDay.year,
        _focusedDay.month + 1,
        0,
        23,
        59,
        59,
      );

      final List<String> instIds = [
        widget.institutionId,
        widget.institutionId.toUpperCase(),
        widget.institutionId.toLowerCase(),
      ].where((s) => s.isNotEmpty).toSet().toList();

      final uData = widget.userData ?? UserPermissionService.cachedUserData;
      final role = (uData?['role'] as String?)?.toLowerCase() ?? '';
      final title = (uData?['title'] as String?)?.toLowerCase() ?? '';
      final type = (uData?['type'] as String?)?.toLowerCase() ?? '';
      final isStudent =
          role.contains('ogrenci') ||
          role.contains('öğrenci') ||
          role.contains('student') ||
          title.contains('ogrenci') ||
          title.contains('öğrenci') ||
          title.contains('student') ||
          type == 'student';
      final isParent =
          role.contains('veli') ||
          role.contains('parent') ||
          title.contains('veli') ||
          title.contains('parent') ||
          type == 'parent';
      final isStudentOrParent = isStudent || isParent;
      final isTeacher =
          !isStudentOrParent &&
          (widget.schoolTypeId.isEmpty ||
              role.contains('ogretmen') ||
              role.contains('öğretmen') ||
              role.contains('teacher') ||
              title.contains('ogretmen') ||
              title.contains('öğretmen') ||
              title.contains('teacher') ||
              type == 'staff' ||
              type == 'teacher');
      final currentAuthUid = FirebaseAuth.instance.currentUser?.uid;
      final docId = uData?['id']?.toString();
      final authUserId = uData?['authUserId']?.toString();
      final tId = uData?['teacherId']?.toString();
      final staffId = uData?['staffId']?.toString();
      final username = uData?['username']?.toString();
      final teacherName = (uData?['fullName'] ?? uData?['name'] ?? '')
          .toString()
          .trim();
      final targetStudentId =
          (uData?['selectedStudentId'] ??
                  uData?['studentId'] ??
                  docId ??
                  currentAuthUid)
              ?.toString() ??
          '';
      final targetStudentClassId =
          (uData?['selectedStudentClassId'] ?? uData?['classId'])?.toString() ??
          '';
      final targetStudentGrade =
          (uData?['selectedStudentClassLevel'] ?? uData?['classLevel'])
              ?.toString() ??
          '';

      final validTeacherIds = <String>{
        if (currentAuthUid != null && currentAuthUid.isNotEmpty) currentAuthUid,
        if (docId != null && docId.isNotEmpty) docId,
        if (authUserId != null && authUserId.isNotEmpty) authUserId,
        if (tId != null && tId.isNotEmpty) tId,
        if (staffId != null && staffId.isNotEmpty) staffId,
        if (username != null && username.isNotEmpty) username,
      }.toList();
      final myId = validTeacherIds.isNotEmpty ? validTeacherIds.first : null;

      Future<QuerySnapshot<Map<String, dynamic>>?> safeSingleQuery(
        Future<QuerySnapshot<Map<String, dynamic>>> future,
      ) async {
        try {
          return await future.timeout(const Duration(seconds: 4));
        } catch (_) {
          return null;
        }
      }

      // ⚡ Ay sınırları: Sadece görüntülenen aktif ay (+/- 7 gün takvim taşma payı)
      final Set<String> assignedClassIds = {
        if (targetStudentClassId.isNotEmpty) targetStudentClassId,
      };
      final startTs = Timestamp.fromDate(
        startOfMonth.subtract(const Duration(days: 7)),
      );
      final endTs = Timestamp.fromDate(endOfMonth.add(const Duration(days: 7)));

      // 1. Dönem Bilgisi Sorgusu (Önbellekte varsa Firestore'a tekrar sormaz)
      final termFuture = (_cachedTermInfo != null)
          ? Future.value(_cachedTermInfo)
          : (() async {
              try {
                final tId =
                    await TermService().getSelectedTermId().timeout(
                      const Duration(seconds: 3),
                      onTimeout: () => null,
                    ) ??
                    await TermService().getActiveTermId().timeout(
                      const Duration(seconds: 3),
                      onTimeout: () => null,
                    );
                if (tId != null && tId.isNotEmpty) {
                  final termDoc = await FirebaseFirestore.instance
                      .collection('terms')
                      .doc(tId)
                      .get()
                      .timeout(const Duration(seconds: 3));
                  if (termDoc.exists) {
                    final tName =
                        (termDoc.data()?['name'] ?? termDoc.data()?['termName'])
                            ?.toString();
                    final info = <String, dynamic>{'id': tId, 'name': tName};
                    _cachedTermInfo = info;
                    return info;
                  }
                  final info = <String, dynamic>{'id': tId, 'name': null};
                  _cachedTermInfo = info;
                  return info;
                }
              } catch (silentError) {
                debugPrint(
                  '[school_type_detail_screen] hata yutuldu: $silentError',
                );
              }
              return <String, dynamic>{'id': null, 'name': null};
            })();

      // 2. Çalışma Dönemleri (WorkPeriods)
      final wpFuture = isStudentOrParent
          ? Future.value(null)
          : safeSingleQuery(
              FirebaseFirestore.instance
                  .collection('workPeriods')
                  .where('institutionId', whereIn: instIds)
                  .get(),
            );

      // 3. Öğretmen Sınıf Atamaları
      final assignFuture = (isTeacher && validTeacherIds.isNotEmpty)
          ? Future.wait(
              validTeacherIds.map(
                (tId) => safeSingleQuery(
                  FirebaseFirestore.instance
                      .collection('lessonAssignments')
                      .where('institutionId', whereIn: instIds)
                      .where('teacherIds', arrayContains: tId)
                      .where('isActive', isEqualTo: true)
                      .get(),
                ),
              ),
            ).then((list) => list.whereType<QuerySnapshot>().toList())
          : Future.value(<QuerySnapshot>[]);

      // 4. Sınıflar
      final classesFuture = safeSingleQuery(
        FirebaseFirestore.instance
            .collection('classes')
            .where('institutionId', whereIn: instIds)
            .get(),
      );

      // 5. Aktiviteler (Kurum bazlı çekip tarihi bellekte filtrele - composite index gerektirmez)
      final activitiesFuture = safeSingleQuery(
        FirebaseFirestore.instance
            .collection('activities')
            .where('institutionId', whereIn: instIds)
            .get(),
      );

      // 6. Etüt Talepleri
      final etutFuture = isStudentOrParent
          ? (targetStudentId.isNotEmpty
                ? Future.wait([
                    safeSingleQuery(
                      FirebaseFirestore.instance
                          .collection('etut_requests')
                          .where('institutionId', whereIn: instIds)
                          .where('studentId', isEqualTo: targetStudentId)
                          .get(),
                    ),
                    safeSingleQuery(
                      FirebaseFirestore.instance
                          .collection('etut_requests')
                          .where('institutionId', whereIn: instIds)
                          .where('studentIds', arrayContains: targetStudentId)
                          .get(),
                    ),
                  ]).then((list) => list.whereType<QuerySnapshot>().toList())
                : Future.value(<QuerySnapshot>[]))
          : (validTeacherIds.isNotEmpty
                ? Future.wait(
                    validTeacherIds.map(
                      (tId) => safeSingleQuery(
                        FirebaseFirestore.instance
                            .collection('etut_requests')
                            .where('institutionId', whereIn: instIds)
                            .where('teacherId', isEqualTo: tId)
                            .get(),
                      ),
                    ),
                  ).then((list) => list.whereType<QuerySnapshot>().toList())
                : safeSingleQuery(
                    FirebaseFirestore.instance
                        .collection('etut_requests')
                        .where('institutionId', whereIn: instIds)
                        .get(),
                  ).then(
                    (snap) => snap != null
                        ? <QuerySnapshot>[snap]
                        : <QuerySnapshot>[],
                  ));

      // 7. Geziler (Kurum bazlı çekip tarihi bellekte filtrele - composite index gerektirmez)
      final geziFuture = safeSingleQuery(
        FirebaseFirestore.instance
            .collection('field_trips')
            .where('institutionId', whereIn: instIds)
            .get(),
      );

      // 8. Nöbetler (Sadece öğretmen için)
      final dutyFuture =
          (isTeacher && (validTeacherIds.isNotEmpty || teacherName.isNotEmpty))
          ? (() {
              final List<Future<QuerySnapshot?>> dutyQueryList = [];
              for (final inst in instIds) {
                for (int i = 0; i < validTeacherIds.length; i += 10) {
                  final chunk = validTeacherIds.skip(i).take(10).toList();
                  dutyQueryList.add(
                    safeSingleQuery(
                      FirebaseFirestore.instance
                          .collection('dutyScheduleItems')
                          .where('institutionId', isEqualTo: inst)
                          .where('teacherId', whereIn: chunk)
                          .get(),
                    ),
                  );
                }
                if (teacherName.isNotEmpty) {
                  dutyQueryList.add(
                    safeSingleQuery(
                      FirebaseFirestore.instance
                          .collection('dutyScheduleItems')
                          .where('institutionId', isEqualTo: inst)
                          .where('teacherName', isEqualTo: teacherName)
                          .get(),
                    ),
                  );
                }
              }
              return Future.wait(
                dutyQueryList,
              ).then((list) => list.whereType<QuerySnapshot>().toList());
            })()
          : Future.value(<QuerySnapshot>[]);

      // 9. Ödevler
      final homeworkFuture = isStudentOrParent
          ? (targetStudentClassId.isNotEmpty
                ? safeSingleQuery(
                    FirebaseFirestore.instance
                        .collection('homeworks')
                        .where('institutionId', whereIn: instIds)
                        .where('classId', isEqualTo: targetStudentClassId)
                        .get(),
                  ).then(
                    (snap) => snap != null
                        ? <QuerySnapshot>[snap]
                        : <QuerySnapshot>[],
                  )
                : Future.value(<QuerySnapshot>[]))
          : (validTeacherIds.isNotEmpty
                ? Future.wait(
                    validTeacherIds.map(
                      (tId) => safeSingleQuery(
                        FirebaseFirestore.instance
                            .collection('homeworks')
                            .where('institutionId', whereIn: instIds)
                            .where('teacherId', isEqualTo: tId)
                            .get(),
                      ),
                    ),
                  ).then((list) => list.whereType<QuerySnapshot>().toList())
                : Future.value(<QuerySnapshot>[]));

      // 10. Sınıf Sınavları
      final classExamsFuture = isStudentOrParent
          ? (targetStudentClassId.isNotEmpty
                ? safeSingleQuery(
                    FirebaseFirestore.instance
                        .collection('class_exams')
                        .where('institutionId', whereIn: instIds)
                        .where('classId', isEqualTo: targetStudentClassId)
                        .get(),
                  )
                : Future.value(null))
          : (myId != null
                ? safeSingleQuery(
                    FirebaseFirestore.instance
                        .collection('class_exams')
                        .where('institutionId', whereIn: instIds)
                        .where('date', isGreaterThanOrEqualTo: startTs)
                        .where('date', isLessThanOrEqualTo: endTs)
                        .get(),
                  )
                : Future.value(null));

      // 11. Deneme Sınavları
      final trialExamsFuture = safeSingleQuery(
        FirebaseFirestore.instance
            .collection('trial_exams')
            .where('institutionId', whereIn: instIds)
            .where('isActive', isEqualTo: true)
            .get(),
      );

      // 12. Nöbet Yerleri (Önbellekte varsa veya öğrenci/veli ise tekrar sorma)
      final dutyLocationsFuture =
          (!isStudentOrParent &&
              myId != null &&
              _globalDutyLocationsMap.isEmpty)
          ? safeSingleQuery(
              FirebaseFirestore.instance
                  .collection('dutyLocations')
                  .where('institutionId', whereIn: instIds)
                  .get(),
            )
          : Future.value(null);

      // 13. Gözetmenlik Slotları (yayınlanmış, bu öğretmene ait)
      final proctoringFuture = (isTeacher && validTeacherIds.isNotEmpty)
          ? (() {
              final List<Future<QuerySnapshot?>> pQueryList = [];
              for (final inst in instIds) {
                for (int i = 0; i < validTeacherIds.length; i += 10) {
                  final chunk = validTeacherIds.skip(i).take(10).toList();
                  pQueryList.add(
                    safeSingleQuery(
                      FirebaseFirestore.instance
                          .collection('proctoringSlots')
                          .where('institutionId', isEqualTo: inst)
                          .where('teacherId', whereIn: chunk)
                          .where('isPublished', isEqualTo: true)
                          .get(),
                    ),
                  );
                }
              }
              return Future.wait(
                pQueryList,
              ).then((list) => list.whereType<QuerySnapshot>().toList());
            })()
          : Future.value(<QuerySnapshot>[]);

      final results =
          await Future.wait([
            termFuture, // 0
            wpFuture, // 1
            assignFuture, // 2
            classesFuture, // 3
            activitiesFuture, // 4
            etutFuture, // 5
            geziFuture, // 6
            dutyFuture, // 7
            homeworkFuture, // 8
            classExamsFuture, // 9
            trialExamsFuture, // 10
            dutyLocationsFuture, // 11
            proctoringFuture, // 12
          ]).timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              debugPrint(
                '⚠️ Calendar Future.wait timeout (8s) - Mevcut verilerle devam ediliyor.',
              );
              return List.filled(13, null);
            },
          );

      final termInfo = results[0] as Map<String, dynamic>?;
      final activeTermId = termInfo?['id'] as String?;
      if (termInfo?['name'] != null) {
        _activeTermName = termInfo!['name'].toString();
      }

      final wpSnap = results[1] as QuerySnapshot?;
      Set<String> validWorkPeriodIds;
      Map<String, Map<String, dynamic>> wpLocationConfigs;
      if (wpSnap != null) {
        validWorkPeriodIds = {};
        wpLocationConfigs = {};
        for (var wpDoc in wpSnap.docs) {
          final wpData = wpDoc.data() as Map<String, dynamic>;
          final wpTermId = wpData['termId']?.toString().trim();
          if (activeTermId == null ||
              activeTermId.isEmpty ||
              wpTermId == activeTermId ||
              wpDoc.id == activeTermId) {
            validWorkPeriodIds.add(wpDoc.id);
          }
          if (wpData['dutyLocationConfigs'] is Map) {
            wpLocationConfigs[wpDoc.id] = Map<String, dynamic>.from(
              wpData['dutyLocationConfigs'] as Map,
            );
          }
        }
        _cachedValidWorkPeriodIds = validWorkPeriodIds;
        _cachedWpLocationConfigs = wpLocationConfigs;
        _cachedInstForWp = widget.institutionId;
      } else {
        validWorkPeriodIds = _cachedValidWorkPeriodIds ?? {};
        wpLocationConfigs = _cachedWpLocationConfigs ?? {};
      }

      final assignSnapshots = results[2] as List<QuerySnapshot>?;
      final classesSnapshot = results[3] as QuerySnapshot?;
      final activitiesSnapshot = results[4] as QuerySnapshot?;
      final etutSnapshots = results[5] as List<QuerySnapshot>?;
      final geziSnapshot = results[6] as QuerySnapshot?;
      final dutySnapshots = results[7] as List<QuerySnapshot>?;
      final homeworkSnapshots = results[8] as List<QuerySnapshot>?;
      final classExamsSnapshot = results[9] as QuerySnapshot?;
      final trialExamsSnapshot = results[10] as QuerySnapshot?;
      final dutyLocationsSnapshot = results[11] as QuerySnapshot?;
      final proctoringSnapshots = results[12] as List<QuerySnapshot>?;

      final List<QueryDocumentSnapshot> allAssignDocs = [];
      if (assignSnapshots != null) {
        final seen = <String>{};
        for (final s in assignSnapshots) {
          for (final d in s.docs) {
            if (seen.add(d.id)) allAssignDocs.add(d);
          }
        }
      }

      final List<QueryDocumentSnapshot> allEtutDocs = [];
      if (etutSnapshots != null) {
        final seen = <String>{};
        for (final s in etutSnapshots) {
          for (final d in s.docs) {
            if (seen.add(d.id)) allEtutDocs.add(d);
          }
        }
      }

      final List<QueryDocumentSnapshot> allDutyDocs = [];
      if (dutySnapshots != null) {
        final seen = <String>{};
        for (final s in dutySnapshots) {
          for (final d in s.docs) {
            if (seen.add(d.id)) allDutyDocs.add(d);
          }
        }
      }

      // Gözetmenlik docs
      final List<QueryDocumentSnapshot> allProctoringDocs = [];
      if (proctoringSnapshots != null) {
        final seen = <String>{};
        for (final s in proctoringSnapshots) {
          for (final d in s.docs) {
            if (seen.add(d.id)) allProctoringDocs.add(d);
          }
        }
      }

      final List<QueryDocumentSnapshot> allHomeworkDocs = [];
      if (homeworkSnapshots != null) {
        final seen = <String>{};
        for (final s in homeworkSnapshots) {
          for (final d in s.docs) {
            if (seen.add(d.id)) allHomeworkDocs.add(d);
          }
        }
      }

      final Map<String, Map<String, dynamic>> dutyLocationsMap = Map.from(
        _globalDutyLocationsMap,
      );
      if (dutyLocationsSnapshot != null) {
        for (var doc in dutyLocationsSnapshot.docs) {
          final locData = Map<String, dynamic>.from(doc.data() as Map);
          locData['id'] = doc.id;
          dutyLocationsMap[doc.id] = locData;
          _globalDutyLocationsMap[doc.id] = locData;
          final locName = (locData['name'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          if (locName.isNotEmpty) {
            dutyLocationsMap['name_$locName'] = locData;
            _globalDutyLocationsMap['name_$locName'] = locData;
          }
        }
      }

      if (allAssignDocs.isNotEmpty) {
        for (var doc in allAssignDocs) {
          final data = doc.data() as Map<String, dynamic>;
          final itemTermId = data['termId']?.toString().trim();
          if (activeTermId != null &&
              activeTermId.isNotEmpty &&
              itemTermId != null &&
              itemTermId.isNotEmpty) {
            if (itemTermId != activeTermId) continue;
          }
          final cid = data['classId']?.toString();
          if (cid != null) assignedClassIds.add(cid);
        }
      }

      final Map<String, String> classIdToName = {};
      if (classesSnapshot != null) {
        for (var doc in classesSnapshot.docs) {
          final cData = doc.data() as Map<String, dynamic>;
          final cId = doc.id;
          final cName =
              cData['className']?.toString() ?? cData['name']?.toString() ?? '';
          if (cName.isNotEmpty) {
            classIdToName[cId] = cName;
          }
        }
      }

      List<Map<String, dynamic>> allEvents = [];

      // Mapper: Activities
      if (activitiesSnapshot != null) {
        allEvents.addAll(
          activitiesSnapshot.docs
              .map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final parsedDate = _parseDateTime(data['date']);
                return <String, dynamic>{
                  ...data,
                  'id': doc.id,
                  'source': 'activity',
                  'displayType': data['type'] ?? 'Etkinlik',
                  'date': parsedDate != null
                      ? Timestamp.fromDate(parsedDate)
                      : null,
                };
              })
              .where((data) {
                final sId = data['schoolTypeId'] as String?;
                if (widget.schoolTypeId.isNotEmpty &&
                    sId != null &&
                    sId != widget.schoolTypeId)
                  return false;

                final itemTermId = data['termId']?.toString().trim();
                if (activeTermId != null &&
                    activeTermId.isNotEmpty &&
                    itemTermId != null &&
                    itemTermId.isNotEmpty) {
                  if (itemTermId != activeTermId) return false;
                }

                // Öğretmen filtreleme: Eğer activities içinde targetRoles veya recipients varsa kontrol et
                if (isTeacher) {
                  final targetRoles = data['targetRoles'] as List<dynamic>?;
                  final recipients = data['recipients'] as List<dynamic>?;
                  bool isRecipient = false;
                  if (targetRoles != null &&
                      (targetRoles.contains('ogretmen') ||
                          targetRoles.contains('öğretmen') ||
                          targetRoles.contains('teacher'))) {
                    isRecipient = true;
                  } else if (recipients != null) {
                    if (recipients.contains('ALL') ||
                        recipients.contains('TEACHER') ||
                        recipients.contains('unit:ogretmen') ||
                        recipients.contains('teacher')) {
                      isRecipient = true;
                    } else if (recipients.contains('user:$myId')) {
                      isRecipient = true;
                    } else {
                      for (var cid in assignedClassIds) {
                        if (recipients.contains('class:$cid') ||
                            recipients.contains(cid)) {
                          isRecipient = true;
                          break;
                        }
                      }
                    }
                  } else {
                    isRecipient = true;
                  }
                  if (!isRecipient) return false;
                }

                final dateTs = data['date'] as Timestamp?;
                if (dateTs == null) return false;
                final date = dateTs.toDate();
                return date.isAfter(
                      startOfMonth.subtract(Duration(seconds: 1)),
                    ) &&
                    date.isBefore(endOfMonth.add(Duration(seconds: 1)));
              }),
        );
      }

      // Mapper: Etütler
      allEvents.addAll(
        allEtutDocs
            .map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final lesson = data['lessonName'] ?? '';
              final teacher = data['teacherName'] ?? '';
              final topic = data['topic'] ?? '';
              String title = 'Etüt';
              if (lesson.isNotEmpty && teacher.isNotEmpty) {
                title = 'Etüt: $lesson - $teacher';
              } else if (topic.isNotEmpty) {
                title = 'Etüt: $topic';
              }

              final parsedDate = _parseDateTime(
                data['startTime'] ?? data['date'],
              );
              return <String, dynamic>{
                ...data,
                'id': doc.id,
                'source': 'etut',
                'title': title,
                'topic': data['topic'],
                'displayType': 'Etüt',
                'date': parsedDate != null
                    ? Timestamp.fromDate(parsedDate)
                    : null,
                'startTime': parsedDate != null
                    ? Timestamp.fromDate(parsedDate)
                    : null,
                'type': 'Etüt',
              };
            })
            .where((data) {
              final sId = data['schoolTypeId'] as String?;
              if (widget.schoolTypeId.isNotEmpty &&
                  sId != null &&
                  sId != widget.schoolTypeId)
                return false;

              final itemTermId = data['termId']?.toString().trim();
              if (activeTermId != null &&
                  activeTermId.isNotEmpty &&
                  itemTermId != null &&
                  itemTermId.isNotEmpty) {
                if (itemTermId != activeTermId) return false;
              }

              // Öğrenci Filtreleme: Eğer isStudent ise sadece kendi olduğu etütleri görsün
              if (isStudent && myId != null) {
                final studentIds = data['studentIds'] as List<dynamic>?;
                final singleStudentId = data['studentId'] as String?;
                if (studentIds != null &&
                    !studentIds.contains(myId) &&
                    singleStudentId != myId) {
                  return false;
                }
              }

              final dateTs = data['startTime'] as Timestamp?;
              if (dateTs == null) return false;
              final date = dateTs.toDate();
              return date.isAfter(
                    startOfMonth.subtract(Duration(seconds: 1)),
                  ) &&
                  date.isBefore(endOfMonth.add(Duration(seconds: 1)));
            }),
      );

      // Mapper: Geziler
      if (geziSnapshot != null) {
        allEvents.addAll(
          geziSnapshot.docs
              .map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final parsedDate = _parseDateTime(data['departureTime']);
                return <String, dynamic>{
                  ...data,
                  'id': doc.id,
                  'source': 'gezi',
                  'title': data['name'] ?? 'Gezi',
                  'displayType': 'Gezi',
                  'date': parsedDate != null
                      ? Timestamp.fromDate(parsedDate)
                      : null,
                  'startTime': parsedDate != null
                      ? Timestamp.fromDate(parsedDate)
                      : null,
                  'type': 'Gezi',
                };
              })
              .where((data) {
                final sId = data['schoolTypeId'] as String?;
                if (widget.schoolTypeId.isNotEmpty &&
                    sId != null &&
                    sId != widget.schoolTypeId)
                  return false;

                final itemTermId = data['termId']?.toString().trim();
                if (activeTermId != null &&
                    activeTermId.isNotEmpty &&
                    itemTermId != null &&
                    itemTermId.isNotEmpty) {
                  if (itemTermId != activeTermId) return false;
                }

                if (isTeacher) {
                  // Gezilerde öğretmen filtreleme: Eğer teacherIds listesi varsa kontrol et
                  final teacherIds = data['teacherIds'] as List<dynamic>?;
                  if (teacherIds != null &&
                      !teacherIds.any((id) => validTeacherIds.contains(id)))
                    return false;
                }

                final dateTs = data['departureTime'] as Timestamp?;
                if (dateTs == null) return false;
                final date = dateTs.toDate();
                return date.isAfter(
                      startOfMonth.subtract(Duration(seconds: 1)),
                    ) &&
                    date.isBefore(endOfMonth.add(Duration(seconds: 1)));
              }),
        );
      }

      // 4. Öğretmen / Öğrenci / Veli özel yüklemeleri (Nöbetler, Ödevler, Sınavlar)
      if ((isTeacher &&
              (myId != null ||
                  validTeacherIds.isNotEmpty ||
                  teacherName.isNotEmpty)) ||
          isStudentOrParent) {
        // A. dutyScheduleItems (Nöbetler)
        if (allDutyDocs.isNotEmpty) {
          final List<QueryDocumentSnapshot> matchingDutyDocs = [];
          for (var doc in allDutyDocs) {
            final data = doc.data() as Map<String, dynamic>;
            final itemTermId = data['termId']?.toString().trim();
            final itemPeriodId = data['periodId']?.toString().trim() ?? '';

            bool termMatches = false;
            if (activeTermId == null || activeTermId.isEmpty) {
              termMatches = true;
            } else if (itemTermId != null && itemTermId.isNotEmpty) {
              termMatches = (itemTermId == activeTermId);
            } else if (itemPeriodId == activeTermId ||
                validWorkPeriodIds.contains(itemPeriodId)) {
              termMatches = true;
            }
            if (termMatches) {
              matchingDutyDocs.add(doc);
            }
          }

          // Dönem eşleşen nöbetler varsa onları göster; dönem filtresi boş dönerse kullanıcı mağdur olmasın diye tümünü göster (teacher_duty_screen ile birebir aynı)
          final dutyDocsToProcess = matchingDutyDocs.isNotEmpty
              ? matchingDutyDocs
              : allDutyDocs;

          // Aktif dönemle eşleşen ve en güncel olan nöbetleri öne al
          final sortedDutyDocs = List<QueryDocumentSnapshot>.from(
            dutyDocsToProcess,
          );
          sortedDutyDocs.sort((a, b) {
            final dataA = a.data() as Map<String, dynamic>;
            final dataB = b.data() as Map<String, dynamic>;

            final matchA =
                (dataA['termId'] == activeTermId ||
                validWorkPeriodIds.contains(dataA['periodId']));
            final matchB =
                (dataB['termId'] == activeTermId ||
                validWorkPeriodIds.contains(dataB['periodId']));
            if (matchA != matchB) {
              return matchA ? -1 : 1;
            }

            final tsA = dataA['updatedAt'] ?? dataA['createdAt'];
            final tsB = dataB['updatedAt'] ?? dataB['createdAt'];
            if (tsA != null && tsB != null) {
              final dtA = _parseDateTime(tsA);
              final dtB = _parseDateTime(tsB);
              if (dtA != null && dtB != null) {
                return dtB.compareTo(dtA);
              }
            }
            return 0;
          });

          final Set<String> seenDutyDatePerTeacher = {};

          for (var doc in sortedDutyDocs) {
            final data = doc.data() as Map<String, dynamic>;
            final itemPeriodId = data['periodId']?.toString().trim() ?? '';
            final dDayOfWeek = int.tryParse(
              data['dayOfWeek']?.toString() ?? '',
            );
            final dWeekStart = _parseDateTime(data['weekStart']);
            final location =
                data['locationName'] ?? data['dutyLocation'] ?? 'Nöbet Yeri';
            final locationId = (data['locationId'] ?? '').toString();
            var locData =
                dutyLocationsMap[locationId] ??
                dutyLocationsMap['name_${location.toString().trim().toLowerCase()}'] ??
                _globalDutyLocationsMap[locationId];

            final actualLocId = locationId.isNotEmpty
                ? locationId
                : (locData?['id']?.toString() ?? '');
            Map<String, dynamic>? cfg =
                (actualLocId.isNotEmpty && itemPeriodId.isNotEmpty)
                ? (wpLocationConfigs[itemPeriodId]?[actualLocId]
                      as Map<String, dynamic>?)
                : null;
            if (cfg == null && actualLocId.isNotEmpty) {
              for (var c in wpLocationConfigs.values) {
                if (c.containsKey(actualLocId) && c[actualLocId] is Map) {
                  cfg = Map<String, dynamic>.from(c[actualLocId] as Map);
                  break;
                }
              }
            }

            final dutyDesc =
                (locData?['description'] ??
                        cfg?['description'] ??
                        data['locationDescription'] ??
                        data['description'] ??
                        '')
                    .toString()
                    .trim();

            DateTime? singleDutyDate;
            if (data['dutyDate'] != null) {
              singleDutyDate = _parseDateTime(data['dutyDate']);
            }
            if (singleDutyDate == null &&
                dDayOfWeek != null &&
                dWeekStart != null) {
              singleDutyDate = dWeekStart.add(Duration(days: dDayOfWeek - 1));
            }

            final List<DateTime> dutyDates = [];
            if (singleDutyDate != null) {
              dutyDates.add(singleDutyDate);
            } else if (dDayOfWeek != null &&
                dDayOfWeek >= 1 &&
                dDayOfWeek <= 7) {
              // Eğer dWeekStart yoksa, o ayın tüm o haftanın günlerine yay (Haftalık döngüsel nöbet programı)
              DateTime cur = startOfMonth;
              while (!cur.isAfter(endOfMonth)) {
                if (cur.weekday == dDayOfWeek) {
                  dutyDates.add(cur);
                }
                cur = cur.add(const Duration(days: 1));
              }
            }

            for (final dutyDate in dutyDates) {
              if (dutyDate.isAfter(
                    startOfMonth.subtract(const Duration(seconds: 1)),
                  ) &&
                  dutyDate.isBefore(
                    endOfMonth.add(const Duration(seconds: 1)),
                  )) {
                // Aynı öğretmenin aynı gün mükerrer/eski nöbeti varsa teke indir (en güncel/aktif olanı göster)
                final dutyTeacherId = (data['teacherId'] ?? myId ?? '')
                    .toString();
                final dayKey =
                    '${dutyTeacherId}_${dutyDate.year}_${dutyDate.month}_${dutyDate.day}';
                if (!seenDutyDatePerTeacher.add(dayKey)) {
                  continue;
                }

                String startStr = '';
                if (locData?['startTime'] != null &&
                    locData!['startTime'].toString().trim().isNotEmpty) {
                  startStr = locData['startTime'].toString().trim();
                } else if (cfg?['startTime'] != null &&
                    cfg!['startTime'].toString().trim().isNotEmpty) {
                  startStr = cfg['startTime'].toString().trim();
                } else if (data['startTime'] is String &&
                    (data['startTime'] as String).trim().isNotEmpty) {
                  startStr = (data['startTime'] as String).trim();
                }

                String endStr = '';
                if (locData?['endTime'] != null &&
                    locData!['endTime'].toString().trim().isNotEmpty) {
                  endStr = locData['endTime'].toString().trim();
                } else if (cfg?['endTime'] != null &&
                    cfg!['endTime'].toString().trim().isNotEmpty) {
                  endStr = cfg['endTime'].toString().trim();
                } else if (data['endTime'] is String &&
                    (data['endTime'] as String).trim().isNotEmpty) {
                  endStr = (data['endTime'] as String).trim();
                }

                final normStart = startStr.replaceAll('.', ':').trim();
                final normEnd = endStr.replaceAll('.', ':').trim();

                DateTime? dutyStartDateTime;
                DateTime? dutyEndDateTime;

                if (normStart.isNotEmpty && normStart.contains(':')) {
                  final parts = normStart.split(':');
                  final sh = int.tryParse(parts[0]) ?? 8;
                  final sm = int.tryParse(parts[1]) ?? 0;
                  dutyStartDateTime = DateTime(
                    dutyDate.year,
                    dutyDate.month,
                    dutyDate.day,
                    sh,
                    sm,
                  );
                } else if (startStr.isNotEmpty || endStr.isNotEmpty) {
                  dutyStartDateTime = DateTime(
                    dutyDate.year,
                    dutyDate.month,
                    dutyDate.day,
                    8,
                    0,
                  );
                }

                if (normEnd.isNotEmpty && normEnd.contains(':')) {
                  final parts = normEnd.split(':');
                  final eh =
                      int.tryParse(parts[0]) ??
                      ((dutyStartDateTime?.hour ?? 8) + 9);
                  final em =
                      int.tryParse(parts[1]) ??
                      (dutyStartDateTime?.minute ?? 0);
                  dutyEndDateTime = DateTime(
                    dutyDate.year,
                    dutyDate.month,
                    dutyDate.day,
                    eh,
                    em,
                  );
                } else if (dutyStartDateTime != null) {
                  dutyEndDateTime = dutyStartDateTime.add(
                    const Duration(hours: 9),
                  );
                }

                allEvents.add(<String, dynamic>{
                  ...data,
                  'id':
                      'duty_${doc.id}_${dutyDate.year}_${dutyDate.month}_${dutyDate.day}',
                  'source': 'duty',
                  'title': 'Nöbet: $location',
                  'locationName': location,
                  'dutyLocation': location,
                  'description': dutyDesc,
                  'locationDescription': dutyDesc,
                  'rawStartTime': startStr,
                  'rawEndTime': endStr,
                  'displayType': 'Nöbet',
                  'type': 'Nöbet',
                  'date': Timestamp.fromDate(dutyDate),
                  'startTime': dutyStartDateTime != null
                      ? Timestamp.fromDate(dutyStartDateTime)
                      : null,
                  'endTime': dutyEndDateTime != null
                      ? Timestamp.fromDate(dutyEndDateTime)
                      : null,
                });
              }
            }
          }
        }

        // B2. Gözetmenlik Slotları
        if (allProctoringDocs.isNotEmpty) {
          // İlgili sınavların güncel saat ayarlarını çek
          final examIds = allProctoringDocs
              .map(
                (d) => (d.data() as Map<String, dynamic>)['examId']?.toString(),
              )
              .where((id) => id != null && id.isNotEmpty)
              .toSet()
              .toList();

          final Map<String, List<Map<String, String>>> examManualSlotsMap = {};
          if (examIds.isNotEmpty) {
            final List<Future<void>> settingsFutures = [];
            for (final eId in examIds) {
              settingsFutures.add(
                FirebaseFirestore.instance
                    .collection('proctoringSettings')
                    .where('examId', isEqualTo: eId)
                    .limit(1)
                    .get()
                    .then((snap) {
                      if (snap.docs.isNotEmpty) {
                        final sData = snap.docs.first.data();
                        final raw =
                            (sData['manualSlots'] ?? sData['timeSlots'])
                                as List? ??
                            [];
                        if (raw.isNotEmpty) {
                          examManualSlotsMap[eId!] = raw.map((e) {
                            if (e is Map) {
                              return {
                                'start': (e['start'] ?? e['startTime'] ?? '')
                                    .toString(),
                                'end': (e['end'] ?? e['endTime'] ?? '')
                                    .toString(),
                              };
                            }
                            return {'start': '', 'end': ''};
                          }).toList();
                        }
                      }
                    })
                    .catchError((_) {}),
              );
            }
            try {
              await Future.wait(
                settingsFutures,
              ).timeout(const Duration(seconds: 3));
            } catch (_) {}
          }

          final seen = <String>{};
          for (var doc in allProctoringDocs) {
            if (!seen.add(doc.id)) continue;
            final data = doc.data() as Map<String, dynamic>;

            // Sınav tarihini al
            final examDate = _parseDateTime(data['examDate']);
            if (examDate == null) continue;

            // Sadece bu ay içindeyse göster
            if (examDate.isBefore(
                  startOfMonth.subtract(const Duration(days: 7)),
                ) ||
                examDate.isAfter(endOfMonth.add(const Duration(days: 7)))) {
              continue;
            }

            final examId = data['examId']?.toString() ?? '';
            final slotIndex = (data['slotIndex'] as num?)?.toInt() ?? 0;
            final className = data['className']?.toString() ?? '';
            final examName = data['examName']?.toString() ?? 'Sınav';

            String startTime = data['startTime']?.toString() ?? '';
            String endTime = data['endTime']?.toString() ?? '';
            String slotLabel = data['slotLabel']?.toString() ?? '';

            // Sınavın güncel saat ayarı varsa slotIndex'e göre saati dinamik belirle ve dokümanı güncelle
            if (examId.isNotEmpty && examManualSlotsMap.containsKey(examId)) {
              final mSlots = examManualSlotsMap[examId]!;
              if (slotIndex >= 0 && slotIndex < mSlots.length) {
                final configuredStart = mSlots[slotIndex]['start'] ?? '';
                final configuredEnd = mSlots[slotIndex]['end'] ?? '';
                if (configuredStart.isNotEmpty && configuredEnd.isNotEmpty) {
                  if (startTime != configuredStart ||
                      endTime != configuredEnd) {
                    doc.reference
                        .update({
                          'startTime': configuredStart,
                          'endTime': configuredEnd,
                          'slotLabel': '${slotIndex + 1}. Saat',
                        })
                        .catchError((_) {});
                  }
                  startTime = configuredStart;
                  endTime = configuredEnd;
                  slotLabel = '${slotIndex + 1}. Saat';
                }
              }
            }

            DateTime? startDt;
            DateTime? endDt;
            if (startTime.contains(':')) {
              final parts = startTime.split(':');
              startDt = DateTime(
                examDate.year,
                examDate.month,
                examDate.day,
                int.tryParse(parts[0]) ?? 8,
                int.tryParse(parts[1]) ?? 0,
              );
            }
            if (endTime.contains(':')) {
              final parts = endTime.split(':');
              endDt = DateTime(
                examDate.year,
                examDate.month,
                examDate.day,
                int.tryParse(parts[0]) ?? 9,
                int.tryParse(parts[1]) ?? 0,
              );
            }

            final desc = [
              if (className.isNotEmpty) className,
              if (slotLabel.isNotEmpty) slotLabel,
              if (startTime.isNotEmpty && endTime.isNotEmpty)
                '$startTime – $endTime',
            ].join(' · ');

            allEvents.add(<String, dynamic>{
              ...data,
              'id': 'proctoring_${doc.id}',
              'source': 'proctoring',
              'title': 'Gözetmenlik: $examName',
              'description': desc,
              'displayType': 'Gözetmenlik',
              'type': 'Gözetmenlik',
              'date': Timestamp.fromDate(
                DateTime(examDate.year, examDate.month, examDate.day),
              ),
              'startTime': startDt != null ? Timestamp.fromDate(startDt) : null,
              'endTime': endDt != null ? Timestamp.fromDate(endDt) : null,
              'rawStartTime': startTime,
              'rawEndTime': endTime,
            });
          }
        }

        // C. homeworks (Ödevler)
        if (allHomeworkDocs.isNotEmpty) {
          for (var doc in allHomeworkDocs) {
            final data = doc.data() as Map<String, dynamic>;
            final itemTermId = data['termId']?.toString().trim();
            if (activeTermId != null &&
                activeTermId.isNotEmpty &&
                itemTermId != null &&
                itemTermId.isNotEmpty) {
              if (itemTermId != activeTermId) continue;
            }

            final dueDate = _parseDateTime(data['dueDate']);
            final classId = data['classId']?.toString() ?? '';
            final className = classIdToName[classId] ?? data['className'] ?? '';

            if (dueDate != null) {
              if (dueDate.isAfter(
                    startOfMonth.subtract(const Duration(seconds: 1)),
                  ) &&
                  dueDate.isBefore(
                    endOfMonth.add(const Duration(seconds: 1)),
                  )) {
                final ts = Timestamp.fromDate(dueDate);
                allEvents.add(<String, dynamic>{
                  ...data,
                  'id': 'homework_${doc.id}',
                  'source': 'homework',
                  'title': 'Ödev Kontrol : $className',
                  'displayType': 'Ödev',
                  'type': 'Ödev',
                  'date': ts,
                  'startTime': ts,
                  'endTime': ts,
                });
              }
            }
          }
        }

        // D. class_exams (Yazılı Sınavlar)
        if (classExamsSnapshot != null) {
          for (var doc in classExamsSnapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final itemTermId = data['termId']?.toString().trim();
            if (activeTermId != null &&
                activeTermId.isNotEmpty &&
                itemTermId != null &&
                itemTermId.isNotEmpty) {
              if (itemTermId != activeTermId) continue;
            }

            final cId = data['classId']?.toString();
            final examDate = _parseDateTime(data['date']);
            final name = data['examName'] ?? 'Sınav';
            final lesson = data['lessonName'] ?? '';

            if (examDate != null &&
                cId != null &&
                assignedClassIds.contains(cId)) {
              if (examDate.isAfter(
                    startOfMonth.subtract(const Duration(seconds: 1)),
                  ) &&
                  examDate.isBefore(
                    endOfMonth.add(const Duration(seconds: 1)),
                  )) {
                final ts = Timestamp.fromDate(examDate);
                allEvents.add(<String, dynamic>{
                  ...data,
                  'id': 'class_exam_${doc.id}',
                  'source': 'class_exam',
                  'title': 'Yazılı Sınav: $name ($lesson)',
                  'displayType': 'Sınav',
                  'type': 'Sınav',
                  'date': ts,
                  'startTime': ts,
                  'endTime': ts,
                });
              }
            }
          }
        }

        // E. trial_exams (Deneme Sınavları - Paralel sorgudan alındı)
        if (trialExamsSnapshot != null) {
          for (var doc in trialExamsSnapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final itemTermId = data['termId']?.toString().trim();
            if (activeTermId != null &&
                activeTermId.isNotEmpty &&
                itemTermId != null &&
                itemTermId.isNotEmpty) {
              if (itemTermId != activeTermId) continue;
            }

            final examDate = _parseDateTime(data['date']);
            final name = data['name'] ?? data['examName'] ?? 'Deneme Sınavı';
            final examGrade = (data['classLevel'] ?? data['gradeLevel'] ?? '')
                .toString()
                .trim();
            if (isStudentOrParent &&
                targetStudentGrade.isNotEmpty &&
                examGrade.isNotEmpty &&
                examGrade != targetStudentGrade) {
              continue;
            }

            if (examDate != null) {
              if (examDate.isAfter(
                    startOfMonth.subtract(const Duration(seconds: 1)),
                  ) &&
                  examDate.isBefore(
                    endOfMonth.add(const Duration(seconds: 1)),
                  )) {
                final startTs = Timestamp.fromDate(examDate);
                allEvents.add(<String, dynamic>{
                  ...data,
                  'id': 'trial_exam_${doc.id}',
                  'source': 'trial_exam',
                  'title': 'Deneme Sınavı: $name',
                  'displayType': 'Sınav',
                  'type': 'Sınav',
                  'date': startTs,
                  'startTime': startTs,
                  'endTime': startTs,
                  'rawStartTime':
                      '${examDate.hour.toString().padLeft(2, '0')}:${examDate.minute.toString().padLeft(2, '0')}',
                });
              }
            }
          }
        }
      }

      // ⚡ Değişiklik kontrolü: Sadece veri değiştiyse arayüzü ve önbelleği güncelle
      final hasChanged = !_eventsAreEqual(_events, allEvents);
      _lastFetchTime[cacheKey] = DateTime.now();

      if (hasChanged) {
        _memoryEventsCache[cacheKey] = allEvents;
        _saveToDiskCache(cacheKey, allEvents);
      }
      if (_activeTermName != null) {
        _memoryActiveTermName[cacheKey] = _activeTermName!;
      }

      if (mounted) {
        setState(() {
          if (hasChanged || _events.isEmpty) {
            _events = allEvents;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Etkinlik yükleme hatası: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onNavigateDate(DateTime newDay, {DateTime? newSelectedDay}) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final newKey =
        '${widget.institutionId}_${uid}_${widget.schoolTypeId}_${newDay.year}_${newDay.month}';
    final cached = _memoryEventsCache[newKey];
    setState(() {
      _focusedDay = newDay;
      if (newSelectedDay != null) _selectedDay = newSelectedDay;
      if (cached != null && cached.isNotEmpty) {
        _events = List<Map<String, dynamic>>.from(cached);
        _activeTermName = _memoryActiveTermName[newKey];
      }
    });
    if (cached == null || cached.isEmpty) {
      _loadFromDiskCache(newKey);
    }
    _loadEvents(isSilent: cached != null && cached.isNotEmpty);
  }

  String _formatTime(dynamic time) {
    if (time == null) return '';
    if (time is Timestamp) {
      return DateFormat('HH:mm').format(time.toDate());
    }
    if (time is DateTime) {
      return DateFormat('HH:mm').format(time);
    }
    final timeStr = time.toString().trim();
    if (timeStr.contains('T')) {
      final parsed = DateTime.tryParse(timeStr);
      if (parsed != null) {
        return DateFormat('HH:mm').format(parsed);
      }
    }
    return timeStr;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    bool isWideScreen = MediaQuery.of(context).size.width > 900;

    return Stack(
      children: [
        Align(
          alignment: isWideScreen ? Alignment.centerRight : Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWideScreen ? 750 : double.infinity,
            ),
            child: Container(
              margin: EdgeInsets.all(isWideScreen ? 24 : 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: isWideScreen
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          spreadRadius: 5,
                          blurRadius: 20,
                          offset: Offset(0, 10),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    child: _isLoading
                        ? const LinearProgressIndicator(
                            minHeight: 3,
                            backgroundColor: Colors.transparent,
                          )
                        : const SizedBox(height: 3),
                  ),
                  // Takvim Başlığı
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isWideScreen ? 24 : 16,
                      isWideScreen ? 24 : 12,
                      isWideScreen ? 24 : 8,
                      isWideScreen ? 16 : 6,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${_months[_focusedDay.month - 1]} ${_focusedDay.year}',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade900,
                                      ),
                                    ),
                                    if (_activeTermName != null &&
                                        _activeTermName!.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.blue.shade200,
                                          ),
                                        ),
                                        child: Text(
                                          _activeTermName!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.blue.shade800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _onNavigateDate(
                              DateTime.now(),
                              newSelectedDay: DateTime.now(),
                            );
                          },
                          child: Text('Bugün'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.blue,
                            padding: EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            if (_isWeeklyView) {
                              final newSel = _selectedDay.subtract(
                                Duration(days: 7),
                              );
                              _onNavigateDate(newSel, newSelectedDay: newSel);
                            } else {
                              final newFocused = DateTime(
                                _focusedDay.year,
                                _focusedDay.month - 1,
                              );
                              _onNavigateDate(newFocused);
                            }
                          },
                          icon: Icon(Icons.chevron_left_rounded),
                          splashRadius: 24,
                        ),
                        IconButton(
                          onPressed: () {
                            if (_isWeeklyView) {
                              final newSel = _selectedDay.add(
                                Duration(days: 7),
                              );
                              _onNavigateDate(newSel, newSelectedDay: newSel);
                            } else {
                              final newFocused = DateTime(
                                _focusedDay.year,
                                _focusedDay.month + 1,
                              );
                              _onNavigateDate(newFocused);
                            }
                          },
                          icon: Icon(Icons.chevron_right_rounded),
                          splashRadius: 24,
                        ),
                      ],
                    ),
                  ),
                  // Gün İsimleri
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: _daysOfWeek
                          .map(
                            (day) => Expanded(
                              child: Center(
                                child: Text(
                                  day,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueGrey.shade300,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  SizedBox(height: isWideScreen ? 8 : 4),
                  // Günler Grid (Clipped view fixed by removing Flexible and using NeverScrollableScrollPhysics)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: _isWeeklyView ? 8 : 2,
                    ),
                    child: _buildCalendarGrid(),
                  ),
                  SizedBox(height: isWideScreen ? 8 : 4),
                  // Seçili Gün Etkinlikleri
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWideScreen ? 24 : 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(24),
                          bottomRight: Radius.circular(24),
                        ),
                      ),
                      child: _buildEventList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Ekleme FAB (Öğrenci ve Veli rollerinde gizlenir)
        if (!((widget.userData?['role'] ??
                    UserPermissionService.cachedUserData?['role'] ??
                    '')
                .toString()
                .toLowerCase()
                .contains('student')) &&
            !((widget.userData?['role'] ??
                    UserPermissionService.cachedUserData?['role'] ??
                    '')
                .toString()
                .toLowerCase()
                .contains('ogrenci')) &&
            !((widget.userData?['role'] ??
                    UserPermissionService.cachedUserData?['role'] ??
                    '')
                .toString()
                .toLowerCase()
                .contains('öğrenci')) &&
            !((widget.userData?['role'] ??
                    UserPermissionService.cachedUserData?['role'] ??
                    '')
                .toString()
                .toLowerCase()
                .contains('parent')) &&
            !((widget.userData?['role'] ??
                    UserPermissionService.cachedUserData?['role'] ??
                    '')
                .toString()
                .toLowerCase()
                .contains('veli')))
          Positioned(
            right: isWideScreen ? 48 : 32,
            bottom: isWideScreen ? 48 : 32,
            child: FloatingActionButton(
              onPressed: () => _showAddEventDialog(),
              backgroundColor: Colors.blue,
              child: Icon(Icons.add_rounded, color: Colors.white, size: 30),
              elevation: 8,
            ),
          ),
      ],
    );
  }

  Widget _buildCalendarGrid() {
    bool isWideScreen = MediaQuery.of(context).size.width > 900;
    final firstDayOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final daysInMonth = DateTime(
      _focusedDay.year,
      _focusedDay.month + 1,
      0,
    ).day;
    int firstDayWeekday = firstDayOfMonth.weekday - 1;
    // Minimum 5 satır, gerekirse 6 (ayın günleri sığmıyorsa)
    final int neededRows = ((firstDayWeekday + daysInMonth) / 7).ceil();
    final int rowCount = neededRows < 5 ? 5 : neededRows;
    final totalCells = _isWeeklyView ? 7 : rowCount * 7;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: _isWeeklyView
            ? (isWideScreen ? 1.5 : 1.25)
            : (isWideScreen
                  ? 2.3
                  : 1.8), // Kompakt ve taşmayan dinamik en-boy oranı
      ),
      itemCount: totalCells,
      itemBuilder: (context, index) {
        DateTime currentDay;

        if (_isWeeklyView) {
          // Hafta görünümündeyse
          DateTime startOfWeek = _selectedDay.subtract(
            Duration(days: _selectedDay.weekday - 1),
          );
          currentDay = startOfWeek.add(Duration(days: index));
        } else {
          // Ay görünümündeyse
          int dayNum = index - firstDayWeekday + 1;
          bool isCurrentMonth = dayNum > 0 && dayNum <= daysInMonth;

          if (!isCurrentMonth) {
            // Önceki / sonraki ay günleri — soluk göster
            late DateTime adjacentDay;
            if (dayNum <= 0) {
              final prevMonthLastDay = DateTime(
                _focusedDay.year,
                _focusedDay.month,
                0,
              );
              adjacentDay = DateTime(
                prevMonthLastDay.year,
                prevMonthLastDay.month,
                prevMonthLastDay.day + dayNum,
              );
            } else {
              adjacentDay = DateTime(
                _focusedDay.year,
                _focusedDay.month + 1,
                dayNum - daysInMonth,
              );
            }
            final adjEvents = _events.where((e) {
              final dateVal = e['date'];
              if (dateVal == null) return false;
              final DateTime? eventDate = dateVal is Timestamp
                  ? dateVal.toDate()
                  : (dateVal is DateTime
                        ? dateVal
                        : DateTime.tryParse(dateVal.toString()));
              if (eventDate == null) return false;
              return eventDate.day == adjacentDay.day &&
                  eventDate.month == adjacentDay.month &&
                  eventDate.year == adjacentDay.year;
            }).toList();
            return InkWell(
              onTap: () {
                setState(() {
                  _selectedDay = adjacentDay;
                  _focusedDay = adjacentDay;
                  _loadEvents();
                });
              },
              borderRadius: BorderRadius.circular(100),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      adjacentDay.day.toString(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: Colors.blueGrey.shade300,
                      ),
                    ),
                    if (adjEvents.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 1),
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade300,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }

          currentDay = DateTime(_focusedDay.year, _focusedDay.month, dayNum);
        }

        bool isSelected =
            currentDay.day == _selectedDay.day &&
            currentDay.month == _selectedDay.month &&
            currentDay.year == _selectedDay.year;

        bool isToday =
            currentDay.day == DateTime.now().day &&
            currentDay.month == DateTime.now().month &&
            currentDay.year == DateTime.now().year;

        // Bu gün için etkinlikleri bul
        final dayEvents = _events.where((e) {
          final dateVal = e['date'];
          if (dateVal == null) return false;
          final DateTime? eventDate = dateVal is Timestamp
              ? dateVal.toDate()
              : (dateVal is DateTime
                    ? dateVal
                    : DateTime.tryParse(dateVal.toString()));
          if (eventDate == null) return false;
          return eventDate.day == currentDay.day &&
              eventDate.month == currentDay.month &&
              eventDate.year == currentDay.year;
        }).toList();

        return InkWell(
          onTap: () {
            setState(() {
              _selectedDay = currentDay;
              if (!_isWeeklyView && currentDay.month != _focusedDay.month) {
                _focusedDay = currentDay;
                _loadEvents();
              }
            });
          },
          onLongPress: () => _showAddEventDialog(date: currentDay),
          borderRadius: BorderRadius.circular(100),
          splashColor: Colors.blue.withValues(alpha: 0.1),
          highlightColor: Colors.transparent,
          child: Center(
            child: AnimatedContainer(
              duration: Duration(milliseconds: 250),
              curve: Curves.easeOutCirc,
              width: isWideScreen ? 38 : 34,
              height: isWideScreen ? 38 : 34,
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.blue
                    : (isToday
                          ? Colors.blue.withValues(alpha: 0.05)
                          : Colors.transparent),
                shape: BoxShape.circle,
                border: isToday && !isSelected
                    ? Border.all(
                        color: Colors.blue.withValues(alpha: 0.3),
                        width: 1.5,
                      )
                    : null,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    currentDay.day.toString(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: (isSelected || isToday)
                          ? FontWeight.bold
                          : FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : (isToday
                                ? Colors.blue.shade700
                                : Colors.blueGrey.shade700),
                    ),
                  ),
                  if (dayEvents.isNotEmpty)
                    Builder(
                      builder: (context) {
                        final hasDuty = dayEvents.any(
                          (e) =>
                              e['source'] == 'duty' ||
                              e['type'] == 'Nöbet' ||
                              e['displayType'] == 'Nöbet',
                        );
                        final dotColor = isSelected
                            ? Colors.white
                            : (hasDuty
                                  ? Colors.orange.shade700
                                  : Colors.blue.shade500);
                        return Container(
                          margin: const EdgeInsets.only(top: 1),
                          width: hasDuty ? 6 : 4,
                          height: hasDuty ? 6 : 4,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                            boxShadow: isSelected
                                ? null
                                : [
                                    BoxShadow(
                                      color: dotColor.withValues(alpha: 0.3),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEventList() {
    final selectedDayEvents = _events.where((e) {
      final dateVal = e['date'];
      if (dateVal == null) return false;
      final DateTime? eventDate = dateVal is Timestamp
          ? dateVal.toDate()
          : (dateVal is DateTime
                ? dateVal
                : DateTime.tryParse(dateVal.toString()));
      if (eventDate == null) return false;
      return eventDate.day == _selectedDay.day &&
          eventDate.month == _selectedDay.month &&
          eventDate.year == _selectedDay.year;
    }).toList();

    selectedDayEvents.sort((a, b) {
      final aTime = a['startTime'];
      final bTime = b['startTime'];
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      int timeCmp = 0;
      if (aTime is Timestamp && bTime is Timestamp) {
        timeCmp = aTime.compareTo(bTime);
      } else {
        timeCmp = aTime.toString().compareTo(bTime.toString());
      }
      if (timeCmp != 0) return timeCmp;
      // Aynı saatte: trial_exam önce, proctoring sonra
      int sourcePriority(Map e) {
        final src = e['source']?.toString() ?? '';
        if (src == 'trial_exam') return 0;
        if (src == 'proctoring') return 2;
        return 1;
      }

      return sourcePriority(a).compareTo(sourcePriority(b));
    });

    final bool isWideScreen = MediaQuery.of(context).size.width > 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: isWideScreen ? 16 : 8,
            bottom: isWideScreen ? 8 : 4,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_selectedDay.day} ${_months[_selectedDay.month - 1]}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: isWideScreen ? 16 : 15,
                  color: Colors.grey.shade800,
                ),
              ),
              Spacer(),
              IconButton(
                tooltip: _isWeeklyView
                    ? 'Aylık Görünüme Geç'
                    : 'Haftalık Görünüme Geç',
                icon: Icon(
                  _isWeeklyView
                      ? Icons.calendar_month_rounded
                      : Icons.calendar_view_week_rounded,
                  color: Colors.blue.shade600,
                  size: 20,
                ),
                splashRadius: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    _isWeeklyView = !_isWeeklyView;
                    if (_isWeeklyView) {
                      _focusedDay = _selectedDay;
                    }
                  });
                },
              ),
              const SizedBox(width: 8),
              Text(
                '${selectedDayEvents.length} Etkinlik',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
        Expanded(
          child: selectedDayEvents.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_note_rounded,
                            color: Colors.grey.shade300,
                            size: 32,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Bu gün için etkinlik yok',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: selectedDayEvents.length,
                  itemBuilder: (context, index) {
                    final event = selectedDayEvents[index];
                    return InkWell(
                      onTap: () => _showEventDetails(event),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        margin: EdgeInsets.only(bottom: 12),
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade100),
                        ),
                        child: Row(
                          children: [
                            _buildEventIcon(event),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    event['title'] ?? '',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (event['startTime'] != null)
                                    Builder(
                                      builder: (context) {
                                        final String classroom =
                                            (event['classroomName'] ??
                                                    event['classroom'] ??
                                                    event['classroomCode'] ??
                                                    event['roomName'] ??
                                                    event['room'] ??
                                                    event['derslikName'] ??
                                                    event['derslik'] ??
                                                    event['derslikAdi'] ??
                                                    '')
                                                .toString()
                                                .trim();
                                        final hasClassroom =
                                            classroom.isNotEmpty &&
                                            classroom != 'null';
                                        final isHomework =
                                            event['source'] == 'homework';
                                        final String description = isHomework
                                            ? (event['content'] ?? '')
                                                  .toString()
                                                  .trim()
                                            : '';
                                        final hasDescription =
                                            isHomework &&
                                            description.isNotEmpty;
                                        final isDuty =
                                            event['source'] == 'duty';
                                        final String dutyDesc = isDuty
                                            ? (event['description'] ??
                                                      event['locationDescription'] ??
                                                      '')
                                                  .toString()
                                                  .trim()
                                            : '';
                                        final hasDutyDesc =
                                            isDuty && dutyDesc.isNotEmpty;
                                        final dateStr = event['date'] != null
                                            ? _formatDateTr(
                                                event['date'],
                                                short: true,
                                              )
                                            : '';
                                        final hasTime =
                                            event['startTime'] != null;
                                        final rawStart =
                                            (event['rawStartTime'] ?? '')
                                                .toString()
                                                .trim();
                                        final rawEnd =
                                            (event['rawEndTime'] ?? '')
                                                .toString()
                                                .trim();
                                        final isTrialExam =
                                            event['source'] == 'trial_exam';
                                        final String timeStr;
                                        if (isTrialExam) {
                                          // Deneme sınavında sadece başlangıç saati
                                          timeStr = rawStart.isNotEmpty
                                              ? rawStart
                                              : (hasTime
                                                    ? _formatTime(
                                                        event['startTime'],
                                                      )
                                                    : '');
                                        } else if (rawStart.isNotEmpty &&
                                            rawEnd.isNotEmpty &&
                                            rawStart != rawEnd) {
                                          timeStr = '$rawStart - $rawEnd';
                                        } else if (rawStart.isNotEmpty) {
                                          timeStr = rawStart;
                                        } else if (hasTime &&
                                            event['endTime'] != null) {
                                          timeStr =
                                              '${_formatTime(event['startTime'])} - ${_formatTime(event['endTime'])}';
                                        } else if (hasTime) {
                                          timeStr = _formatTime(
                                            event['startTime'],
                                          );
                                        } else {
                                          timeStr = '';
                                        }
                                        final prefix =
                                            dateStr.isNotEmpty &&
                                                timeStr.isNotEmpty
                                            ? '$dateStr • $timeStr'
                                            : (dateStr.isNotEmpty
                                                  ? dateStr
                                                  : timeStr);
                                        final isProctoring =
                                            event['source'] == 'proctoring';
                                        final String proctoringClass =
                                            isProctoring
                                            ? (event['className'] ?? '')
                                                  .toString()
                                                  .trim()
                                            : '';
                                        return Text(
                                          prefix +
                                              (hasClassroom
                                                  ? ' • Derslik: $classroom'
                                                  : '') +
                                              (hasDescription
                                                  ? ' • $description'
                                                  : '') +
                                              (hasDutyDesc
                                                  ? ' • $dutyDesc'
                                                  : '') +
                                              (proctoringClass.isNotEmpty
                                                  ? ' • $proctoringClass'
                                                  : ''),
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                            if (event['source'] == 'activity')
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: Colors.grey.shade400,
                                ),
                                onPressed: () => _deleteEvent(event['id']),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEventIcon(Map<String, dynamic> event) {
    final source = event['source'] ?? 'activity';
    IconData icon = Icons.circle;
    Color color = Colors.blue;
    double size = 10;

    if (source == 'etut') {
      icon = Icons.book_rounded;
      color = Colors.indigo;
      size = 18;
    } else if (source == 'gezi') {
      icon = Icons.directions_bus_rounded;
      color = Colors.red;
      size = 18;
    } else if (source == 'lesson') {
      icon = Icons.class_rounded;
      color = Colors.blue;
      size = 18;
    } else if (source == 'duty') {
      icon = Icons.security_rounded;
      color = Colors.orange;
      size = 18;
    } else if (source == 'proctoring') {
      icon = Icons.supervised_user_circle_rounded;
      color = const Color(0xFF7C3AED);
      size = 18;
    } else if (source == 'homework') {
      icon = Icons.assignment_rounded;
      color = Colors.purple;
      size = 18;
    } else {
      color = _getEventColor(event['type']);
      icon = Icons.campaign_rounded;
      size = 18;
    }

    return Icon(icon, color: color, size: size);
  }

  void _showEventDetails(Map<String, dynamic> event) {
    final bool isEtut = event['source'] == 'etut';
    final bool isDuty =
        event['source'] == 'duty' ||
        event['type'] == 'Nöbet' ||
        event['displayType'] == 'Nöbet';
    final String title = event['title'] ?? 'Etkinlik Detayı';
    final String type = event['displayType'] ?? 'Genel';
    final String dateStr = _formatFullDateTr(event['date']);
    final rawStart = (event['rawStartTime'] ?? '').toString().trim();
    final rawEnd = (event['rawEndTime'] ?? '').toString().trim();
    final String timeStr;
    if (rawStart.isNotEmpty && rawEnd.isNotEmpty) {
      timeStr = '$rawStart - $rawEnd';
    } else if (rawStart.isNotEmpty) {
      timeStr = rawStart;
    } else if (event['startTime'] != null && event['endTime'] != null) {
      timeStr =
          '${_formatTime(event['startTime'])} - ${_formatTime(event['endTime'])}';
    } else if (event['startTime'] != null) {
      timeStr = _formatTime(event['startTime']);
    } else {
      timeStr = '';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getEventColor(
                        event['type'],
                      ).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: _buildEventIcon(event),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          '$type • $dateStr',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (timeStr.isNotEmpty)
                    _buildDetailItem(
                      Icons.access_time_rounded,
                      isDuty ? 'Nöbet Saati' : 'Saat',
                      timeStr,
                    ),

                  if (isDuty) ...[
                    Builder(
                      builder: (context) {
                        final locName =
                            (event['locationName'] ??
                                    event['dutyLocation'] ??
                                    '')
                                .toString()
                                .trim();
                        if (locName.isNotEmpty) {
                          return _buildDetailItem(
                            Icons.security_rounded,
                            'Nöbet Yeri',
                            locName,
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    Builder(
                      builder: (context) {
                        final dutyDesc =
                            (event['locationDescription'] ??
                                    event['description'] ??
                                    '')
                                .toString()
                                .trim();
                        if (dutyDesc.isNotEmpty) {
                          return _buildDetailItem(
                            Icons.info_outline_rounded,
                            'Nöbet Yeri Açıklaması',
                            dutyDesc,
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],

                  Builder(
                    builder: (context) {
                      final String classroom =
                          (event['classroomName'] ??
                                  event['classroom'] ??
                                  event['classroomCode'] ??
                                  event['roomName'] ??
                                  event['room'] ??
                                  event['derslikName'] ??
                                  event['derslik'] ??
                                  event['derslikAdi'] ??
                                  '')
                              .toString()
                              .trim();
                      if (classroom.isNotEmpty && classroom != 'null') {
                        return _buildDetailItem(
                          Icons.meeting_room_rounded,
                          'Derslik',
                          classroom,
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),

                  if (isEtut && event['topic'] != null)
                    _buildDetailItem(
                      Icons.auto_awesome_rounded,
                      'Kazanım Bilgisi',
                      event['topic'],
                    ),

                  if (!isDuty &&
                      event['description'] != null &&
                      event['description'].toString().trim().isNotEmpty)
                    _buildDetailItem(
                      Icons.description_outlined,
                      'Açıklama',
                      event['description'].toString().trim(),
                    ),

                  if (isEtut) ...[
                    // Öğrenci değilse katılımcı listesini göster
                    if (!((widget.userData?['role'] as String?)
                                ?.toLowerCase() ==
                            'ogrenci' ||
                        (widget.userData?['role'] as String?)?.toLowerCase() ==
                            'öğrenci')) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'Katılımcı Listesi',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (event['recipientNames'] != null)
                        ...(event['recipientNames'] as Map<String, dynamic>)
                            .entries
                            .map((entry) {
                              final userRole =
                                  (widget.userData?['role'] as String?)
                                      ?.toLowerCase();
                              final isStudentUser =
                                  userRole == 'ogrenci' ||
                                  userRole == 'öğrenci';

                              if (isStudentUser &&
                                  entry.key != widget.userData?['id']) {
                                return const SizedBox.shrink();
                              }
                              return _buildParticipantTile(
                                entry.value.toString(),
                              );
                            })
                            .toList()
                      else if (isEtut &&
                          event['studentIds'] != null &&
                          (event['studentIds'] as List).isNotEmpty)
                        FutureBuilder<List<String>>(
                          future: _fetchStudentNames(
                            event['studentIds'] as List<dynamic>,
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            }
                            if (!snapshot.hasData || snapshot.data!.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Text(
                                  'Katılımcı bilgisi bulunamadı.',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                              );
                            }

                            final names = snapshot.data!;
                            final userRole =
                                (widget.userData?['role'] as String?)
                                    ?.toLowerCase();
                            final isStudentUser =
                                userRole == 'ogrenci' || userRole == 'öğrenci';
                            final myId = widget.userData?['id'];
                            final studentIds =
                                event['studentIds'] as List<dynamic>;

                            return Column(
                              children: List.generate(names.length, (index) {
                                if (isStudentUser &&
                                    studentIds[index] != myId) {
                                  return const SizedBox.shrink();
                                }
                                return _buildParticipantTile(names[index]);
                              }),
                            );
                          },
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            'Katılımcı bilgisi bulunamadı.',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantTile(String name) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_outline,
              size: 16,
              color: Colors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<List<String>> _fetchStudentNames(List<dynamic> studentIds) async {
    try {
      List<String> results = [];
      // Firestore batch limit (10) for 'where in'
      for (var i = 0; i < studentIds.length; i += 10) {
        final chunk = studentIds.sublist(
          i,
          i + 10 > studentIds.length ? studentIds.length : i + 10,
        );
        final snap = await FirebaseFirestore.instance
            .collection('students')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        final Map<String, String> nameMap = {};
        for (var doc in snap.docs) {
          final data = doc.data();
          final name = data['name'] ?? 'İsimsiz';
          final sube = data['subeAdi'] ?? data['className'] ?? '';
          nameMap[doc.id] = sube.isNotEmpty ? '$name ($sube)' : name;
        }

        // Keep order
        for (var id in chunk) {
          if (nameMap.containsKey(id)) {
            results.add(nameMap[id]!);
          }
        }
      }
      return results;
    } catch (e) {
      debugPrint('Error fetching student names: $e');
      return [];
    }
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 20, color: Colors.grey.shade400),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ExpandableDetailText(label: label, value: value),
          ),
        ],
      ),
    );
  }

  Color _getEventColor(String? type) {
    switch (type) {
      case 'Önemli':
        return Colors.red;
      case 'Toplantı':
        return Colors.blue;
      case 'Duyuru':
        return Colors.green;
      case 'Etkinlik':
        return Colors.orange;
      case 'Ders':
        return Colors.blue;
      case 'Nöbet':
        return Colors.orange;
      case 'Ödev':
        return Colors.purple;
      default:
        return Colors.blue;
    }
  }

  Future<void> _showAddEventDialog({DateTime? date}) async {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final targetDate = date ?? _selectedDay;

    if (isMobile) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => Scaffold(
            appBar: EduknAppBar(
              title: 'Yeni Etkinlik',
              leading: IconButton(
                icon: Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: _AddEventForm(
              initialDate: targetDate,
              schoolTypeId: widget.schoolTypeId,
              onSave: (data) {
                _saveEvent(
                  title: data['title'],
                  type: data['type'],
                  date: data['date'],
                  endDate: data['endDate'],
                  startTime: data['startTime'],
                  endTime: data['endTime'],
                  recipientIds: data['recipientIds'],
                  recipientNames: data['recipientNames'],
                );
                Navigator.pop(context);
              },
            ),
          ),
        ),
      );
    } else {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_task_rounded,
                        color: Colors.blue,
                        size: 28,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Yeni Etkinlik',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Spacer(),
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    child: _AddEventForm(
                      initialDate: targetDate,
                      schoolTypeId: widget.schoolTypeId,
                      onSave: (data) {
                        _saveEvent(
                          title: data['title'],
                          type: data['type'],
                          date: data['date'],
                          endDate: data['endDate'],
                          startTime: data['startTime'],
                          endTime: data['endTime'],
                          recipientIds: data['recipientIds'],
                          recipientNames: data['recipientNames'],
                        );
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Future<void> _saveEvent({
    required String title,
    required String type,
    required DateTime date,
    required DateTime endDate,
    required String startTime,
    required String endTime,
    List<String>? recipientIds,
    Map<String, String>? recipientNames,
  }) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('activities').add({
        'institutionId': widget.institutionId,
        'schoolTypeId': widget.schoolTypeId,
        'title': title,
        'type': type,
        'date': Timestamp.fromDate(date),
        'endDate': Timestamp.fromDate(endDate),
        'startTime': startTime,
        'endTime': endTime,
        'recipientIds': recipientIds ?? [],
        'recipientNames': recipientNames ?? {},
        'createdBy': FirebaseAuth.instance.currentUser?.uid,
        'source': 'activity',
        'createdAt': FieldValue.serverTimestamp(),
      });
      _loadEvents();
    } catch (e) {
      debugPrint('Error saving event: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteEvent(String eventId) async {
    setState(() => _isLoading = true);
    try {
      final eventDoc = await FirebaseFirestore.instance
          .collection('activities')
          .doc(eventId)
          .get();

      if (eventDoc.exists && eventDoc.data()?['source'] == 'activity') {
        await eventDoc.reference.delete();
        _loadEvents();
      } else {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Sadece kendi oluşturduğunuz etkinlikleri silebilirsiniz.',
              ),
            ),
          );
      }
    } catch (e) {
      debugPrint('Error deleting event: $e');
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Silme hatası: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }
}

class _AddEventForm extends StatefulWidget {
  final DateTime initialDate;
  final String schoolTypeId;
  final Function(Map<String, dynamic>) onSave;

  const _AddEventForm({
    Key? key,
    required this.initialDate,
    required this.schoolTypeId,
    required this.onSave,
  }) : super(key: key);

  @override
  State<_AddEventForm> createState() => _AddEventFormState();
}

class _AddEventFormState extends State<_AddEventForm> {
  final _titleController = TextEditingController();
  String _selectedType = 'Etkinlik';
  late DateTime _startDate;
  late DateTime _endDate;
  TimeOfDay _startTime = TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = TimeOfDay(hour: 10, minute: 0);
  List<String> _selectedRecipients = [];
  Map<String, String> _recipientNames = {};

  @override
  void initState() {
    super.initState();
    _startDate = widget.initialDate;
    _endDate = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'Etkinlik Başlığı',
              hintText: 'Örn: Veli Toplantısı',
              prefixIcon: Icon(Icons.title_rounded, color: Colors.blue),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _selectedType,
            decoration: InputDecoration(
              labelText: 'Etkinlik Türü',
              prefixIcon: Icon(Icons.category_rounded, color: Colors.blue),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            items: [
              'Etkinlik',
              'Toplantı',
              'Duyuru',
              'Önemli',
            ].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (val) => setState(() => _selectedType = val!),
          ),
          SizedBox(height: 24),
          Text(
            'Tarih ve Saat',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          SizedBox(height: 16),
          // Start Date & Time
          Row(
            children: [
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _startDate = picked;
                        if (_endDate.isBefore(_startDate))
                          _endDate = _startDate;
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Başlangıç Tarihi',
                      prefixIcon: Icon(Icons.calendar_today_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      DateFormat('d MMM yyyy', 'tr').format(_startDate),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _startTime,
                    );
                    if (picked != null) setState(() => _startTime = picked);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Saat',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(_startTime.format(context)),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          // End Date & Time
          Row(
            children: [
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _endDate,
                      firstDate: _startDate,
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _endDate = picked);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Bitiş Tarihi',
                      prefixIcon: Icon(Icons.calendar_month_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      DateFormat('d MMM yyyy', 'tr').format(_endDate),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _endTime,
                    );
                    if (picked != null) setState(() => _endTime = picked);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Saat',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(_endTime.format(context)),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 24),
          RecipientSelectorField(
            selectedRecipients: _selectedRecipients,
            recipientNames: _recipientNames,
            schoolTypeId: widget.schoolTypeId,
            title: 'Kimler Görecek?',
            hint: 'Boş bırakılırsa sadece siz görürsünüz',
            onChanged: (list, names) {
              setState(() {
                _selectedRecipients = list;
                _recipientNames = names;
              });
            },
          ),
          SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              if (_titleController.text.isNotEmpty) {
                widget.onSave({
                  'title': _titleController.text,
                  'type': _selectedType,
                  'date': _startDate,
                  'endDate': _endDate,
                  'startTime':
                      '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
                  'endTime':
                      '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
                  'recipientIds': _selectedRecipients,
                  'recipientNames': _recipientNames,
                });
              }
            },
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              elevation: 4,
            ),
            child: Text(
              'Kaydet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
  };
}

class _ModuleCardWidget extends StatefulWidget {
  final String title;
  final String badge;
  final IconData icon;
  final Color color;
  final List<Map<String, dynamic>> items;
  final VoidCallback onTap;
  final double cardWidth;
  final bool isMobile;
  final String category;
  final bool showAllItems;

  const _ModuleCardWidget({
    Key? key,
    required this.title,
    required this.badge,
    required this.icon,
    required this.color,
    required this.items,
    required this.onTap,
    required this.cardWidth,
    required this.isMobile,
    required this.category,
    this.showAllItems = false,
  }) : super(key: key);
  @override
  State<_ModuleCardWidget> createState() => _ModuleCardWidgetState();
}

class _ModuleCardWidgetState extends State<_ModuleCardWidget> {
  bool isCardHovered = false;
  int? hoveredItemIndex;
  @override
  Widget build(BuildContext context) {
    final displayedItems = widget.showAllItems
        ? widget.items
        : widget.items.take(3).toList();
    final remainingCount = widget.items.length - displayedItems.length;
    final String label = remainingCount > 0
        ? '+$remainingCount işlem daha görüntüle'
        : ('GÖRÜNTÜLE');
    return MouseRegion(
      onEnter: (_) => setState(() => isCardHovered = true),
      onExit: (_) => setState(() => isCardHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: widget.cardWidth,
        constraints: BoxConstraints(
          minHeight: (widget.isMobile || widget.showAllItems) ? 0 : 380,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: isCardHovered || widget.showAllItems ? 0.08 : 0.03,
              ),
              blurRadius: isCardHovered || widget.showAllItems ? 30 : 20,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(
            color: isCardHovered || widget.showAllItems
                ? widget.color.withValues(alpha: 0.3)
                : Colors.indigo.withValues(alpha: 0.05),
            width: 1.5,
          ),
        ),
        alignment: Alignment
            .center, // İçeriği merkeze hizala (Dikey ortalama isteği için)
        padding: EdgeInsets.all(widget.isMobile ? 20 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 28),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.badge,
                    style: TextStyle(
                      color: widget.color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: widget.isMobile ? 18 : 22,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1E293B),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 24),
            ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayedItems.length,
              itemBuilder: (context, index) {
                final item = displayedItems[index];
                final isHovered = hoveredItemIndex == index;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: MouseRegion(
                    onEnter: (_) => setState(() => hoveredItemIndex = index),
                    onExit: (_) => setState(() => hoveredItemIndex = null),
                    child: InkWell(
                      onTap: item['onTap'] as VoidCallback,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isHovered
                                    ? widget.color
                                    : Colors.blueGrey.shade200,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item['title'] as String,
                                style: TextStyle(
                                  color: isHovered
                                      ? widget.color
                                      : Colors.blueGrey.shade600,
                                  fontSize: 14,
                                  fontWeight: isHovered
                                      ? FontWeight.w900
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: isHovered
                                  ? widget.color
                                  : Colors.blueGrey.shade300,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16), // Boşluğu biraz artırdık
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isCardHovered
                      ? widget.color
                      : const Color(0xFFF1F5F9),
                  foregroundColor: isCardHovered
                      ? Colors.white
                      : Colors.blueGrey.shade700,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                  ), // 18 -> 12 düşürüldü
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DoodlePainter extends CustomPainter {
  const DoodlePainter();
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    const iconSize = 40.0;
    const spacing = 120.0;
    final icons = [
      Icons.school,
      Icons.book,
      Icons.edit,
      Icons.science,
      Icons.calculate,
      Icons.public,
      Icons.history_edu,
      Icons.psychology,
      Icons.menu_book,
      Icons.biotech,
      Icons.brush,
      Icons.music_note,
    ];
    final random = math.Random(42);
    for (double x = 0; x < size.width + spacing; x += spacing) {
      for (double y = 0; y < size.height + spacing; y += spacing) {
        final iconData = icons[random.nextInt(icons.length)];
        final jitterX = random.nextDouble() * 40 - 20;
        final jitterY = random.nextDouble() * 40 - 20;
        final rotation = random.nextDouble() * 0.5 - 0.25;

        final textPainter = TextPainter(
          textDirection: ui.TextDirection.ltr,
          text: TextSpan(
            text: String.fromCharCode(iconData.codePoint),
            style: TextStyle(
              fontSize: iconSize,
              fontFamily: iconData.fontFamily,
              package: iconData.fontPackage,
              color: Colors.indigo.withValues(
                alpha: 0.02 + random.nextDouble() * 0.03,
              ),
            ),
          ),
        );
        textPainter.layout();
        canvas.save();
        canvas.translate(x + jitterX, y + jitterY);
        canvas.rotate(rotation);
        textPainter.paint(
          canvas,
          Offset(-textPainter.width / 2, -textPainter.height / 2),
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class _ExpandableDetailText extends StatelessWidget {
  final String label;
  final String value;
  const _ExpandableDetailText({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}
