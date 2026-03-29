import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../services/announcement_service.dart';
import '../../../services/user_permission_service.dart';
import '../../announcements/create_announcement_screen.dart';
import '../../announcements/sent_announcements_screen.dart';
import '../../announcements/announcement_detail_screen.dart';
import '../../announcements/announcement_card.dart';

class SchoolTypeAnnouncementsScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const SchoolTypeAnnouncementsScreen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
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

  // Yetkilendirme
  Map<String, dynamic>? userData;
  bool _isLoadingPermissions = true;
  Timer? _scheduledCheckTimer;
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _loadUserPermissions();
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

  Future<void> _checkScheduledAnnouncements() async {
    try {
      await _announcementService.checkAndPublishScheduledAnnouncements();
    } catch (e) {
      debugPrint('🔔 Zamanlanmış duyurular hatası: $e');
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
    if (userData == null) return true;
    final schoolTypePerms =
        userData!['schoolTypePermissions'] as Map<String, dynamic>?;
    if (schoolTypePerms == null) return false;
    final permission = schoolTypePerms[widget.schoolTypeId];
    return permission == 'editor';
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
      MaterialPageRoute(
        builder: (ctx) => CreateAnnouncementScreen(
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.indigo,
              elevation: 0,
              automaticallyImplyLeading: false,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.schoolTypeName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Duyurular',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              actions: [
                if (_canEditAnnouncements())
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
            SliverAppBar(
              floating: true,
              pinned: false,
              snap: true,
              backgroundColor: Colors.white,
              elevation: 2,
              automaticallyImplyLeading: false,
              toolbarHeight: _showFilters ? 124 : 68,
              flexibleSpace: FlexibleSpaceBar(
                background: _buildFilters(context),
              ),
            ),
          ],
          body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _getSchoolTypeAnnouncements(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(child: Text('Hata: ${snapshot.error}'));
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            const SizedBox(height: 64),
                            Center(
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
                            ),
                          ],
                        );
                      }

                      final allDocs = snapshot.data!.docs;
                      final currentUserEmail =
                          FirebaseAuth.instance.currentUser?.email ?? '';
                      final searchText = _search.text.toLowerCase();

                      // Filter
                      var filteredDocs = allDocs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final status = data['status'] ?? 'published';
                        final title = (data['title'] ?? '')
                            .toString()
                            .toLowerCase();
                        final content = (data['content'] ?? '')
                            .toString()
                            .toLowerCase();
                        final publishDate = data['publishDate'] as Timestamp?;
                        final readBy = data['readBy'] as List<dynamic>? ?? [];
                        final isRead = readBy.contains(currentUserEmail);
                        final isPinned = data['isPinned'] ?? false;

                        if (status != 'published') return false;

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

                        if (_filterType == 'unread' && isRead) return false;
                        if (_filterType == 'pinned' && !isPinned) return false;

                        return true;
                      }).toList();

                      // Sort
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
                        return ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            const SizedBox(height: 64),
                            Center(
                              child: Text(
                                'Kriterlere uygun duyuru yok',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
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
                              final schoolId = await _announcementService
                                  .getSchoolId();
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
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
      floatingActionButton: MediaQuery.of(context).size.width > 700 && !_isLoadingPermissions && _canEditAnnouncements()
          ? FloatingActionButton.extended(
              onPressed: _openCreateSheet,
              backgroundColor: const Color(0xFF1976D2), // Strong Blue
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


  Widget _buildFilters(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        children: [
          // Search Bar
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
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 40,
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
                    fillColor: Colors.white,
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
                        color: Colors.blue,
                        width: 1.5,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(
                        color: Color(0xFFE2E8F0),
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Filter Toggle Button
              Material(
                color: _showFilters
                    ? Colors.indigo.withOpacity(0.1)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => setState(() => _showFilters = !_showFilters),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _showFilters ? Colors.indigo : Colors.transparent,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      color: _showFilters ? Colors.indigo : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_showFilters) ...[
            const SizedBox(height: 12),
            // Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
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
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    const primaryColor = Color(0xFF1976D2); // Strong Blue
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
    const primaryColor = Color(0xFF1976D2); // Strong Blue
    return InkWell(
      onTap: _pickRange,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(20),
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

  // Okul türü bazlı duyuruları getir
  Stream<QuerySnapshot> _getSchoolTypeAnnouncements() {
    return _announcementService.getAnnouncements().map((snapshot) {
      // Okul türü ID'sine göre filtrele
      final filteredDocs = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final schoolTypeId = data['schoolTypeId'] as String?;
        return schoolTypeId == widget.schoolTypeId;
      }).toList();

      // Yeni bir QuerySnapshot oluştur (mock)
      return _MockQuerySnapshot(filteredDocs);
    });
  }
}

// Mock Classes
class _MockQuerySnapshot implements QuerySnapshot {
  final List<QueryDocumentSnapshot> _docs;
  _MockQuerySnapshot(this._docs);
  @override
  List<QueryDocumentSnapshot> get docs => _docs;
  @override
  List<DocumentChange> get docChanges => [];
  @override
  SnapshotMetadata get metadata => _MockSnapshotMetadata();
  @override
  int get size => _docs.length;
}

class _MockSnapshotMetadata implements SnapshotMetadata {
  @override
  bool get hasPendingWrites => false;
  @override
  bool get isFromCache => false;
}
