import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/announcement_service.dart';
import '../../services/user_permission_service.dart';
import '../announcements/announcement_detail_screen.dart';
import '../announcements/announcement_card.dart';

class TeacherAnnouncementsScreen extends StatefulWidget {
  final String institutionId;

  const TeacherAnnouncementsScreen({
    Key? key,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<TeacherAnnouncementsScreen> createState() =>
      _TeacherAnnouncementsScreenState();
}

class _TeacherAnnouncementsScreenState extends State<TeacherAnnouncementsScreen> {
  final TextEditingController _search = TextEditingController();
  final AnnouncementService _announcementService = AnnouncementService();

  DateTimeRange? _range;
  String? _filterType; // 'unread', 'pinned'
  Map<String, dynamic>? userData;
  bool _isLoadingPermissions = true;
  Timer? _scheduledCheckTimer;
  Set<String> _assignedClassIds = {};
  Set<String> _assignedStudentIds = {};
  bool _isLoadingClasses = true;
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _loadUserPermissions();
    _loadAssignedClasses();
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
      debugPrint('Zamanlanmış duyurular hatası: $e');
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

  Future<void> _loadAssignedClasses() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final instId = widget.institutionId.toUpperCase();

      // 1. Atanmış sınıfları bul
      final snapshot = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: instId)
          .where('teacherIds', arrayContains: user.uid)
          .where('isActive', isEqualTo: true)
          .get();

      final classIds = snapshot.docs
          .map((doc) => doc.data()['classId']?.toString())
          .where((id) => id != null)
          .cast<String>()
          .toSet();

      // 2. Bu sınıflardaki öğrencileri bul
      Set<String> studentIds = {};
      if (classIds.isNotEmpty) {
        final classIdList = classIds.toList();
        for (var i = 0; i < classIdList.length; i += 10) {
          final chunk = classIdList.skip(i).take(10).toList();
          final studentSnap = await FirebaseFirestore.instance
              .collection('students')
              .where('institutionId', isEqualTo: instId)
              .where('classId', whereIn: chunk)
              .get();
          
          for (var doc in studentSnap.docs) {
            studentIds.add(doc.id);
          }
        }
      }

      if (mounted) {
        setState(() {
          _assignedClassIds = classIds;
          _assignedStudentIds = studentIds;
          _isLoadingClasses = false;
        });
      }
    } catch (e) {
      debugPrint('Sınıf yükleme hatası: $e');
      if (mounted) {
        setState(() => _isLoadingClasses = false);
      }
    }
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

