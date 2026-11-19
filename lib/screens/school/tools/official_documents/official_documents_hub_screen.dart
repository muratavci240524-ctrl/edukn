import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../models/school/official_document_model.dart';
import '../../../../services/official_document_context_service.dart';
import '../../../../widgets/edukn_app_bar.dart';
import 'oddk_bulk_dossier_screen.dart';
import 'official_document_catalog.dart';
import 'official_document_wizard_screen.dart';

enum _HubTabMode { catalog, archive }

enum _AudienceFilter { all, admin, teacher, common }

enum _RegulationFilter { all, oddkDisiplin, ilkogretim, ortaogretim, ozelKurs }

/// Tek başına sayfa olarak açılmak istendiğinde kullanılan sarmalayıcı ekran
class OfficialDocumentsHubScreen extends StatelessWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final bool isTeacher;
  final String? teacherId;
  final List<String>? allowedClassIds;

  const OfficialDocumentsHubScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.isTeacher = false,
    this.teacherId,
    this.allowedClassIds,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: EduknAppBar(
        title: 'Resmi Evrak ve Matbu Şablon Merkezi',
        subtitle: schoolTypeName,
      ),
      body: OfficialDocumentsHubBody(
        institutionId: institutionId,
        schoolTypeId: schoolTypeId,
        schoolTypeName: schoolTypeName,
        isTeacher: isTeacher,
        teacherId: teacherId,
        allowedClassIds: allowedClassIds,
      ),
    );
  }
}

/// Araçlar -> Evrak sekmesinin doğrudan içinde de gömülü çalışan ana gövde bileşeni
class OfficialDocumentsHubBody extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final bool isTeacher;
  final String? teacherId;
  final List<String>? allowedClassIds;

  const OfficialDocumentsHubBody({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.isTeacher = false,
    this.teacherId,
    this.allowedClassIds,
  }) : super(key: key);

  @override
  State<OfficialDocumentsHubBody> createState() =>
      _OfficialDocumentsHubBodyState();
}

class _OfficialDocumentsHubBodyState extends State<OfficialDocumentsHubBody> {
  final OfficialDocumentContextService _contextService =
      OfficialDocumentContextService();
  final TextEditingController _searchController = TextEditingController();

  _HubTabMode _tabMode = _HubTabMode.catalog;
  _AudienceFilter _audienceFilter = _AudienceFilter.all;
  _RegulationFilter _regulationFilter = _RegulationFilter.all;
  bool _showPassiveArchive = false;
  String _searchQuery = '';
  final Set<String> _collapsedCategoryIds = {};

