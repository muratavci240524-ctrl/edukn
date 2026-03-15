import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/announcement_service.dart';
import '../../services/user_permission_service.dart';
import '../../services/term_service.dart';
import 'sent_announcements_screen.dart';
import 'announcement_detail_screen.dart';
import 'create_announcement_screen.dart';
import 'announcement_card.dart';

class AnnouncementsScreen extends StatefulWidget {
  static const routeName = '/announcements';
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen>
    with WidgetsBindingObserver {
  final TextEditingController _search = TextEditingController();
  final AnnouncementService _announcementService = AnnouncementService();

  // Filtreler
  DateTimeRange? _range;
  String? _filterType; // 'all', 'unread', 'pinned'

  // Yetkilendirme
  Map<String, dynamic>? userData;
  bool _isLoadingPermissions = true;
  Timer? _scheduledCheckTimer;
  Timer? _termCheckTimer;

  // Dönem
  String? _selectedTermId;
  bool _isViewingPastTerm = false;

  Stream<QuerySnapshot>? _announcementsStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserPermissions();
    _loadSelectedTerm();
    _initAnnouncementsStream();
    _checkScheduledAnnouncements();

    _scheduledCheckTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _checkScheduledAnnouncements(),
    );

    _termCheckTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkTermChange(),
    );
  }

  Future<void> _checkTermChange() async {
    final selectedTermId = await TermService().getSelectedTermId();
    final activeTermId = await TermService().getActiveTermId();
    final effectiveTermId = selectedTermId ?? activeTermId;
    final newIsViewingPastTerm =
        selectedTermId != null && selectedTermId != activeTermId;

    if (mounted &&
        (_selectedTermId != effectiveTermId ||
            _isViewingPastTerm != newIsViewingPastTerm)) {
      setState(() {
        _selectedTermId = effectiveTermId;
        _isViewingPastTerm = newIsViewingPastTerm;
      });
      _initAnnouncementsStream();
    }
  }

  void _initAnnouncementsStream() {
    _announcementsStream = _announcementService.getAnnouncements();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    _scheduledCheckTimer?.cancel();
    _termCheckTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSelectedTerm();
      _initAnnouncementsStream();
    }
  }

  Future<void> _checkScheduledAnnouncements() async {
    try {
      await _announcementService.checkAndPublishScheduledAnnouncements();
    } catch (e) {
      debugPrint('🔔 Zamanlanmış duyuru hatası: $e');
    }
  }

  Future<void> _loadSelectedTerm() async {
    final selectedTermId = await TermService().getSelectedTermId();
    final activeTermId = await TermService().getActiveTermId();
    final effectiveTermId = selectedTermId ?? activeTermId;
    final newIsViewingPastTerm =
        selectedTermId != null && selectedTermId != activeTermId;

    if (mounted &&
        (_selectedTermId != effectiveTermId ||
            _isViewingPastTerm != newIsViewingPastTerm)) {
      setState(() {
        _selectedTermId = effectiveTermId;
        _isViewingPastTerm = newIsViewingPastTerm;
      });
    }
  }

  Future<void> _loadUserPermissions() async {
    final data = await UserPermissionService.loadUserData();
    if (mounted) {
      setState(() {
        userData = data;
        _isLoadingPermissions = false;
      });
    }
  }

  bool _canEditAnnouncements() {
    return UserPermissionService.canEdit('genel_duyurular', userData);
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _range,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _range = picked);
    }
  }

  void _openCreateSheet() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (ctx) => const CreateAnnouncementScreen()),
    );
  }

  Future<void> _markAsRead(String announcementId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final schoolId = await _announcementService.getSchoolId();
      if (schoolId == null) return;

      // Kullanıcı ID'sini bulmak gerekebilir, ancak mevcut implementasyonda email kullanılmışsa email,
      // userId kullanılmışsa userId. Önceki koda bakarsak:
      // 'readBy': FieldValue.arrayUnion([currentUserEmail]) kullanıyordu.
      // Ancak AnnouncementDetailScreen'de userId kullanılıyor olabilir.
      // Eşleşmesi için eski koddaki logic'i koruyalım:
      // Eski kod: .update({'readBy': FieldValue.arrayUnion([currentUserEmail])});
      // Ama wait, AnnouncementService içinde ne var?
      // Biz direkt Firestore update yapıyorduk.

      final currentUserEmail = currentUser.email ?? '';

      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('announcements')
          .doc(announcementId)
          .update({
            'readBy': FieldValue.arrayUnion([currentUserEmail]),
          });
    } catch (e) {
      debugPrint('❌ Okundu hatası: $e');
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _loadSelectedTerm();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Slate 50
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(context),
            _buildFilters(context),

            // Content
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: _buildAnnouncementList(),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton:
          (!_isLoadingPermissions &&
              !_isViewingPastTerm &&
              _canEditAnnouncements())
          ? FloatingActionButton.extended(
              onPressed: _openCreateSheet,
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'Yeni Duyuru',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              elevation: 4,
            )
          : null,
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            color: const Color(0xFF1E293B),
            tooltip: 'Geri',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 16),
          Text(
            'Duyurular',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const Spacer(),
          if (_canEditAnnouncements())
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert_rounded,
                color: Color(0xFF64748B),
              ),
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
                      Icon(Icons.send_rounded, color: Colors.grey),
                      SizedBox(width: 12),
                      Text('Gönderilen Duyurular'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'new',
                  child: Row(
                    children: [
                      Icon(Icons.add_rounded, color: Colors.grey),
                      SizedBox(width: 12),
                      Text('Yeni Duyuru'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        children: [
          // Search Bar
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9), // Slate 100
              borderRadius: BorderRadius.circular(99),
            ),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Duyuru veya anket ara...',
                hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                suffixIcon: _search.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Color(0xFF94A3B8)),
                        onPressed: () => setState(() => _search.clear()),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  'Tümü',
                  _filterType == null,
                  () => setState(() => _filterType = null),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  'Okunmamış',
                  _filterType == 'unread',
                  () => setState(() => _filterType = 'unread'),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  'Sabitlenenler',
                  _filterType == 'pinned',
                  () => setState(() => _filterType = 'pinned'),
                ),
                const SizedBox(width: 8),
                _buildDateFilterChip(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    final primaryColor = Theme.of(context).primaryColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected ? primaryColor : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: isSelected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildDateFilterChip() {
    final isSelected = _range != null;
    final primaryColor = Theme.of(context).primaryColor;

    return InkWell(
      onTap: _pickRange,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected ? primaryColor : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 14,
              color: isSelected ? primaryColor : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              isSelected
                  ? '${_range!.start.day}/${_range!.start.month} - ${_range!.end.day}/${_range!.end.month}'
                  : 'Tarih',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: isSelected ? primaryColor : const Color(0xFF64748B),
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () => setState(() => _range = null),
                child: Icon(Icons.close, size: 14, color: primaryColor),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnnouncementList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _announcementsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Hata oluştu: ${snapshot.error}'));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.campaign_outlined,
                  size: 64,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  'Henüz duyuru bulunmuyor',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }

        final allDocs = snapshot.data!.docs;
        final currentUserEmail = FirebaseAuth.instance.currentUser?.email ?? '';
        final searchText = _search.text.toLowerCase();

        // İstemci tarafı filtreleme ve sıralama
        var filteredDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'] ?? 'published';
          final termId = data['termId'] as String?;
          final title = (data['title'] ?? '').toString().toLowerCase();
          final content = (data['content'] ?? '').toString().toLowerCase();
          final publishDate = data['publishDate'] as Timestamp?;
          final readBy = data['readBy'] as List<dynamic>? ?? [];
          final isRead = readBy.contains(currentUserEmail);
          final isPinned = data['isPinned'] ?? false;

          // 1. Status kontrolü
          if (status != 'published') return false;

          // 2. Dönem kontrolü
          if (_selectedTermId != null &&
              termId != null &&
              termId != _selectedTermId) {
            return false;
          }

          // 3. Arama Metni
          if (searchText.isNotEmpty &&
              !title.contains(searchText) &&
              !content.contains(searchText)) {
            return false;
          }

          // 4. Tarih Aralığı
          if (_range != null && publishDate != null) {
            final date = publishDate.toDate();
            if (date.isBefore(_range!.start) || date.isAfter(_range!.end)) {
              return false;
            }
          }

          // 5. Özel Filtreler (Unread, Pinned)
          if (_filterType == 'unread' && isRead) return false;
          if (_filterType == 'pinned' && !isPinned) return false;

          return true;
        }).toList();

        // Sıralama: Önce Pinned, Sonra Tarih (Yeni en üstte)
        filteredDocs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;

          final aPinned = aData['isPinned'] ?? false;
          final bPinned = bData['isPinned'] ?? false;

          if (aPinned != bPinned) {
            return aPinned ? -1 : 1;
          }

          final aDate = aData['publishDate'] as Timestamp?;
          final bDate = bData['publishDate'] as Timestamp?;

          if (aDate == null) return 1;
          if (bDate == null) return -1;

          return bDate.compareTo(aDate);
        });

        if (filteredDocs.isEmpty) {
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              const SizedBox(height: 64),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      size: 64,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Aradığınız kriterlere uygun duyuru bulunamadı',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 64),
            ],
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
            final isRead = readBy.contains(currentUserEmail);
            final isPinned = data['isPinned'] ?? false;
            final isCreator = createdBy == currentUserEmail;

            // Check for survey link
            final isSurvey = links.any((l) {
              if (l is Map) {
                return (l['url'] ?? '').toString().startsWith(
                  'internal://survey',
                );
              }
              return false;
            });

            return AnnouncementCard(
              doc: doc,
              isCreator: isCreator,
              isRead: isRead,
              isPinned: isPinned,
              isSurvey: isSurvey,
              canEdit: _canEditAnnouncements(),
              onTogglePin: () => _togglePin(doc.id, isPinned),
              onMarkAsRead: () => _markAsRead(doc.id),
              onTap: () async {
                final schoolId = await _announcementService.getSchoolId();
                if (schoolId != null && context.mounted) {
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
            );
          },
        );
      },
    );
  }
}
