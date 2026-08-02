import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:edukn/widgets/custom_date_range_picker.dart';
import '../../../services/announcement_service.dart';
import '../../../services/user_permission_service.dart';
import '../../../services/term_service.dart';
import '../../announcements/create_announcement_screen_v2.dart';
import '../../announcements/sent_announcements_screen.dart';
import '../../announcements/announcement_detail_screen.dart';
import '../../announcements/announcement_card.dart';

class SchoolTypeAnnouncementsScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const SchoolTypeAnnouncementsScreen({
    Key? key,
    this.schoolTypeId = '',
    this.schoolTypeName = '',
    this.institutionId = '',
  }) : super(key: key);

  @override
  State<SchoolTypeAnnouncementsScreen> createState() =>
      _SchoolTypeAnnouncementsScreenState();
}

class _SchoolTypeAnnouncementsScreenState
    extends State<SchoolTypeAnnouncementsScreen> {
  final TextEditingController _search = TextEditingController();
  final AnnouncementService _announcementService = AnnouncementService();

  // Filtreler
  DateTimeRange? _range;
  String? _filterType; // 'unread', 'pinned'

  // Yetkilendirme ve Durum
  Map<String, dynamic>? userData;
  bool _isLoadingPermissions = true;
  Timer? _scheduledCheckTimer;

  List<Map<String, dynamic>> _schoolTypes = [];
  String _selectedFilterSchoolTypeId = 'GENEL'; // Varsayılan: Genel duyurular
  String? _resolvedInstitutionId;
  String? _activeTermId;

  // Yeni / Geçmiş toggle
  String _viewMode = 'new'; // 'new' = okunmamış, 'past' = okunmuş
  final Set<String> _sessionUnreadDocIds = {};

  // Rol bazlı filtreleme
  String _userRole = '';
  String _userEmail = '';
  List<String> _userClassIds = [];

  @override
  void initState() {
    super.initState();
    _initData();
    _checkScheduledAnnouncements();
    _scheduledCheckTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _checkScheduledAnnouncements(),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    _scheduledCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _initData() async {
    _resolvedInstitutionId = widget.institutionId;
    if (_resolvedInstitutionId == null || _resolvedInstitutionId!.isEmpty) {
      final userData = await UserPermissionService.loadUserData();
      final user = FirebaseAuth.instance.currentUser;
      _resolvedInstitutionId = await UserPermissionService.resolveInstitutionId(user?.email ?? '', userData: userData);
    }

    final activeTermId = await TermService().getSelectedTermId() ?? await TermService().getActiveTermId();
    if (mounted) {
      setState(() {
        _activeTermId = activeTermId;
      });
    }

    if (widget.schoolTypeId.isEmpty) {
      _loadSchoolTypes();
    } else {
      _selectedFilterSchoolTypeId = widget.schoolTypeId;
    }
    _loadUserPermissions();
  }

  Future<void> _loadSchoolTypes() async {
    try {
      if (_resolvedInstitutionId == null || _resolvedInstitutionId!.isEmpty) return;
      final snapshot = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .where('institutionId', isEqualTo: _resolvedInstitutionId)
          .get();

      final data = await UserPermissionService.loadUserData();
      final userSchoolTypeId = data?['schoolTypeId']?.toString();
      final userSchoolTypeIds = List<String>.from(data?['schoolTypeIds'] ?? []);
      final role = (data?['role'] ?? '').toString().toLowerCase();
      final type = (data?['type'] ?? '').toString().toLowerCase();

      final isGlobalAdmin = role == 'admin' || role == 'manager' || role == 'genel_mudur' || type == 'admin';

      List<Map<String, dynamic>> loadedTypes = [];

      for (var d in snapshot.docs) {
        final stId = d.id;
        final stName = d.data()['name'] ?? d.data()['schoolTypeName'] ?? d.data()['typeName'] ?? d.data()['schoolName'] ?? 'Bilinmeyen Okul Türü';

        if (!isGlobalAdmin) {
          bool hasAccess = false;
          if (userSchoolTypeId != null && userSchoolTypeId == stId) hasAccess = true;
          if (userSchoolTypeIds.contains(stId)) hasAccess = true;
          final schoolTypePerms = data?['schoolTypePermissions'] as Map<String, dynamic>?;
          if (schoolTypePerms != null && schoolTypePerms.containsKey(stId)) hasAccess = true;

          if (!hasAccess) continue; // Skip school types the user is not assigned to
        }

        loadedTypes.add({'id': stId, 'name': stName});
      }

      if (mounted) {
        final isTeacher = role.contains('ogretmen') || role.contains('öğretmen') || role.contains('teacher');
        setState(() {
          _schoolTypes = loadedTypes;
          if (widget.schoolTypeId.isEmpty) {
            if (isTeacher && loadedTypes.isNotEmpty) {
              _selectedFilterSchoolTypeId = loadedTypes.first['id'];
            } else if (!isGlobalAdmin && loadedTypes.length == 1) {
              _selectedFilterSchoolTypeId = loadedTypes.first['id'];
            }
          }
        });
      }
    } catch (e) {
      debugPrint("School Types load error: $e");
    }
  }

  Future<void> _checkScheduledAnnouncements() async {
    try {
      if (!_canEditAnnouncements()) return;
      await _announcementService.checkAndPublishScheduledAnnouncements();
    } catch (e) {
      debugPrint('🔔 Zamanlanmış duyurular hatası: $e');
    }
  }

  Future<void> _loadUserPermissions() async {
    final data = await UserPermissionService.loadUserData();
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final role = (data?['role'] ?? '').toString().toLowerCase();

    List<String> classIds = [];
    if (role == 'ogretmen' || role == 'öğretmen' || role == 'teacher') {
      try {
        final instId = _resolvedInstitutionId ?? data?['institutionId']?.toString();
        if (instId != null && instId.isNotEmpty && email.isNotEmpty) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          final ids = <String>{};

          if (uid != null) {
            final scheduleSnap = await FirebaseFirestore.instance
                .collection('classSchedules')
                .where('institutionId', isEqualTo: instId)
                .where('teacherIds', arrayContains: uid)
                .get();
            for (final doc in scheduleSnap.docs) {
              final cid = doc.data()['classId']?.toString();
              if (cid != null && cid.isNotEmpty) ids.add(cid);
            }
          }

          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: email)
              .where('institutionId', isEqualTo: instId)
              .limit(1)
              .get();
          if (userDoc.docs.isNotEmpty) {
            final assignedIds = userDoc.docs.first.data()['assignedClassIds'];
            if (assignedIds is List) {
              for (final id in assignedIds) {
                if (id != null) ids.add(id.toString());
              }
            }
          }
          
          if (uid != null) {
            final assignSnap = await FirebaseFirestore.instance
                .collection('lessonAssignments')
                .where('institutionId', isEqualTo: instId)
                .where('teacherIds', arrayContains: uid)
                .where('isActive', isEqualTo: true)
                .get();
            for (final doc in assignSnap.docs) {
              final cid = doc.data()['classId']?.toString();
              if (cid != null && cid.isNotEmpty) ids.add(cid);
            }
          }

          classIds = ids.toList();
        }
      } catch (e) {
        debugPrint('Öğretmen sınıf ID yükleme hatası: $e');
      }
    }

    if (mounted) {
      setState(() {
        userData = data;
        _userRole = role;
        _userEmail = email;
        _userClassIds = classIds;
        _isLoadingPermissions = false;
      });
    }
  }

  bool _canEditAnnouncements() {
    if (userData == null) return true;
    final role = (_userRole).toLowerCase();
    if (role == 'admin' || role == 'manager' || role == 'genel_mudur') {
      return true;
    }
    if (widget.schoolTypeId.isEmpty) {
      return UserPermissionService.canEditSubModule('haberlesme', 'genel_duyurular', userData);
    }
    final schoolTypePerms =
        userData!['schoolTypePermissions'] as Map<String, dynamic>?;
    if (schoolTypePerms == null) return false;
    final permission = schoolTypePerms[widget.schoolTypeId];
    return permission == 'editor';
  }

  Future<void> _pickRange() async {
    final picked = await CustomDateRangePicker.show(
      context,
      initialRange: _range,
    );
    if (picked != null) {
      setState(() => _range = picked);
    }
  }

  void _openCreateSheet() {
    final activeSchoolTypeId = widget.schoolTypeId.isNotEmpty
        ? widget.schoolTypeId
        : (_selectedFilterSchoolTypeId == 'GENEL' ? '' : _selectedFilterSchoolTypeId);

    String activeSchoolTypeName = widget.schoolTypeName;
    if (activeSchoolTypeName.isEmpty && activeSchoolTypeId.isNotEmpty) {
      final found = _schoolTypes.firstWhere(
        (st) => st['id'] == activeSchoolTypeId,
        orElse: () => {'name': ''},
      );
      activeSchoolTypeName = (found['name'] ?? '').toString();
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => CreateAnnouncementScreenV2(
          schoolTypeId: activeSchoolTypeId,
          schoolTypeName: activeSchoolTypeName,
        ),
      ),
    );
  }

  Future<void> _openTeacherModeSettingsDialog() async {
    final schoolId = await _announcementService.getSchoolId();
    if (schoolId == null) return;
    String currentMode = await _announcementService.getTeacherAnnouncementMode(schoolId);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.settings_suggest_rounded, color: Colors.indigo),
              const SizedBox(width: 8),
              Text('Öğretmen Duyuru Ayarı', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Öğretmenlerin duyuru oluşturma izinlerini ve onay sürecini belirleyin:'),
              const SizedBox(height: 12),
              RadioListTile<String>(
                title: const Text('Yönetim Onayına Düşsün'),
                subtitle: const Text('Öğretmen duyuru yapar, yönetici onaylayınca yayınlanır.'),
                value: 'approval_required',
                groupValue: currentMode,
                onChanged: (val) => setDialogState(() => currentMode = val!),
              ),
              RadioListTile<String>(
                title: const Text('Doğrudan Yayınlansın'),
                subtitle: const Text('Öğretmenin yaptığı duyuru onay gerekmeden yayınlanır.'),
                value: 'direct',
                groupValue: currentMode,
                onChanged: (val) => setDialogState(() => currentMode = val!),
              ),
              RadioListTile<String>(
                title: const Text('Öğretmen Duyuru Yapamasın'),
                subtitle: const Text('Öğretmen modülünde duyuru oluşturma kapalıdır.'),
                value: 'disabled',
                groupValue: currentMode,
                onChanged: (val) => setDialogState(() => currentMode = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _announcementService.setTeacherAnnouncementMode(schoolId, currentMode);
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Öğretmen duyuru yetki ayarı kaydedildi.')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markAsRead(String announcementId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final currentUserEmail = currentUser.email ?? '';
      final schoolId = await _announcementService.getSchoolId();
      if (schoolId == null) return;

      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('announcements')
          .doc(announcementId)
          .update({
            'readBy': FieldValue.arrayUnion([currentUserEmail]),
          });
    } catch (e) {
      debugPrint('❌ Duyuru okundu hatası: $e');
    }
  }

  Future<void> _togglePin(String docId, bool currentStatus) async {
    if (!_canEditAnnouncements()) return;
    try {
      if (currentStatus) {
        await _announcementService.unpinAnnouncement(docId);
      } else {
        await _announcementService.pinAnnouncement(docId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  String? get _activeViewSchoolTypeId {
    if (widget.schoolTypeId.isNotEmpty) return widget.schoolTypeId;
    if (_selectedFilterSchoolTypeId == 'GENEL') return null;
    return _selectedFilterSchoolTypeId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.schoolTypeName.isNotEmpty
                      ? widget.schoolTypeName
                      : (_selectedFilterSchoolTypeId == 'GENEL'
                          ? 'Tüm Okul Türleri'
                          : (_schoolTypes.firstWhere((st) => st['id'] == _selectedFilterSchoolTypeId, orElse: () => {'name': 'Duyurular'})['name'])),
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Duyurular',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_canEditAnnouncements())
            IconButton(
              icon: const Icon(Icons.settings_rounded, color: Colors.white),
              tooltip: 'Öğretmen Duyuru Ayarı',
              onPressed: _openTeacherModeSettingsDialog,
            ),
          if (_canEditAnnouncements() || _isTeacherRole)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (value) {
                if (value == 'sent') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => const SentAnnouncementsScreen(),
                    ),
                  );
                } else if (value == 'new') {
                  _openCreateSheet();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'sent',
                  child: Row(
                    children: [
                      Icon(Icons.outbox_rounded, color: Colors.indigo, size: 20),
                      SizedBox(width: 12),
                      Text('Gönderilenler'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'new',
                  child: Row(
                    children: [
                      Icon(Icons.add_rounded, color: Colors.indigo, size: 20),
                      SizedBox(width: 12),
                      Text('Yeni Duyuru'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Filtreler Üst Alanı
            _buildHeaderFilters(context),

            // Tab Toggle: Yeni Duyurular / Geçmiş Duyurular
            _buildViewModeToggle(),

            // Duyuru Listesi
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                    stream: _announcementService.getAnnouncements(),
                    builder: (context, snapshot) {
                      if (_isLoadingPermissions || snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(child: Text('Hata: ${snapshot.error}'));
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return _buildEmptyState(
                          'Henüz bir duyuru paylaşılmamış',
                          'Aktif döneme ait yayınlanmış herhangi bir duyuru bulunmuyor.',
                        );
                      }

                      final allDocs = snapshot.data!.docs;
                      final currentUserEmail = _userEmail.isNotEmpty
                          ? _userEmail
                          : FirebaseAuth.instance.currentUser?.email ?? '';
                      final searchText = _search.text.toLowerCase();
                      final viewingSchoolTypeId = _activeViewSchoolTypeId;

                      final effectiveRole = _userRole.isNotEmpty ? _userRole : 'admin';

                      final currentUserUid = FirebaseAuth.instance.currentUser?.uid ?? '';

                      // ─── Rol & Okul Türü Filtrelemesi ───
                      var rolFiltered = AnnouncementService.filterAnnouncementsForUser(
                        docs: allDocs,
                        userRole: effectiveRole,
                        userEmail: currentUserEmail,
                        userClassIds: _userClassIds,
                        viewingSchoolTypeId: viewingSchoolTypeId,
                        isGeneralView: _selectedFilterSchoolTypeId == 'GENEL' && widget.schoolTypeId.isEmpty,
                        userId: currentUserUid,
                      );

                      // ─── Oturum Açılışındaki Okunmamış Dokümanları Kaydet ───
                      for (final doc in rolFiltered) {
                        final data = doc.data() as Map<String, dynamic>;
                        final readBy = data['readBy'] as List<dynamic>? ?? [];
                        final isRead = readBy.contains(currentUserEmail) || readBy.contains(currentUserUid);
                        if (!isRead) {
                          _sessionUnreadDocIds.add(doc.id);
                        }
                      }

                      // ─── Zaman, Arama Metni, Dönem & Sekme (Yeni/Geçmiş) Filtresi ───
                      var filteredDocs = rolFiltered.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final status = data['status'] ?? 'published';
                        final title = (data['title'] ?? '').toString().toLowerCase();
                        final content = (data['content'] ?? '').toString().toLowerCase();
                        final publishDate = data['publishDate'] as Timestamp?;
                        final readBy = data['readBy'] as List<dynamic>? ?? [];
                        final isRead = readBy.contains(currentUserEmail) || readBy.contains(currentUserUid);
                        final isPinned = data['isPinned'] ?? false;
                        final wasUnreadAtStart = _sessionUnreadDocIds.contains(doc.id);

                        final docCreatedBy = (data['createdBy'] ?? '').toString();
                        final isCreator = docCreatedBy.isNotEmpty && docCreatedBy == currentUserEmail;

                        if (status != 'published') {
                          if (status == 'pending_approval' && (_canEditAnnouncements() || isCreator)) {
                            // Onay bekleyen duyuruyu yöneticiye veya oluşturan öğretmene göster
                          } else {
                            return false;
                          }
                        }

                        if (publishDate != null &&
                            publishDate.toDate().isAfter(DateTime.now())) {
                          return false;
                        }

                        if (searchText.isNotEmpty &&
                            !title.contains(searchText) &&
                            !content.contains(searchText)) {
                          return false;
                        }

                        if (_range != null && publishDate != null) {
                          final date = publishDate.toDate();
                          if (date.isBefore(_range!.start) ||
                              date.isAfter(_range!.end)) {
                            return false;
                          }
                        }

                        // Sekme filtrelemesi:
                        if (_viewMode == 'past' && !isRead) return false;
                        if (_viewMode == 'new' && isRead && !isPinned) return false;

                        if (_filterType == 'pinned' && !isPinned) return false;

                        return true;
                      }).toList();

                      // Sıralama
                      filteredDocs.sort((a, b) {
                        final aData = a.data() as Map<String, dynamic>;
                        final aPinned = aData['isPinned'] ?? false;
                        final bData = b.data() as Map<String, dynamic>;
                        final bPinned = bData['isPinned'] ?? false;

                        if (aPinned != bPinned) return aPinned ? -1 : 1;

                        final aDate = aData['publishDate'] as Timestamp?;
                        final bDate = bData['publishDate'] as Timestamp?;
                        if (aDate == null) return 1;
                        if (bDate == null) return -1;
                        return bDate.compareTo(aDate);
                      });

                      if (filteredDocs.isEmpty) {
                        return _buildEmptyState(
                          _viewMode == 'new'
                              ? 'Henüz duyuru yok'
                              : 'Okunmuş geçmiş duyuru bulunmuyor',
                          _viewMode == 'new'
                              ? 'Yeni bir duyuru yayınlandığında veya geldiğinde burada görünecektir.'
                              : 'Okuduğunuz tüm duyurular geçmiş sekmesinde listelenmektedir.',
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: filteredDocs.length,
                        itemBuilder: (context, index) {
                          final doc = filteredDocs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final createdBy = data['createdBy'] ?? '';
                          final readBy = data['readBy'] as List<dynamic>? ?? [];
                          final links = data['links'] as List<dynamic>? ?? [];
                          final isRead = readBy.contains(currentUserEmail) || readBy.contains(currentUserUid);
                          final isPinned = data['isPinned'] ?? false;
                          final isCreator = createdBy == currentUserEmail || (createdBy.isNotEmpty && createdBy.split('@')[0] == currentUserEmail.split('@')[0]);
                          final isPending = data['status'] == 'pending_approval';

                          final isSurvey = links.any((l) {
                            if (l is Map) {
                              return (l['url'] ?? '').toString().startsWith(
                                'internal://survey',
                              );
                            }
                            return false;
                          });

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnnouncementCard(
                                doc: doc,
                                isCreator: isCreator,
                                isRead: isRead,
                                isPinned: isPinned,
                                isSurvey: isSurvey,
                                canEdit: _canEditAnnouncements(),
                                isPendingApproval: isPending,
                                onApprove: () async {
                                  final sId = await _announcementService.getSchoolId();
                                  if (sId != null) {
                                    await _announcementService.approveAnnouncement(doc.id, sId, currentUserEmail);
                                    if (mounted) {
                                      setState(() {});
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Duyuru onaylandı ve yayınlandı!')),
                                      );
                                    }
                                  }
                                },
                                onReject: () async {
                                  final sId = await _announcementService.getSchoolId();
                                  if (sId != null) {
                                    await _announcementService.rejectAnnouncement(doc.id, sId, currentUserEmail);
                                    if (mounted) {
                                      setState(() {});
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Duyuru reddedildi.')),
                                      );
                                    }
                                  }
                                },
                                onTogglePin: () => _togglePin(doc.id, isPinned),
                                onMarkAsRead: () => _markAsRead(doc.id),
                                onTap: () async {
                                  if (!isRead) {
                                    _markAsRead(doc.id);
                                  }
                                  
                                  if (!_canEditAnnouncements()) {
                                    return; // Sadece yetkililer detay (okuyanlar) ekranına gidebilir
                                  }
                                  
                                  final schoolId = await _announcementService.getSchoolId();
                                  if (schoolId != null && mounted) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (ctx) => AnnouncementDetailScreen(
                                          announcementId: doc.id,
                                          schoolId: schoolId,
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                              if (!isRead)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16, left: 12, right: 12),
                                  child: GestureDetector(
                                    onTap: () => _markAsRead(doc.id),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF0F7FF),
                                        borderRadius: const BorderRadius.only(
                                          bottomLeft: Radius.circular(14),
                                          bottomRight: Radius.circular(14),
                                        ),
                                        border: Border.all(color: const Color(0xFFBFDBFE), width: 1.2),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.check_circle_outline_rounded,
                                            size: 16,
                                            color: Color(0xFF1976D2),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Okundu olarak işaretle → Geçmişe at',
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF1976D2),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 12),
                            ],
                          );
                        },
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
      floatingActionButton: !_isLoadingPermissions && (_canEditAnnouncements() || _isTeacherRole)
          ? FloatingActionButton.extended(
              onPressed: _openCreateSheet,
              backgroundColor: const Color(0xFF1976D2),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'Yeni Duyuru',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            )
          : null,
    );
  }

  bool get _isTeacherRole {
    final role = _userRole.toLowerCase();
    return role.contains('ogretmen') || role.contains('öğretmen') || role.contains('teacher');
  }

  bool get _shouldShowSchoolTypeFilter {
    if (widget.schoolTypeId.isNotEmpty) return false;
    if (_isTeacherRole) {
      // Öğretmen ise: sadece birden fazla okul türünde görevli ise filtre gösterilir
      return _schoolTypes.length > 1;
    }
    return _schoolTypes.isNotEmpty;
  }

  Widget _buildHeaderFilters(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          // Arama & Takvim Satırı
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  textAlignVertical: TextAlignVertical.center,
                  style: GoogleFonts.inter(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Duyuru ara...',
                    hintStyle: GoogleFonts.inter(
                      color: const Color(0xFF94A3B8),
                      fontSize: 14,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF94A3B8),
                      size: 20,
                    ),
                    suffixIcon: _search.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear_rounded,
                              size: 18,
                              color: Color(0xFF94A3B8),
                            ),
                            onPressed: () => setState(() => _search.clear()),
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(
                        color: Color(0xFFE2E8F0),
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(
                        color: Colors.indigo,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Takvim Butonu
              Material(
                color: _range != null ? Colors.indigo.withOpacity(0.1) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _pickRange,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _range != null ? Colors.indigo : Colors.transparent,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.date_range_rounded,
                          color: _range != null ? Colors.indigo : const Color(0xFF64748B),
                        ),
                        if (_range != null) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setState(() => _range = null),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Colors.indigo,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Okul Türü Dropdown Pill Selector
          if (_shouldShowSchoolTypeFilter)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedFilterSchoolTypeId == 'GENEL' && _isTeacherRole && _schoolTypes.isNotEmpty
                      ? _schoolTypes.first['id']
                      : _selectedFilterSchoolTypeId,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.indigo),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.indigo.shade900,
                  ),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedFilterSchoolTypeId = val;
                      });
                    }
                  },
                  items: [
                    if (!_isTeacherRole)
                      DropdownMenuItem(
                        value: 'GENEL',
                        child: Row(
                          children: [
                            const Icon(Icons.school_rounded, size: 18, color: Colors.indigo),
                            const SizedBox(width: 10),
                            Text(
                              'Genel Duyurular',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ..._schoolTypes.map((st) {
                      return DropdownMenuItem<String>(
                        value: st['id'] as String,
                        child: Row(
                          children: [
                            const Icon(Icons.apartment_rounded, size: 18, color: Color(0xFF64748B)),
                            const SizedBox(width: 10),
                            Text(st['name'] ?? 'Okul Türü'),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildViewModeToggle() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _viewMode = 'new'),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _viewMode == 'new' ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: _viewMode == 'new'
                        ? [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : [],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.mark_email_unread_rounded,
                        size: 18,
                        color: _viewMode == 'new' ? Colors.indigo : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Yeni Duyurular',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _viewMode == 'new' ? Colors.indigo : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _viewMode = 'past'),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _viewMode == 'past' ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: _viewMode == 'past'
                        ? [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : [],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.done_all_rounded,
                        size: 18,
                        color: _viewMode == 'past' ? Colors.indigo : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Geçmiş Duyurular',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _viewMode == 'past' ? Colors.indigo : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      children: [
        Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.indigo.shade50, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.indigo.shade900.withOpacity(0.04),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.campaign_outlined,
                    size: 40,
                    color: Colors.indigo.shade400,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF64748B),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