  static String _normTr(String input) {
    return input
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .replaceAll('Ş', 'ş')
        .replaceAll('Ğ', 'ğ')
        .replaceAll('Ü', 'ü')
        .replaceAll('Ö', 'ö')
        .replaceAll('Ç', 'ç')
        .toLowerCase();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesRegulationFilter(OfficialDocTemplate t) {
    switch (_regulationFilter) {
      case _RegulationFilter.all:
        return true;
      case _RegulationFilter.oddkDisiplin:
        return t.categoryId == 'oddk_disiplin_surec_paketi' ||
            t.categoryId == 'idari_disiplin_kaza' ||
            t.id.contains('oddk') ||
            t.id.contains('disiplin');
      case _RegulationFilter.ilkogretim:
        return t.scopes.contains(DocRegulationScope.ilkogretimOkulOncesi) ||
            t.scopes.contains(DocRegulationScope.ortakMevzuat);
      case _RegulationFilter.ortaogretim:
        return t.scopes.contains(DocRegulationScope.ortaogretimLise) ||
            t.scopes.contains(DocRegulationScope.ortakMevzuat);
      case _RegulationFilter.ozelKurs:
        return t.scopes.contains(DocRegulationScope.ozelOgretimKurs) ||
            t.scopes.contains(DocRegulationScope.ortakMevzuat);
    }
  }

  bool _matchesAudienceFilter(OfficialDocTemplate t) {
    if (widget.isTeacher && t.audience == DocAudience.admin) {
      return false;
    }
    switch (_audienceFilter) {
      case _AudienceFilter.all:
        return true;
      case _AudienceFilter.admin:
        return t.audience == DocAudience.admin ||
            t.categoryId == 'oddk_disiplin_surec_paketi' ||
            t.categoryId == 'idari_gezi_toren';
      case _AudienceFilter.teacher:
        return t.audience == DocAudience.teacher ||
            (t.categoryId == 'oddk_disiplin_surec_paketi' &&
                t.audience == DocAudience.common);
      case _AudienceFilter.common:
        return t.audience == DocAudience.common;
    }
  }

  List<OfficialDocCategory> get _visibleCategories {
    final cats = OfficialDocumentCatalog.safeCategories
        .where((cat) => _templatesForCategory(cat).isNotEmpty)
        .toList();

    // Belirli bir yönetmelik veya ÖDDK paketi seçildiğinde o başlığı en üste taşı
    if (_regulationFilter != _RegulationFilter.all) {
      String priorityId = '';
      if (_regulationFilter == _RegulationFilter.oddkDisiplin) {
        priorityId = 'oddk_disiplin_surec_paketi';
      } else if (_regulationFilter == _RegulationFilter.ilkogretim) {
        priorityId = 'ilkogretim_okul_oncesi_ozel';
      } else if (_regulationFilter == _RegulationFilter.ortaogretim) {
        priorityId = 'ortaogretim_lise_ozel';
      } else if (_regulationFilter == _RegulationFilter.ozelKurs) {
        priorityId = 'ozel_ogretim_kurs_ozel';
      }
      cats.sort((a, b) {
        if (a.id == priorityId) return -1;
        if (b.id == priorityId) return 1;
        return a.order.compareTo(b.order);
      });
    }
    return cats;
  }

  List<OfficialDocTemplate> _templatesForCategory(OfficialDocCategory cat) {
    final q = _normTr(_searchQuery.trim());
    return OfficialDocumentCatalog.templates.where((t) {
      if (t.categoryId != cat.id) return false;
      if (!_matchesAudienceFilter(t)) return false;
      if (!_matchesRegulationFilter(t)) return false;
      if (q.isEmpty) return true;
      return _normTr(t.title).contains(q) ||
          _normTr(t.subtitle).contains(q) ||
          _normTr(t.code).contains(q) ||
          _normTr(t.legalBasis).contains(q) ||
          _normTr(cat.title).contains(q);
    }).toList();
  }

  void _openTemplate(
    OfficialDocTemplate template,
    OfficialDocCategory category, {
    SavedOfficialDocument? existing,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OfficialDocumentWizardScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
          template: template,
          category: category,
          existingDocument: existing,
          allowedClassIds: widget.allowedClassIds,
        ),
      ),
    );
  }

  void _openOddkBulkDossier({SavedOfficialDocument? existing}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OddkBulkDossierScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
          existingDocument: existing,
          allowedClassIds: widget.allowedClassIds,
        ),
      ),
    );
  }

  String _layoutBadgeText(OfficialDocTemplate t) {
    switch (t.layoutKind) {
      case DocLayoutKind.officialLetter:
        return t.defaultHeaderStyle == DocHeaderStyle.mebOfficial
            ? 'MEB Resmi Yazı'
            : 'Resmi Belge';
      case DocLayoutKind.meetingMinutes:
        return 'Tutanak & İmza';
      case DocLayoutKind.incidentForm:
        return 'Olay / Form';
      case DocLayoutKind.circularSignatureTable:
        return 'İmza Sirküsü';
      case DocLayoutKind.bulkParentSlip:
        return 'Toplu Veli Fişi';
      case DocLayoutKind.dynamicChecklist:
        return 'Dinamik Tablo';
      case DocLayoutKind.badgeGrid:
        return 'QR Kart & Liste';
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 760;
    final currentUid =
        widget.teacherId ?? FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<List<SavedOfficialDocument>>(
      stream: _contextService.streamDocuments(
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        onlyCreatedByMe: widget.isTeacher,
        currentUserId: currentUid,
      ),
      builder: (context, snapshot) {
        final allSaved = snapshot.data ?? const <SavedOfficialDocument>[];
        final activeDocs = allSaved.where((d) => !d.isPassive).toList();
        final passiveDocs = allSaved.where((d) => d.isPassive).toList();

        final categories = _visibleCategories;
        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.all(isMobile ? 14 : 22),
          children: [
            _buildTopControlHeader(
              isMobile: isMobile,
              activeCount: activeDocs.length,
              passiveCount: passiveDocs.length,
              categoryCount: categories.length,
            ),
            const SizedBox(height: 16),
            if (_tabMode == _HubTabMode.catalog)
              ..._buildCatalogChildren(isMobile, categories)
            else
              ..._buildArchiveChildren(
                isMobile: isMobile,
                activeDocs: activeDocs,
                passiveDocs: passiveDocs,
                isLoading:
                    snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData,
              ),
          ],
        );
      },
    );
  }

  Widget _buildTopControlHeader({
    required bool isMobile,
    required int activeCount,
    required int passiveCount,
    required int categoryCount,
  }) {
    final visibleTemplateCount = OfficialDocumentCatalog.templates
        .where((t) => !widget.isTeacher || t.audience != DocAudience.admin)
        .length;

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E3A8A), Color(0xFF1D4ED8)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final wideHeader = constraints.maxWidth >= 880;
              final titleRow = Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.description_rounded,
                      color: Color(0xFF93C5FD),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resmi Evrak ve Matbu Şablon Merkezi',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 16.5 : 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Soruları yanıtlayın, metni canlı düzenleyin ve antetli resmi A4 PDF çıktınızı anında alın ($visibleTemplateCount şablon)',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 11.8 : 12.6,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              final switcher = Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                child: Row(
                  mainAxisSize: wideHeader
                      ? MainAxisSize.min
                      : MainAxisSize.max,
                  children: [
                    if (wideHeader) ...[
                      _buildModeButton(
                        selected: _tabMode == _HubTabMode.catalog,
                        icon: Icons.folder_copy_rounded,
                        label: 'Matbu Şablonlar',
                        badgeCount: visibleTemplateCount,
                        onTap: () =>
                            setState(() => _tabMode = _HubTabMode.catalog),
                      ),
                      const SizedBox(width: 4),
                      _buildModeButton(
                        selected: _tabMode == _HubTabMode.archive,
                        icon: Icons.inventory_2_rounded,
                        label: 'Hazırlanan Evraklar',
                        badgeCount: activeCount,
                        onTap: () =>
                            setState(() => _tabMode = _HubTabMode.archive),
                      ),
                    ] else ...[
                      Expanded(
                        child: _buildModeButton(
                          selected: _tabMode == _HubTabMode.catalog,
                          icon: Icons.folder_copy_rounded,
                          label: 'Matbu Şablonlar',
                          badgeCount: visibleTemplateCount,
                          onTap: () =>
                              setState(() => _tabMode = _HubTabMode.catalog),
                        ),
                      ),
                      Expanded(
                        child: _buildModeButton(
                          selected: _tabMode == _HubTabMode.archive,
                          icon: Icons.inventory_2_rounded,
                          label: 'Hazırlanan Evraklar',
                          badgeCount: activeCount,
                          onTap: () =>
                              setState(() => _tabMode = _HubTabMode.archive),
                        ),
                      ),
                    ],
                  ],
                ),
              );

              if (wideHeader) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: titleRow),
                    const SizedBox(width: 16),
                    switcher,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [titleRow, const SizedBox(height: 14), switcher],
              );
            },
          ),
          const SizedBox(height: 16),
          // Genişliğe göre hesaplanan 2x2 (mobil) / 4x1 (web) KPI kartları
          LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final isTwoByTwo = maxW < 680;
              final gap = maxW < 400 ? 8.0 : 10.0;
              final cardWidth = isTwoByTwo
                  ? (maxW - gap) / 2
                  : (maxW - gap * 3) / 4;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _buildHeaderKpiCard(
                    width: cardWidth,
                    label: 'Matbu Şablon',
                    value: '$visibleTemplateCount',
                    sub: 'Bakanlık Uyumlu A4',
                    accent: const Color(0xFF93C5FD),
                  ),
                  _buildHeaderKpiCard(
                    width: cardWidth,
                    label: 'Mevzuat Başlığı',
                    value: '$categoryCount',
                    sub: 'Aktif Kategori',
                    accent: const Color(0xFF6EE7B7),
                  ),
                  _buildHeaderKpiCard(
                    width: cardWidth,
                    label: 'Aktif Evrak',
                    value: '$activeCount',
                    sub: 'Kayıtlı & Düzenlenebilir',
                    accent: const Color(0xFFFDE68A),
                  ),
                  _buildHeaderKpiCard(
                    width: cardWidth,
                    label: 'Pasif / Arşiv',
                    value: '$passiveCount',
                    sub: 'Arşivlenen Evrak',
                    accent: const Color(0xFFC4B5FD),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderKpiCard({
    required double width,
    required String label,
    required String value,
    required String sub,
    required Color accent,
  }) {
    final compact = width < 165;
    final hPad = compact ? 10.0 : 14.0;
    final vPad = compact ? 9.0 : 11.0;
    final valSize = (width * 0.115).clamp(16.5, 21.0);

    return SizedBox(
      width: width,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: compact ? 10.5 : 11.2,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: valSize,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: compact ? 10.0 : 11.0,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton({
    required bool selected,
    required IconData icon,
    required String label,
    required int badgeCount,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? const Color(0xFF1E3A8A) : Colors.white,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12.2,
                  fontWeight: FontWeight.w700,
                  color: selected ? const Color(0xFF1E3A8A) : Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF1E3A8A).withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$badgeCount',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? const Color(0xFF1E3A8A) : Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1) ŞABLON KATALOĞU (BAŞLIK BAŞLIK AYRIŞTIRILMIŞ GÖRÜNÜM)
  // ═══════════════════════════════════════════════════════════════════════════
  List<Widget> _buildCatalogChildren(
    bool isMobile,
    List<OfficialDocCategory> categories,
  ) {
    final hasAnyMatch = categories.any(
      (c) => _templatesForCategory(c).isNotEmpty,
    );

    final searchBox = TextField(
      controller: _searchController,
      style: const TextStyle(fontSize: 13),
      onChanged: (v) => setState(() => _searchQuery = v),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        hintText:
            'Evrak, yönetmelik veya madde ara (ÖDDK, EK-9 Sözleşme, Savunma, Görgü Tanığı, İYEP, Zümre...)',
        hintStyle: const TextStyle(fontSize: 12.2, color: Color(0xFF94A3B8)),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 19,
          color: Color(0xFF64748B),
        ),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 17),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
    );

    final collapseButton = OutlinedButton.icon(
      onPressed: () {
        setState(() {
          if (_collapsedCategoryIds.length >= categories.length &&
              categories.isNotEmpty) {
            _collapsedCategoryIds.clear();
          } else {
            for (final c in categories) {
              _collapsedCategoryIds.add(c.id);
            }
          }
        });
      },
      style: OutlinedButton.styleFrom(
        backgroundColor: const Color(0xFFF8FAFC),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(
        _collapsedCategoryIds.length >= categories.length &&
                categories.isNotEmpty
            ? Icons.unfold_more_rounded
            : Icons.unfold_less_rounded,
        size: 17,
        color: const Color(0xFF334155),
      ),
      label: Text(
        _collapsedCategoryIds.length >= categories.length &&
                categories.isNotEmpty
            ? 'Tümünü Aç'
            : 'Daralt',
        style: const TextStyle(
          fontSize: 11.8,
          fontWeight: FontWeight.w700,
          color: Color(0xFF334155),
        ),
      ),
    );

    final roleChipsRow = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip(_AudienceFilter.all, 'Tüm Roller'),
          if (!widget.isTeacher)
            _buildFilterChip(_AudienceFilter.admin, 'İdari Evraklar'),
          _buildFilterChip(_AudienceFilter.teacher, 'Öğretmen Evrakları'),
          _buildFilterChip(
            _AudienceFilter.common,
            'Gezi, Veli İzin & Listeler',
          ),
        ],
      ),
    );

    final regulationChipsRow = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildRegulationChip(
            _RegulationFilter.all,
            'Tüm Yönetmelikler',
            const Color(0xFF0F172A),
          ),
          _buildRegulationChip(
            _RegulationFilter.oddkDisiplin,
            'ÖDDK & Disiplin Süreci (16 Adım)',
            const Color(0xFF991B1B),
          ),
          _buildRegulationChip(
            _RegulationFilter.ilkogretim,
            'İlköğretim & Okul Öncesi Yön.',
            const Color(0xFF0D9488),
          ),
          _buildRegulationChip(
            _RegulationFilter.ortaogretim,
            'Ortaöğretim (Lise) Yön.',
            const Color(0xFF1D4ED8),
          ),
          _buildRegulationChip(
            _RegulationFilter.ozelKurs,
            'Özel Öğretim & Kurslar Yön. (5580)',
            const Color(0xFF9333EA),
          ),
        ],
      ),
    );

    return [
      Container(
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wideToolbar = constraints.maxWidth >= 960;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (wideToolbar)
                  Row(
                    children: [
                      Expanded(flex: 5, child: searchBox),
                      const SizedBox(width: 12),
                      Flexible(flex: 6, child: roleChipsRow),
                      const SizedBox(width: 8),
                      collapseButton,
                    ],
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(child: searchBox),
                      const SizedBox(width: 8),
                      collapseButton,
                    ],
                  ),
                  const SizedBox(height: 8),
                  roleChipsRow,
                ],
                const SizedBox(height: 8),
                regulationChipsRow,
              ],
            );
          },
        ),
      ),
      const SizedBox(height: 16),
      if (_regulationFilter == _RegulationFilter.oddkDisiplin &&
          _collapsedCategoryIds.contains('oddk_disiplin_surec_paketi')) ...[
        _buildBulkDossierLaunchBanner(isMobile: isMobile),
        const SizedBox(height: 14),
      ],
      if (!hasAnyMatch)
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 40,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 8),
              const Text(
                'Aramanızla eşleşen matbu şablon bulunamadı.',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
        )
      else
        for (final cat in categories) ...[
          if (_templatesForCategory(cat).isNotEmpty)
            _buildCategorySection(
              cat: cat,
              templates: _templatesForCategory(cat),
              isMobile: isMobile,
            ),
        ],
    ];
  }

  Widget _buildFilterChip(_AudienceFilter filter, String label) {
    final selected = _audienceFilter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        selected: selected,
        label: Text(
          label,
          style: TextStyle(
            fontSize: 11.8,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF334155),
          ),
        ),
        selectedColor: const Color(0xFF1E3A8A),
        backgroundColor: Colors.white,
        side: BorderSide(
          color: selected ? const Color(0xFF1E3A8A) : const Color(0xFFE2E8F0),
        ),
        visualDensity: VisualDensity.compact,
        showCheckmark: false,
        onSelected: (_) => setState(() => _audienceFilter = filter),
      ),
    );
  }

  Widget _buildRegulationChip(
    _RegulationFilter filter,
    String label,
    Color activeColor,
  ) {
    final selected = _regulationFilter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        selected: selected,
        avatar: Icon(
          Icons.gavel_rounded,
          size: 13,
          color: selected ? Colors.white : activeColor,
        ),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 11.4,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF334155),
          ),
        ),
        selectedColor: activeColor,
        backgroundColor: Colors.white,
        side: BorderSide(
          color: selected ? activeColor : const Color(0xFFE2E8F0),
        ),
        visualDensity: VisualDensity.compact,
        showCheckmark: false,
        onSelected: (_) => setState(() => _regulationFilter = filter),
      ),
    );
  }

  Widget _buildCategorySection({
    required OfficialDocCategory cat,
    required List<OfficialDocTemplate> templates,
    required bool isMobile,
  }) {
    final isCollapsed =
        _collapsedCategoryIds.contains(cat.id) && _searchQuery.isEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık Şeridi
          InkWell(
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(15),
              bottom: Radius.circular(isCollapsed ? 15 : 0),
            ),
            onTap: () {
              setState(() {
                if (_collapsedCategoryIds.contains(cat.id)) {
                  _collapsedCategoryIds.remove(cat.id);
                } else {
                  _collapsedCategoryIds.add(cat.id);
                }
              });
            },
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 16,
                vertical: 11,
              ),
              decoration: BoxDecoration(
                color: cat.color.withValues(alpha: 0.05),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(14),
                  bottom: Radius.circular(isCollapsed ? 14 : 0),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cat.color,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(cat.icon, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cat.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 13.5 : 14.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                            height: 1.22,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cat.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11.3,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: cat.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${templates.length} Şablon',
                      style: TextStyle(
                        fontSize: 10.8,
                        fontWeight: FontWeight.w800,
                        color: cat.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isCollapsed
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    color: const Color(0xFF64748B),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          if (!isCollapsed)
            Padding(
              padding: EdgeInsets.all(isMobile ? 10 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (cat.id == 'oddk_disiplin_surec_paketi') ...[
                    _buildBulkDossierLaunchBanner(isMobile: isMobile),
                    const SizedBox(height: 12),
                  ],
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final maxW = constraints.maxWidth;
                      final cols = maxW >= 1480
                          ? 4
                          : (maxW >= 1040 ? 3 : (maxW >= 640 ? 2 : 1));
                      if (cols == 1) {
                        return Column(
                          children: [
                            for (int i = 0; i < templates.length; i++) ...[
                              _buildTemplateCard(
                                templates[i],
                                cat,
                                isMobile: true,
                              ),
                              if (i < templates.length - 1)
                                const SizedBox(height: 8),
                            ],
                          ],
                        );
                      }

                      final rows = <Widget>[];
                      for (int i = 0; i < templates.length; i += cols) {
                        final rowChildren = <Widget>[];
                        for (int c = 0; c < cols; c++) {
                          if (c > 0) rowChildren.add(const SizedBox(width: 12));
                          final idx = i + c;
                          rowChildren.add(
                            Expanded(
                              child: idx < templates.length
                                  ? _buildTemplateCard(
                                      templates[idx],
                                      cat,
                                      isMobile: false,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          );
                        }
                        rows.add(
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: rowChildren,
                            ),
                          ),
                        );
                        if (i + cols < templates.length) {
                          rows.add(const SizedBox(height: 12));
                        }
                      }
                      return Column(children: rows);
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBulkDossierLaunchBanner({required bool isMobile}) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7F1D1D), Color(0xFF991B1B), Color(0xFF1E3A8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF991B1B).withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isBannerWide = constraints.maxWidth >= 760;
          final infoRow = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.folder_special_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Toplu Soruşturma Vaka Dosyası Üretici (ÖDDK-01 .. ÖDDK-16 Tek PDF)',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 13 : 14.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Öğrenci, veli, olay özeti ve kurul bilgilerini tek seferde girin; seçtiğiniz tüm ÖDDK/Disiplin adımlarını kapak sayfası ve kronolojik dizi pusulasıyla birleşik TEK PDF vaka dosyası olarak indirin.',
                      style: GoogleFonts.inter(
                        fontSize: 11.6,
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.34,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final launchBtn = ElevatedButton.icon(
            onPressed: () => _openOddkBulkDossier(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF991B1B),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.auto_awesome_motion_rounded, size: 17),
            label: const Text(
              'Toplu Vaka Dosyası Oluştur',
              style: TextStyle(fontSize: 12.4, fontWeight: FontWeight.w800),
            ),
          );

          if (isBannerWide) {
            return Row(
              children: [
                Expanded(child: infoRow),
                const SizedBox(width: 16),
                launchBtn,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [infoRow, const SizedBox(height: 12), launchBtn],
          );
        },
      ),
    );
  }

  Widget _buildTemplateCard(
    OfficialDocTemplate template,
    OfficialDocCategory category, {
    required bool isMobile,
  }) {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openTemplate(template, category),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 11 : 13,
            vertical: 11,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: category.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(template.icon, size: 19, color: category.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: category.color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            template.code,
                            style: TextStyle(
                              fontSize: 10.2,
                              fontWeight: FontWeight.w800,
                              color: category.color,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFE2E8F0,
                            ).withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            _layoutBadgeText(template),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      template.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13.2,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      template.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11.4,
                        color: const Color(0xFF64748B),
                        height: 1.28,
                      ),
                    ),
                    if (template.legalBasis.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                            Icons.menu_book_rounded,
                            size: 11.5,
                            color: category.color.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              template.legalBasis,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 10.4,
                                fontWeight: FontWeight.w700,
                                color: category.color.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: category.color.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2) HAZIRLANAN EVRAKLAR ARŞİVİ (AKTİF / PASİF SEKME MANTIĞI)
  // ═══════════════════════════════════════════════════════════════════════════
  List<Widget> _buildArchiveChildren({
    required bool isMobile,
    required List<SavedOfficialDocument> activeDocs,
    required List<SavedOfficialDocument> passiveDocs,
    required bool isLoading,
  }) {
    final displayed = _showPassiveArchive ? passiveDocs : activeDocs;

    return [
      // Aktif / Pasif Alt Sekmesi
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFE2E8F0).withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildArchiveStatusTab(
                selected: !_showPassiveArchive,
                icon: Icons.play_circle_outline_rounded,
                label: 'Aktif Evraklar',
                count: activeDocs.length,
                onTap: () => setState(() => _showPassiveArchive = false),
              ),
            ),
            Expanded(
              child: _buildArchiveStatusTab(
                selected: _showPassiveArchive,
                icon: Icons.inventory_2_outlined,
                label: 'Pasif (Arşiv)',
                count: passiveDocs.length,
                onTap: () => setState(() => _showPassiveArchive = true),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      if (isLoading)
        const Padding(
          padding: EdgeInsets.all(36),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (displayed.isEmpty)
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              Icon(
                _showPassiveArchive
                    ? Icons.inventory_2_outlined
                    : Icons.description_outlined,
                size: 42,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 10),
              Text(
                _showPassiveArchive
                    ? 'Pasife alınmış evrak bulunmuyor.'
                    : 'Henüz kaydedilmiş aktif bir resmi evrak bulunmuyor.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Matbu Şablonlar sekmesinden bir evrak seçip hazırladığınızda buradan tekrar açıp düzenleyebilir veya PDF çıktısı alabilirsiniz.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth;
            final cols = maxW >= 1480
                ? 4
                : (maxW >= 1040 ? 3 : (maxW >= 660 ? 2 : 1));
            if (cols == 1) {
              return Column(
                children: [
                  for (final doc in displayed) ...[
                    _buildSavedDocCard(doc, stretchHeight: false),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            }
            final rows = <Widget>[];
            for (int i = 0; i < displayed.length; i += cols) {
              final rowChildren = <Widget>[];
              for (int c = 0; c < cols; c++) {
                if (c > 0) rowChildren.add(const SizedBox(width: 12));
                final idx = i + c;
                rowChildren.add(
                  Expanded(
                    child: idx < displayed.length
                        ? _buildSavedDocCard(
                            displayed[idx],
                            stretchHeight: true,
                          )
                        : const SizedBox.shrink(),
                  ),
                );
              }
              rows.add(
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rowChildren,
                  ),
                ),
              );
              if (i + cols < displayed.length) {
                rows.add(const SizedBox(height: 12));
              }
            }
            return Column(children: rows);
          },
        ),
    ];
  }

  Widget _buildArchiveStatusTab({
    required bool selected,
    required IconData icon,
    required String label,
    required int count,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected
                  ? const Color(0xFF1E3A8A)
                  : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.2,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? const Color(0xFF1E3A8A)
                      : const Color(0xFF64748B),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFDBEAFE)
                    : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? const Color(0xFF1E3A8A)
                      : const Color(0xFF334155),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedDocCard(
    SavedOfficialDocument doc, {
    required bool stretchHeight,
  }) {
    final isBulkDossier =
        doc.templateId == OddkBulkDossierScreen.bundleTemplateId;
    final template = OfficialDocumentCatalog.findById(doc.templateId);
    final category = OfficialDocumentCatalog.safeCategories.firstWhere(
      (c) => c.id == doc.categoryId,
      orElse: () => OfficialDocumentCatalog.safeCategories.first,
    );
    final formattedDate = DateFormat('dd.MM.yyyy HH:mm').format(doc.createdAt);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  doc.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13.8,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _confirmDelete(doc),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: category.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  doc.categoryTitle.isNotEmpty
                      ? doc.categoryTitle
                      : category.title,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: category.color,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: doc.isPassive
                      ? const Color(0xFFF1F5F9)
                      : const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  doc.isPassive ? 'PASİF' : 'AKTİF',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: doc.isPassive
                        ? const Color(0xFF64748B)
                        : const Color(0xFF059669),
                  ),
                ),
              ),
              Text(
                '$formattedDate • ${doc.creatorName}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            doc.composedBody.replaceAll('\n', ' ').trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.8,
              color: Color(0xFF475569),
              height: 1.3,
            ),
          ),
          if (stretchHeight) const Spacer() else const SizedBox(height: 6),
          const Divider(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  onPressed: () => _contextService.setDocumentPassive(
                    widget.institutionId,
                    doc.id,
                    !doc.isPassive,
                  ),
                  icon: Icon(
                    doc.isPassive
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    size: 15,
                    color: const Color(0xFF475569),
                  ),
                  label: Text(
                    doc.isPassive ? 'Aktife Al' : 'Pasife Al',
                    style: const TextStyle(
                      fontSize: 11.8,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isBulkDossier
                        ? const Color(0xFF991B1B)
                        : const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  onPressed: isBulkDossier
                      ? () => _openOddkBulkDossier(existing: doc)
                      : (template == null
                            ? null
                            : () => _openTemplate(
                                template,
                                category,
                                existing: doc,
                              )),
                  icon: Icon(
                    isBulkDossier
                        ? Icons.folder_special_rounded
                        : Icons.open_in_new_rounded,
                    size: 15,
                  ),
                  label: Text(
                    isBulkDossier ? 'Vaka Dosyasını Aç' : 'Aç / PDF Al',
                    style: const TextStyle(
                      fontSize: 11.8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(SavedOfficialDocument doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Evrak Silinsin mi?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Text(
          '"${doc.title}" kaydını silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _contextService.deleteDocument(widget.institutionId, doc.id);
    }
  }
}
