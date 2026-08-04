import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'create_social_media_post_screen.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'dart:math' as math;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import '../../../services/announcement_service.dart';
import '../../../services/user_permission_service.dart';
import '../../../services/term_service.dart';
import 'package:url_launcher/url_launcher.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui;

class SchoolTypeSocialMediaScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const SchoolTypeSocialMediaScreen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<SchoolTypeSocialMediaScreen> createState() =>
      _SchoolTypeSocialMediaScreenState();
}

class _SchoolTypeSocialMediaScreenState
    extends State<SchoolTypeSocialMediaScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // --- Filter & Categorization State ---
  List<Map<String, dynamic>> _schoolTypes = [];
  String _selectedFilterSchoolTypeId = 'GENEL'; // Varsayılan: Genel Paylaşımlar
  bool _isTeacher = false;
  bool _isLoadingSchoolTypes = true;

  // Oturum süresince Yeni sekmesindeki gönderilerin aniden kaybolmasını engellemek için saklanan liste
  final Set<String> _sessionUnreadDocIds = {};

  // --- View Mode State ('new' = Okunmayanlar / Yeni, 'past' = Okunanlar / Geçmiş) ---
  String _viewMode = 'new';

  @override
  void initState() {
    super.initState();
    if (widget.schoolTypeId.isEmpty) {
      _isLoadingSchoolTypes = true;
      _loadSchoolTypes();
    } else {
      _selectedFilterSchoolTypeId = widget.schoolTypeId;
      _isLoadingSchoolTypes = false;
    }
  }

  Future<void> _loadSchoolTypes() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final data = await UserPermissionService.loadUserData();
      final userSchoolTypeId = data?['schoolTypeId']?.toString();
      final userSchoolTypeIds = List<String>.from(data?['schoolTypeIds'] ?? []);
      final role = (data?['role'] ?? '').toString().toLowerCase();
      final type = (data?['type'] ?? '').toString().toLowerCase();

      final isTeacher = role.contains('ogretmen') || role.contains('öğretmen') || role.contains('teacher');
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
        setState(() {
          _isTeacher = isTeacher;
          _schoolTypes = loadedTypes;
          _isLoadingSchoolTypes = false;
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
      if (mounted) {
        setState(() {
          _isLoadingSchoolTypes = false;
        });
      }
    }
  }

  void _openCreatePost() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateSocialMediaPostScreen(
          schoolTypeId: widget.schoolTypeId.isNotEmpty
              ? widget.schoolTypeId
              : (_selectedFilterSchoolTypeId == 'GENEL' ? '' : _selectedFilterSchoolTypeId),
          schoolTypeName: widget.schoolTypeName.isNotEmpty
              ? widget.schoolTypeName
              : (_getSchoolTypeName(_selectedFilterSchoolTypeId)),
          institutionId: widget.institutionId,
        ),
      ),
    );
  }

  String _getSchoolTypeName(String? typeId) {
    if (typeId == null || typeId.isEmpty || typeId == 'GENEL') return 'Genel Paylaşımlar';
    final found = _schoolTypes.firstWhere(
      (st) => st['id'] == typeId,
      orElse: () => {'name': 'Genel Paylaşımlar'},
    );
    return found['name'] ?? 'Genel Paylaşımlar';
  }

  /// Okul Türü ve Alıcı Listesine göre paylaşımları kategorize etme kuralı:
  /// 1. Tek bir okul türüne yapıldıysa -> Sadece o okul türünde çıkar, GENEL'de görünmez.
  /// 2. Birden fazla okul türüne yapıldıysa -> GENEL'de ve ilgili okul türlerinde çıkar.
  /// 3. Okul türünden bağımsız (Birim/Tüm Kurum) yapıldıysa -> GENEL'de çıkar, okul türlerinde görünmez.
  bool _isPostVisibleForFilter(Map<String, dynamic> data, String filterId) {
    final postSchoolTypeId = (data['schoolTypeId'] ?? '').toString();
    final recipients = List<String>.from(data['recipients'] ?? []);

    final Set<String> targetedSchoolTypeIds = {};
    bool hasNonSchoolUnit = false;

    // 1. Dokümandaki birincil okul türünü ekle
    if (postSchoolTypeId.isNotEmpty && postSchoolTypeId != 'GENEL') {
      targetedSchoolTypeIds.add(postSchoolTypeId);
    }

    // 2. Alıcı gruplarındaki okul türlerini veya bağımsız birimleri çözümle
    for (final r in recipients) {
      if (r.startsWith('school:')) {
        final id = r.substring('school:'.length);
        if (id.isNotEmpty && id != '*') targetedSchoolTypeIds.add(id);
      } else if (r.startsWith('class:')) {
        final body = r.substring('class:'.length);
        final parts = body.split('_');
        if (parts.isNotEmpty && parts[0].isNotEmpty) {
          targetedSchoolTypeIds.add(parts[0]);
        }
      } else if (r.startsWith('branch:')) {
        final body = r.substring('branch:'.length);
        final parts = body.split('_');
        if (parts.isNotEmpty && parts[0].isNotEmpty) {
          targetedSchoolTypeIds.add(parts[0]);
        }
      } else if (r.startsWith('unit:')) {
        hasNonSchoolUnit = true;
      }
    }

    // 3. Kategorizasyon Durumları
    final bool isSingleSchoolType =
        targetedSchoolTypeIds.length == 1 && !hasNonSchoolUnit;

    final bool isMultipleSchoolTypes = targetedSchoolTypeIds.length > 1;

    final bool isGeneralOrInstitutionWide =
        (postSchoolTypeId.isEmpty || postSchoolTypeId == 'GENEL') &&
        targetedSchoolTypeIds.isEmpty;

    // 4. Aktif Filtreye Göre Kontrol
    if (filterId == 'GENEL' || filterId.isEmpty) {
      // Tek bir okul türüne özel yapılmış gönderiler Genel'de HİÇBİR ŞEKİLDE ÇIKMAZ!
      if (isSingleSchoolType) return false;
      // Birden fazla okul türüne, bağımsız birime veya genel kuruma yapılanlar Genel'de ÇIKAR.
      return isMultipleSchoolTypes || isGeneralOrInstitutionWide || hasNonSchoolUnit;
    } else {
      // Belirli bir okul türü seçildiyse (ör. ABC Ortaokulu): Sadece o okul türünün ID'sini barındıranlar ÇIKAR.
      return targetedSchoolTypeIds.contains(filterId);
    }
  }

  bool get _shouldShowSchoolTypeFilter {
    if (widget.schoolTypeId.isNotEmpty) return false;
    if (_isLoadingSchoolTypes) return false;
    if (_isTeacher) {
      return _schoolTypes.length > 1;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserEmail = _auth.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            // Standardized AppBar matching announcement screen typography & back button
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.indigo,
              elevation: 0,
              automaticallyImplyLeading: false,
              title: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
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
                            : (_getSchoolTypeName(_selectedFilterSchoolTypeId)),
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Sosyal Medya & Paylaşımlar',
                        style: GoogleFonts.inter(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: const [], // Mükerrer butonu kaldırıldı - FAB kullanılmaktadır
            ),

            // Header section: School Type Categorization Dropdown + Read/Past View Mode Switcher
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                minHeight: _shouldShowSchoolTypeFilter ? 115.0 : 65.0,
                maxHeight: _shouldShowSchoolTypeFilter ? 115.0 : 65.0,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // School Type Filter Dropdown
                      if (_shouldShowSchoolTypeFilter) ...[
                        SizedBox(
                          height: 44,
                          child: DropdownButtonFormField<String>(
                            alignment: AlignmentDirectional.bottomStart,
                            dropdownColor: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.indigo.shade900,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                              prefixIcon: const Icon(Icons.school_rounded, color: Colors.indigo, size: 18),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.indigo.shade100, width: 1.5),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.indigo.shade100, width: 1.5),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Colors.indigo, width: 2),
                              ),
                              filled: true,
                              fillColor: Colors.indigo.withOpacity(0.02),
                            ),
                            value: _selectedFilterSchoolTypeId == 'GENEL' && _isTeacher && _schoolTypes.isNotEmpty
                                ? _schoolTypes.first['id']
                                : _selectedFilterSchoolTypeId,
                            hint: Text(
                              'Genel Paylaşımlar',
                              style: GoogleFonts.inter(
                                color: Colors.blueGrey.shade500,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.indigo, size: 22),
                            items: [
                              if (!_isTeacher)
                                DropdownMenuItem(
                                  value: 'GENEL',
                                  child: Text(
                                    'Genel Paylaşımlar (Tüm Kurum)',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ..._schoolTypes.map((type) => DropdownMenuItem(
                                value: type['id'] as String,
                                child: Text(
                                  type['name'] as String,
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                                ),
                              )).toList(),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedFilterSchoolTypeId = val;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // View Mode Switcher: Yeni Paylaşımlar vs Okunanlar / Geçmiş (TÜM PAYLAŞIMLAR KALDIRILDI)
                      Container(
                        height: 40,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildViewModeTab(
                                key: 'new',
                                label: 'Yeni Paylaşımlar',
                                icon: Icons.mark_chat_unread_rounded,
                              ),
                            ),
                            Expanded(
                              child: _buildViewModeTab(
                                key: 'past',
                                label: 'Okunanlar / Geçmiş',
                                icon: Icons.history_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          body: StreamBuilder<QuerySnapshot>(
            stream: Stream.fromFuture(TermService().getSelectedTermId()).asyncExpand((termId) {
              Query query = FirebaseFirestore.instance
                  .collection('social_media_posts')
                  .where('institutionId', isEqualTo: widget.institutionId);

              if (widget.schoolTypeId.isNotEmpty) {
                query = query.where('schoolTypeId', isEqualTo: widget.schoolTypeId);
              }

              if (termId != null && termId.isNotEmpty) {
                query = query.where('termId', isEqualTo: termId);
              }

              return query.orderBy('createdAt', descending: true).snapshots();
            }),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Hata: ${snapshot.error}',
                    style: GoogleFonts.inter(color: Colors.red),
                  ),
                );
              }

              final activeFilterId = widget.schoolTypeId.isNotEmpty
                  ? widget.schoolTypeId
                  : _selectedFilterSchoolTypeId;

              // Oturum açılışında okunmamış olan doküman ID'lerini kaydet
              for (final doc in snapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final readByList = List<String>.from(data['readBy'] ?? []);
                final isRead = currentUserEmail.isNotEmpty && readByList.contains(currentUserEmail);
                if (!isRead) {
                  _sessionUnreadDocIds.add(doc.id);
                }
              }

              // Filter documents by school type categorization & read status
              List<QueryDocumentSnapshot> posts = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                
                // Institution check
                if (data['institutionId'] != null &&
                    data['institutionId'] != widget.institutionId) {
                  return false;
                }

                // School Type & Recipient Categorization Filter (Rules A, B, C)
                if (!_isPostVisibleForFilter(data, activeFilterId)) {
                  return false;
                }

                // Read / Past Filter Logic
                final readByList = List<String>.from(data['readBy'] ?? []);
                final isReadInDb = currentUserEmail.isNotEmpty && readByList.contains(currentUserEmail);
                final wasUnreadAtStart = _sessionUnreadDocIds.contains(doc.id);

                // Kullanıcı oturumu açıkken okuduğunda gönderi ekrandan aniden kaybolmaz;
                // ancak sayfa kapatılıp tekrar açıldığında Geçmiş sekmesine aktarılır.
                if (_viewMode == 'new' && isReadInDb && !wasUnreadAtStart) {
                  return false;
                }
                if (_viewMode == 'past' && !isReadInDb) {
                  return false;
                }

                return true;
              }).toList();

              if (posts.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _viewMode == 'new'
                            ? Icons.mark_chat_read_rounded
                            : (_viewMode == 'past'
                                ? Icons.history_toggle_off_rounded
                                : Icons.find_in_page_rounded),
                        size: 64,
                        color: Colors.indigo.shade200,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _viewMode == 'new'
                            ? 'Henüz okunmamış yeni paylaşım yok'
                            : (_viewMode == 'past'
                                ? 'Okunmuş geçmiş paylaşım bulunmuyor'
                                : 'Henüz paylaşım bulunmuyor'),
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.blueGrey.shade700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Yeni medya paylaşımı oluşturmak için aşağıdaki butonu kullanabilirsiniz.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.blueGrey.shade400,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Sorting pinned posts first, then newest timestamp
              posts.sort((a, b) {
                final dataA = a.data() as Map<String, dynamic>;
                final dataB = b.data() as Map<String, dynamic>;
                final isPinnedA = dataA['isPinned'] ?? false;
                final isPinnedB = dataB['isPinned'] ?? false;

                if (isPinnedA != isPinnedB) {
                  return isPinnedA ? -1 : 1;
                }
                final timeA = dataA['createdAt'] as Timestamp?;
                final timeB = dataB['createdAt'] as Timestamp?;
                if (timeA != null && timeB != null) {
                  return timeB.compareTo(timeA);
                }
                return 0;
              });

              return Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      int crossAxisCount = constraints.maxWidth > 700 ? 2 : 1;

                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        physics: const BouncingScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.75,
                        ),
                        itemCount: posts.length,
                        itemBuilder: (context, index) {
                          final post = posts[index];
                          final data = post.data() as Map<String, dynamic>;
                          return PostCard(
                            postId: post.id,
                            data: data,
                            currentUserId: _auth.currentUser?.uid,
                            currentUserEmail: currentUserEmail,
                            schoolTypeId: widget.schoolTypeId,
                            schoolTypesMap: _schoolTypes,
                          );
                        },
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreatePost,
        label: Text(
          'Yeni Medya Ekle',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        icon: const Icon(Icons.add_photo_alternate_rounded, color: Colors.white),
        backgroundColor: Colors.indigo,
        elevation: 4,
      ),
    );
  }

  Widget _buildViewModeTab({
    required String key,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _viewMode == key;
    return InkWell(
      onTap: () {
        setState(() {
          _viewMode = key;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.indigo : Colors.blueGrey.shade500,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.indigo : Colors.blueGrey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PostCard extends StatefulWidget {
  final String postId;
  final Map<String, dynamic> data;
  final String? currentUserId;
  final String? currentUserEmail;
  final String schoolTypeId;
  final List<Map<String, dynamic>> schoolTypesMap;

  const PostCard({
    Key? key,
    required this.postId,
    required this.data,
    this.currentUserId,
    this.currentUserEmail,
    required this.schoolTypeId,
    this.schoolTypesMap = const [],
  }) : super(key: key);

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  final PageController _pageController = PageController();
  int _currentImageIndex = 0;
  bool _isPlaying = false;
  bool _canManage = false;

  @override
  void initState() {
    super.initState();
    // Auto mark as read when rendering/interacting if user hasn't read it yet
    _autoMarkRead();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final data = await UserPermissionService.loadUserData();
    final role = (data?['role'] ?? '').toString().toLowerCase();
    final type = (data?['type'] ?? '').toString().toLowerCase();
    final isTeacher = role.contains('ogretmen') || role.contains('öğretmen') || role.contains('teacher');
    final isManager = role == 'admin' || role == 'manager' || role == 'genel_mudur' || type == 'admin' || role.contains('mudur') || role.contains('müdür');

    if (mounted) {
      setState(() {
        _canManage = !isTeacher && isManager;
      });
    }
  }

  Future<void> _autoMarkRead() async {
    final email = widget.currentUserEmail;
    if (email == null || email.isEmpty) return;
    final readBy = List<String>.from(widget.data['readBy'] ?? []);
    if (!readBy.contains(email)) {
      try {
        await FirebaseFirestore.instance
            .collection('social_media_posts')
            .doc(widget.postId)
            .update({
          'readBy': FieldValue.arrayUnion([email]),
        });
      } catch (e) {
        debugPrint('Auto mark read error: $e');
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _toggleLike(List<dynamic> likes) async {
    if (widget.currentUserId == null) return;
    final userIdentifier = widget.currentUserEmail ?? widget.currentUserId;
    final docRef = FirebaseFirestore.instance
        .collection('social_media_posts')
        .doc(widget.postId);

    if (likes.contains(userIdentifier)) {
      await docRef.update({
        'likes': FieldValue.arrayRemove([userIdentifier]),
        'likeCount': FieldValue.increment(-1),
      });
    } else {
      await docRef.update({
        'likes': FieldValue.arrayUnion([userIdentifier]),
        'likeCount': FieldValue.increment(1),
      });
    }
  }

  Future<void> _togglePin(bool currentStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('social_media_posts')
          .doc(widget.postId)
          .update({'isPinned': !currentStatus});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentStatus ? 'Sabitleme kaldırıldı' : 'Gönderi sabitlendi',
            style: GoogleFonts.inter(),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Pin error: $e');
    }
  }

  Future<void> _deletePost() async {
    try {
      await FirebaseFirestore.instance
          .collection('social_media_posts')
          .doc(widget.postId)
          .delete();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gönderi silindi', style: GoogleFonts.inter())));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e', style: GoogleFonts.inter())));
    }
  }

  void _editPost() {
    showDialog(
      context: context,
      builder: (ctx) => _EditPostModal(
        postId: widget.postId,
        initialCaption: widget.data['caption'],
        initialRecipients: List<String>.from(widget.data['recipients'] ?? []),
        schoolTypeId: widget.schoolTypeId,
      ),
    );
  }

  void _showPostOptions(bool isPinned, String creatorEmail) {
    final isOwner = widget.currentUserEmail == creatorEmail;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: Icon(
              isPinned ? Icons.push_pin_outlined : Icons.push_pin,
              color: Colors.indigo,
            ),
            title: Text(
              isPinned ? 'Sabitlemeyi Kaldır' : 'Gönderiyi Sabitle',
              style: GoogleFonts.inter(),
            ),
            onTap: () {
              Navigator.pop(context);
              _togglePin(isPinned);
            },
          ),
          if (isOwner) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: Text('Düzenle', style: GoogleFonts.inter()),
              onTap: () {
                Navigator.pop(context);
                _editPost();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text('Sil', style: GoogleFonts.inter()),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('Emin misiniz?', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    content: Text('Bu gönderi kalıcı olarak silinecek.', style: GoogleFonts.inter()),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('İptal', style: GoogleFonts.inter()),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _deletePost();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: Text('Sil', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays > 7) return DateFormat('dd/MM/yyyy').format(date);
    if (difference.inDays > 0) return '${difference.inDays} gn';
    if (difference.inHours > 0) return '${difference.inHours} sa';
    if (difference.inMinutes > 0) return '${difference.inMinutes} dk';
    return 'Şimdi';
  }

  void _downloadBase64Image(String base64String) {
    try {
      final bytes = base64Decode(base64String);
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute(
          "download",
          "image_${DateTime.now().millisecondsSinceEpoch}.jpg",
        )
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      debugPrint("Download error: $e");
    }
  }

  void _openFullScreenImage(List<String> images, int initialIndex) {
    _autoMarkRead();
    showDialog(
      context: context,
      builder: (context) => _FullScreenImageViewer(
        images: images,
        initialIndex: initialIndex,
        onDownload: _downloadBase64Image,
      ),
    );
  }

  String? _extractYoutubeId(String url) {
    if (url.trim().isEmpty) return null;
    try {
      final uri = Uri.parse(url.trim());
      if (uri.host.contains('youtube.com')) {
        if (uri.queryParameters.containsKey('v')) {
          return uri.queryParameters['v'];
        }
        if (uri.pathSegments.contains('shorts') &&
            uri.pathSegments.last.isNotEmpty) {
          return uri.pathSegments.last;
        }
      }
      if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.last;
      }
    } catch (e) {}

    RegExp regExp = RegExp(
      r'.*(?:(?:youtu\.be\/|v\/|vi\/|u\/\w\/|embed\/|e\/)|(?:(?:watch)?\?v(?:i)?=|\&v(?:i)?=))([^#\&\?]*).*',
      caseSensitive: false,
      multiLine: false,
    );
    final match = regExp.firstMatch(url);
    if (match != null && match.groupCount >= 1) {
      final id = match.group(1);
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  String? _getEmbedUrl(String url) {
    url = url.trim();

    if (url.contains('drive.google.com')) {
      final RegExp driveExp = RegExp(r'(?:file\/d\/|id=)([-_\w]+)');
      final match = driveExp.firstMatch(url);
      if (match != null) {
        final id = match.group(1);
        return 'https://drive.google.com/file/d/$id/preview';
      }
    }

    if (url.contains('youtube.com') || url.contains('youtu.be')) {
      final youtubeId = _extractYoutubeId(url);
      if (youtubeId != null) {
        return 'https://www.youtube.com/embed/$youtubeId?autoplay=1&rel=0&modestbranding=1';
      }
    }

    final lower = url.toLowerCase();
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.ogg')) {
      return url;
    }

    return url;
  }

  Widget _buildVideoPlaceholder(String url) {
    if (_isPlaying) {
      final String? embedUrl = _getEmbedUrl(url);

      if (embedUrl != null) {
        final String viewId = 'web_view-${widget.postId}';
        try {
          // ignore: undefined_prefixed_name
          ui.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
            final element = html.IFrameElement()
              ..src = embedUrl
              ..style.border = 'none'
              ..allow =
                  'autoplay; fullscreen; picture-in-picture; encrypted-media';
            return element;
          });
        } catch (e) {}

        return AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            children: [
              HtmlElementView(viewType: viewId),
              Positioned(top: 8, right: 8, child: _buildCloseButton()),
            ],
          ),
        );
      }
    }

    final videoId = _extractYoutubeId(url);
    final thumbnailUrl = videoId != null
        ? 'https://img.youtube.com/vi/$videoId/0.jpg'
        : '';

    return GestureDetector(
      onTap: () {
        _autoMarkRead();
        setState(() => _isPlaying = true);
      },
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          alignment: Alignment.center,
          children: [
            thumbnailUrl.isNotEmpty
                ? Image.network(
                    thumbnailUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (c, o, s) => Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF2C3E50), Color(0xFF000000)],
                        ),
                      ),
                    ),
                  )
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF2C3E50), Color(0xFF000000)],
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.video_library,
                        color: Colors.white54,
                        size: 40,
                      ),
                    ),
                  ),
            Container(color: Colors.black26),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white24,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloseButton() {
    return InkWell(
      onTap: () {
        setState(() {
          _isPlaying = false;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, color: Colors.white, size: 24),
      ),
    );
  }

  String _getSchoolTypeName(String typeId) {
    if (typeId.isEmpty) return 'Genel';
    for (var st in widget.schoolTypesMap) {
      if (st['id'] == typeId) return st['name'] ?? 'Okul';
    }
    return 'Okul';
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final likeCount = data['likeCount'] ?? 0;
    final likes = List<String>.from(data['likes'] ?? []);
    final userIdentifier = widget.currentUserEmail ?? widget.currentUserId;
    final isLiked = userIdentifier != null && likes.contains(userIdentifier);
    final caption = data['caption'] ?? '';
    final creatorName = data['creatorName'] ?? 'Anonim';
    final creatorPhotoUrl = data['creatorPhotoUrl'];
    final timestamp = data['createdAt'] as Timestamp?;
    final date = timestamp?.toDate() ?? DateTime.now();
    final isPinned = data['isPinned'] ?? false;
    final creatorEmail = data['createdBy'] ?? '';

    final readByList = List<String>.from(data['readBy'] ?? []);
    final isRead = widget.currentUserEmail != null && readByList.contains(widget.currentUserEmail);

    // School type & recipient tagging labels
    final postSchoolTypeId = (data['schoolTypeId'] ?? '').toString();
    final schoolTagLabel = _getSchoolTypeName(postSchoolTypeId);
    final recipientsList = List<String>.from(data['recipients'] ?? []);
    final isPublic = data['isPublic'] ?? recipientsList.isEmpty;

    List<String> images = [];
    if (data['mediaItems'] != null) {
      images = List<String>.from(data['mediaItems']);
    } else if (data['imageBase64'] != null &&
        data['imageBase64'].toString().isNotEmpty) {
      images = [data['imageBase64']];
    }

    final videoUrl = data['videoUrl'] as String?;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 15,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with School Type & Recipient Tags + User Info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tagging bar: School Type & Target Audience Chips
                Row(
                  children: [
                    // School Type Chip Tag
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.indigo.shade100),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.school_rounded, size: 12, color: Colors.indigo.shade700),
                          const SizedBox(width: 4),
                          Text(
                            schoolTagLabel,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Target Audience Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isPublic ? Colors.teal.shade50 : Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isPublic ? Colors.teal.shade200 : Colors.purple.shade200,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPublic ? Icons.public_rounded : Icons.groups_rounded,
                            size: 12,
                            color: isPublic ? Colors.teal.shade700 : Colors.purple.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isPublic ? 'Tüm Okul' : '${recipientsList.length} Alıcı Grubu',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isPublic ? Colors.teal.shade800 : Colors.purple.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Unread Status Badge ("YENİ")
                    if (!isRead)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade500,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.amber.withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          "YENİ",
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 8),

                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundImage: creatorPhotoUrl != null
                          ? NetworkImage(creatorPhotoUrl)
                          : null,
                      backgroundColor: Colors.indigo.shade50,
                      child: creatorPhotoUrl == null
                          ? Icon(
                              Icons.person,
                              size: 18,
                              color: Colors.indigo.shade300,
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            creatorName,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.grey.shade900,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isPinned)
                            Row(
                              children: [
                                const Icon(
                                  Icons.push_pin,
                                  size: 12,
                                  color: Colors.orange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "Sabitlendi",
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    if (_canManage)
                      IconButton(
                        icon: const Icon(Icons.more_horiz, size: 20),
                        onPressed: () => _showPostOptions(isPinned, creatorEmail),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Image / Video Area
          Expanded(
            child: (videoUrl != null && videoUrl.isNotEmpty)
                ? _buildVideoPlaceholder(videoUrl)
                : images.isNotEmpty
                ? Stack(
                    children: [
                      PageView.builder(
                        controller: _pageController,
                        itemCount: images.length,
                        onPageChanged: (idx) =>
                            setState(() => _currentImageIndex = idx),
                        itemBuilder: (context, idx) {
                          return GestureDetector(
                            onTap: () => _openFullScreenImage(images, idx),
                            child: Image.memory(
                              base64Decode(images[idx]),
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, _, __) => Container(
                                color: Colors.grey[100],
                                child: const Icon(Icons.broken_image),
                              ),
                            ),
                          );
                        },
                      ),
                      if (images.length > 1) ...[
                        if (_currentImageIndex > 0)
                          Positioned(
                            left: 8,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: CircleAvatar(
                                backgroundColor: Colors.black26,
                                radius: 14,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(
                                    Icons.chevron_left,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _pageController.previousPage(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeInOut,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        if (_currentImageIndex < images.length - 1)
                          Positioned(
                            right: 8,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: CircleAvatar(
                                backgroundColor: Colors.black26,
                                radius: 14,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(
                                    Icons.chevron_right,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _pageController.nextPage(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeInOut,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                      ],
                      if (images.length > 1)
                        Positioned(
                          bottom: 8,
                          right: 0,
                          left: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(images.length, (index) {
                              return Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                width: _currentImageIndex == index ? 8 : 6,
                                height: _currentImageIndex == index ? 8 : 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _currentImageIndex == index
                                      ? Colors.white
                                      : Colors.white54,
                                ),
                              );
                            }),
                          ),
                        ),
                      if (images.length > 1)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              "${_currentImageIndex + 1}/${images.length}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                : Container(
                    color: Colors.grey[100],
                    child: const Center(
                      child: Icon(
                        Icons.image_not_supported,
                        color: Colors.grey,
                      ),
                    ),
                  ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, top: 4),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? Colors.red : Colors.black87,
                  ),
                  onPressed: () {
                    _autoMarkRead();
                    _toggleLike(likes);
                  },
                ),
                if (likeCount > 0)
                  Text(
                    '$likeCount',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),

                const Spacer(),
                if (_canManage)
                  IconButton(
                    icon: Icon(
                      isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      color: isPinned ? Colors.orange : Colors.grey,
                    ),
                    onPressed: () => _togglePin(isPinned),
                    tooltip: 'Sabitle',
                  ),
              ],
            ),
          ),

          // Caption & Date
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (caption.isNotEmpty)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$creatorName ',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.grey.shade900,
                          ),
                        ),
                        TextSpan(
                          text: caption,
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade800),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 4),
                Text(
                  _formatTimeAgo(date),
                  style: GoogleFonts.inter(color: Colors.blueGrey.shade400, fontSize: 10),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FullScreenImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  final Function(String) onDownload;

  const _FullScreenImageViewer({
    Key? key,
    required this.images,
    required this.initialIndex,
    required this.onDownload,
  }) : super(key: key);

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.images.length,
            onPageChanged: (idx) => setState(() => _currentIndex = idx),
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.memory(
                  base64Decode(widget.images[index]),
                  fit: BoxFit.contain,
                ),
              );
            },
          ),
          if (widget.images.length > 1) ...[
            if (_currentIndex > 0)
              Positioned(
                left: 20,
                child: CircleAvatar(
                  backgroundColor: Colors.white24,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => _controller.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
                  ),
                ),
              ),
            if (_currentIndex < widget.images.length - 1)
              Positioned(
                right: 20,
                child: CircleAvatar(
                  backgroundColor: Colors.white24,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_forward, color: Colors.white),
                    onPressed: () => _controller.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
                  ),
                ),
              ),
          ],
          Positioned(
            top: 40,
            left: 20,
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 20,
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: IconButton(
                icon: const Icon(Icons.download, color: Colors.white),
                onPressed: () =>
                    widget.onDownload(widget.images[_currentIndex]),
              ),
            ),
          ),
          if (widget.images.length > 1)
            Positioned(
              bottom: 40,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "${_currentIndex + 1} / ${widget.images.length}",
                  style: GoogleFonts.inter(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EditPostModal extends StatefulWidget {
  final String postId;
  final String initialCaption;
  final List<String> initialRecipients;
  final String schoolTypeId;

  const _EditPostModal({
    Key? key,
    required this.postId,
    required this.initialCaption,
    required this.initialRecipients,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<_EditPostModal> createState() => _EditPostModalState();
}

class _EditPostModalState extends State<_EditPostModal> {
  late TextEditingController _captionController;
  late List<String> _recipients;
  bool _isPublic = false;
  final AnnouncementService _announcementService = AnnouncementService();

  List<Map<String, dynamic>> _classes = [];
  String? _selectedClass;
  bool _isLoadingClasses = false;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.initialCaption);
    _recipients = List.from(widget.initialRecipients);
    _isPublic = _recipients.isEmpty;
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _isLoadingClasses = true);
    try {
      final classes = await _announcementService.getClasses(
        widget.schoolTypeId,
      );
      if (mounted) setState(() => _classes = classes);
    } catch (e) {
      debugPrint("Error loading classes: $e");
    } finally {
      if (mounted) setState(() => _isLoadingClasses = false);
    }
  }

  void _addRecipient(String id) {
    if (!_recipients.contains(id)) {
      setState(() {
        _recipients.add(id);
        _isPublic = false;
      });
    }
  }

  void _removeRecipient(String id) {
    setState(() {
      _recipients.remove(id);
      if (_recipients.isEmpty) _isPublic = true;
    });
  }

  void _addClassRecipients() {
    if (_selectedClass == null) return;
    _addRecipient('class:${widget.schoolTypeId}_$_selectedClass');
    setState(() => _selectedClass = null);
  }

  Future<void> _save() async {
    try {
      await FirebaseFirestore.instance
          .collection('social_media_posts')
          .doc(widget.postId)
          .update({
            'caption': _captionController.text.trim(),
            'recipients': _isPublic ? [] : _recipients,
            'isPublic': _isPublic,
          });
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gönderi güncellendi', style: GoogleFonts.inter())));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e', style: GoogleFonts.inter())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Gönderiyi Düzenle",
              style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _captionController,
              style: GoogleFonts.inter(),
              decoration: InputDecoration(
                labelText: "Açıklama",
                labelStyle: GoogleFonts.inter(),
                border: const OutlineInputBorder(),
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),

            Text(
              "Hedef Kitle",
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SwitchListTile(
              title: Text("Herkese Açık", style: GoogleFonts.inter()),
              subtitle: Text("Tüm okul ve veliler görebilir", style: GoogleFonts.inter(fontSize: 12)),
              value: _isPublic,
              onChanged: (val) {
                setState(() {
                  _isPublic = val;
                  if (val) _recipients.clear();
                });
              },
            ),

            if (!_isPublic) ...[
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: _isLoadingClasses
                        ? const LinearProgressIndicator()
                        : DropdownButtonFormField<String>(
                            value: _selectedClass,
                            hint: Text("Sınıf Seç", style: GoogleFonts.inter()),
                            isExpanded: true,
                            items: _classes.map<DropdownMenuItem<String>>((c) {
                              final val = c['name'].toString();
                              return DropdownMenuItem<String>(
                                value: val,
                                child: Text(val, style: GoogleFonts.inter()),
                              );
                            }).toList(),
                            onChanged: (val) =>
                                setState(() => _selectedClass = val),
                          ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.indigo),
                    onPressed: _addClassRecipients,
                    tooltip: "Sınıf Ekle",
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _recipients.map((r) {
                  String label = r;
                  if (r.startsWith('class:')) label = r.split('_').last;
                  return Chip(
                    label: Text(label, style: GoogleFonts.inter()),
                    onDeleted: () => _removeRecipient(r),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("İptal", style: GoogleFonts.inter()),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                  child: Text("Kaydet", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  final double minHeight;
  final double maxHeight;
  final Widget child;

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => math.max(maxHeight, minHeight);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight ||
        minHeight != oldDelegate.minHeight ||
        child != oldDelegate.child;
  }
}