  Future<void> _markAsRead(String announcementId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;
      final currentUserEmail = currentUser.email ?? '';
      
      final instId = widget.institutionId.toUpperCase();
      final schoolQuery = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', isEqualTo: instId)
          .limit(1)
          .get();

      if (schoolQuery.docs.isEmpty) return;
      final schoolId = schoolQuery.docs.first.id;

      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('announcements')
          .doc(announcementId)
          .update({
            'readBy': FieldValue.arrayUnion([currentUserEmail]),
          });
    } catch (e) {
      debugPrint('Duyuru okundu hatası: $e');
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
                    'Öğretmen',
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
              actions: [],
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
                    stream: _getTeacherAnnouncements(),
                    builder: (context, snapshot) {
                      if (_isLoadingPermissions) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Hata: ${snapshot.error}'));
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return _buildEmptyState();
                      }

                      final allDocs = snapshot.data!.docs;
                      final currentUserEmail =
                          FirebaseAuth.instance.currentUser?.email ?? '';
                      final searchText = _search.text.toLowerCase();

                      var filteredDocs = allDocs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final status = data['status'] ?? 'published';
                        final title = (data['title'] ?? '').toString().toLowerCase();
                        final content = (data['content'] ?? '').toString().toLowerCase();
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
                        return _buildEmptyState(message: 'Kriterlere uygun duyuru yok');
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: filteredDocs.length,
                        itemBuilder: (context, index) {
                          final doc = filteredDocs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final readBy = data['readBy'] as List<dynamic>? ?? [];
                          final isRead = readBy.contains(currentUserEmail);
                          final isPinned = data['isPinned'] ?? false;
                          
                          return AnnouncementCard(
                            doc: doc,
                            isCreator: false,
                            isRead: isRead,
                            isPinned: isPinned,
                            isSurvey: false,
                            canEdit: false,
                            onTogglePin: () {},
                            onMarkAsRead: () => _markAsRead(doc.id),
                            onTap: () async {
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
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
    );
  }

  Widget _buildEmptyState({String message = 'Henüz duyuru bulunmuyor'}) {
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
                message,
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

  // Header removed

  Widget _buildFilters(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        children: [
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
    const primaryColor = Color(0xFF1976D2);
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
    const primaryColor = Color(0xFF1976D2);
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

  Stream<QuerySnapshot> _getTeacherAnnouncements() {
    if (userData == null || _isLoadingClasses) return const Stream.empty();
    
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final currentUserEmail = FirebaseAuth.instance.currentUser?.email;

    return _announcementService.getAnnouncements().map((snapshot) {
      final List<dynamic> userSchoolTypes = userData!['schoolTypes'] ?? [];
      
      final filteredDocs = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final schoolTypeId = data['schoolTypeId'] as String?;
        final recipients = List<String>.from(data['recipients'] ?? []);
        final publishDate = (data['publishDate'] as Timestamp?)?.toDate();

        // 1. Okul türü kontrolü
        if (schoolTypeId != null && !userSchoolTypes.contains(schoolTypeId)) {
          return false;
        }

        // 2. Alıcı kontrolü
        bool isRecipient = false;

        // - 'ALL' ise herkes görür
        // - 'TEACHER' ise tüm öğretmenler görür
        // - 'unit:ogretmen' ise tüm öğretmenler görür
        if (recipients.contains('ALL') ||
            recipients.contains('TEACHER') ||
            recipients.contains('unit:ogretmen')) {
          isRecipient = true;
        }

        // - Öğretmenin kendi ID'si veya Email'i alıcılarda varsa görür
        if (!isRecipient &&
            ((currentUserId != null && recipients.contains('user:$currentUserId')) ||
                (currentUserEmail != null && recipients.contains(currentUserEmail)))) {
          isRecipient = true;
        }

        // - Okul türü bazlı öğretmenler (Örn: school:XYZ:Öğretmenler)
        if (!isRecipient) {
          for (final stId in userSchoolTypes) {
            if (recipients.contains('school:$stId:Öğretmenler')) {
              isRecipient = true;
              break;
            }
          }
        }

        // - Şube bazlı öğretmenler (Örn: branch:ABC:Öğretmenler)
        if (!isRecipient) {
          for (final classId in _assignedClassIds) {
            if (recipients.contains('branch:$classId:Öğretmenler')) {
              isRecipient = true;
              break;
            }
          }
        }

        // - Öğretmenin dersine girdiği bir sınıf ID'si alıcılarda varsa görür
        // (Eski mantık: raw classId)
        if (!isRecipient) {
          for (final classId in _assignedClassIds) {
            if (recipients.contains(classId)) {
              isRecipient = true;
              break;
            }
          }
        }

        // Öğrenci bazlı kontrol (Tanımlı öğrencilere giden duyuruları öğretmen de görür)
        for (final studentId in _assignedStudentIds) {
          if (recipients.contains(studentId)) {
            isRecipient = true; // If any student is a recipient, the teacher can see it.
            break;
          }
        }

        if (!isRecipient) return false;

        // 3. Tarih Aralığı Filtreleme
        if (_range != null && publishDate != null) {
          if (publishDate.isBefore(_range!.start) ||
              publishDate.isAfter(_range!.end)) {
            return false;
          }
        }

        return true;
      }).toList();

      return _MockQuerySnapshot(filteredDocs);
    });
  }
}

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
