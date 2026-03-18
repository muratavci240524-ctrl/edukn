import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../../services/chat_service.dart';
import '../../services/announcement_service.dart';
import '../../services/user_permission_service.dart';
import '../../widgets/stylish_bottom_nav.dart';
import 'teacher_announcements_screen.dart';
import 'teacher_social_media_screen.dart';
import 'teacher_messages_screen.dart';
import 'teacher_operations_screen.dart';
import 'teacher_dashboard_tab.dart';

class TeacherMainScreen extends StatefulWidget {
  final String institutionId;

  const TeacherMainScreen({Key? key, required this.institutionId})
    : super(key: key);

  @override
  State<TeacherMainScreen> createState() => _TeacherMainScreenState();
}

class _TeacherMainScreenState extends State<TeacherMainScreen> {
  int _currentIndex = 0;
  late List<Widget> _pages;
  final List<bool> _pageLoaded = [false, false, false, false, false];

  int _unreadAnnouncements = 0;
  int _unreadMessages = 0;
  int _unreadSocial = 0;

  StreamSubscription? _announcementSub;
  StreamSubscription? _messageSub;
  StreamSubscription? _socialSub;

  @override
  void initState() {
    super.initState();
    _pages = [
      TeacherAnnouncementsScreen(institutionId: widget.institutionId), // 0
      TeacherSocialMediaScreen(institutionId: widget.institutionId),   // 1
      TeacherDashboardTab(institutionId: widget.institutionId),       // 2
      TeacherMessagesScreen(institutionId: widget.institutionId),      // 3
      TeacherOperationsScreen(institutionId: widget.institutionId),    // 4
    ];
    _pageLoaded[_currentIndex] = true; // İlk sayfayı yükle
    _startBadgeListeners();
  }

  @override
  void dispose() {
    _announcementSub?.cancel();
    _messageSub?.cancel();
    _socialSub?.cancel();
    super.dispose();
  }

  bool _isBadgeListenerStarted = false;

  void _startBadgeListeners() async {
    if (_isBadgeListenerStarted) return;
    _isBadgeListenerStarted = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1. Mesaj Bildirimleri
    _messageSub = ChatService().getConversations(user.uid).listen((conversations) {
      if (!mounted) return;
      int count = 0;
      for (var conv in conversations) {
        if (!conv.isArchived) {
          final countForMe = conv.unreadCounts[user.uid] ?? 0;
          count += countForMe;
        }
      }
      if (mounted) setState(() => _unreadMessages = count);
    });

    // 2. Duyuru Bildirimleri
    try {
      final userData = await UserPermissionService.loadUserData();
      final schoolId = await AnnouncementService().getSchoolId();
      final currentUserId = user.uid;
      final currentUserEmail = user.email;
      final instId = widget.institutionId.toUpperCase();

      if (schoolId == null) return;

      // Öğretmenin sınıflarını alalım
      final assignSnap = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: instId)
          .where('teacherIds', arrayContains: currentUserId)
          .where('isActive', isEqualTo: true)
          .get();

      final assignedClassIds = assignSnap.docs
          .map((doc) => doc.data()['classId']?.toString())
          .where((id) => id != null)
          .cast<String>()
          .toSet();

      final schoolTypes = userData?['schoolTypes'] as List<dynamic>? ?? [];
      final userSchoolTypeSet = schoolTypes.map((e) => e.toString()).toSet();

      _announcementSub = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('announcements')
          .where('status', isEqualTo: 'published')
          .snapshots()
          .listen((snapshot) {
        if (!mounted) return;
        
        int unreadCount = 0;
        final now = DateTime.now();

        for (var doc in snapshot.docs) {
          final data = doc.data();
          final readBy = List<dynamic>.from(data['readBy'] ?? []);
          
          if (currentUserEmail != null && readBy.contains(currentUserEmail)) continue;

          final schoolTypeId = data['schoolTypeId']?.toString();
          final recipients = List<String>.from(data['recipients'] ?? []);
          final publishDate = (data['publishDate'] as Timestamp?)?.toDate();

          if (publishDate != null && publishDate.isAfter(now)) continue;

          // Hızlı filtreleme mantığı
          bool isRecipient = false;
          if (recipients.contains('ALL') || recipients.contains('TEACHER') || recipients.contains('unit:ogretmen')) {
            isRecipient = true;
          } else if (recipients.contains('user:$currentUserId') || (currentUserEmail != null && recipients.contains(currentUserEmail))) {
            isRecipient = true;
          } else {
            for (final cid in assignedClassIds) {
              if (recipients.contains(cid) || recipients.contains('branch:$cid:Öğretmenler')) {
                isRecipient = true;
                break;
              }
            }
          }

          if (isRecipient && schoolTypeId != null && !userSchoolTypeSet.contains(schoolTypeId)) {
             if (!recipients.contains('ALL') && !recipients.contains('TEACHER')) isRecipient = false;
          }

          if (isRecipient) unreadCount++;
        }
        if (mounted) setState(() => _unreadAnnouncements = unreadCount);
      });

      // 3. Sosyal Medya Bildirimleri (Son 48 saat)
      _socialSub = FirebaseFirestore.instance
          .collection('social_media_posts')
          .where('institutionId', isEqualTo: instId)
          .snapshots()
          .listen((snapshot) {
        if (!mounted) return;
        
        int newPostsCount = 0;
        final now = DateTime.now();
        final twoDaysAgo = now.subtract(const Duration(hours: 48));

        for (var doc in snapshot.docs) {
          final data = doc.data();
          final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
          if (createdAt == null || createdAt.isBefore(twoDaysAgo)) continue;

          final recipients = List<String>.from(data['recipients'] ?? []);
          final schoolTypeId = data['schoolTypeId']?.toString();

          bool isRecipient = (recipients.isEmpty || recipients.contains('ALL') || recipients.contains('TEACHER'));
          if (!isRecipient) {
            if (recipients.contains('user:$currentUserId')) isRecipient = true;
            else {
              for (final cid in assignedClassIds) {
                if (recipients.contains('class:$cid')) { isRecipient = true; break; }
              }
            }
          }

          if (isRecipient && schoolTypeId != null && !userSchoolTypeSet.contains(schoolTypeId)) {
             if (!recipients.contains('ALL') && !recipients.contains('TEACHER')) isRecipient = false;
          }

          if (isRecipient) newPostsCount++;
        }
        if (mounted) setState(() => _unreadSocial = newPostsCount);
      });
    } catch (e) {
      debugPrint('Badge Listener Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(_pages.length, (index) {
          return _pageLoaded[index] 
              ? _pages[index] 
              : const Center(child: CircularProgressIndicator());
        }),
      ),
      bottomNavigationBar: StylishBottomNav(
        currentIndex: _currentIndex,
        badgeCounts: {
          0: _unreadAnnouncements,
          1: _unreadSocial,
          3: _unreadMessages,
        },
        onTap: (index) {
          setState(() {
            _currentIndex = index;
            _pageLoaded[index] = true;
            if (index == 1) _unreadSocial = 0;
          });
        },
      ),
    );
  }
}
