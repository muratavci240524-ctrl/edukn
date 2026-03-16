import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/user_permission_service.dart';
import '../school/school_types/school_type_social_media_screen.dart';

class TeacherSocialMediaScreen extends StatefulWidget {
  final String institutionId;

  const TeacherSocialMediaScreen({
    Key? key,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<TeacherSocialMediaScreen> createState() => _TeacherSocialMediaScreenState();
}

class _TeacherSocialMediaScreenState extends State<TeacherSocialMediaScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Map<String, dynamic>? userData;
  Set<String> _assignedClassIds = {};
  Set<String> _assignedStudentIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final data = await UserPermissionService.loadUserData();
    
    // Sınıfları yükle (Genişletilmiş arama ve index hatasını önlemek için basitleştirilmiş sorgu)
    final user = _auth.currentUser;
    final teacherId = (data?['id'] ?? user?.uid)?.toString();
    final instId = (data?['institutionId'] ?? widget.institutionId ?? "").toString().toUpperCase();

    if (teacherId != null && teacherId.isNotEmpty) {
      try {
        // 1. Atanmış sınıfları bul
        final snapshot = await FirebaseFirestore.instance
            .collection('lessonAssignments')
            .where('institutionId', isEqualTo: instId)
            .where('teacherIds', arrayContains: teacherId)
            .where('isActive', isEqualTo: true)
            .get();

        _assignedClassIds = snapshot.docs
            .map((doc) => doc.data()['classId']?.toString())
            .where((id) => id != null)
            .cast<String>()
            .toSet();

        // 2. Bu sınıflardaki öğrencileri bul
        if (_assignedClassIds.isNotEmpty) {
          final classIdList = _assignedClassIds.toList();
          for (var i = 0; i < classIdList.length; i += 10) {
            final chunk = classIdList.skip(i).take(10).toList();
            final studentSnap = await FirebaseFirestore.instance
                .collection('students')
                .where('institutionId', isEqualTo: instId)
                .where('classId', whereIn: chunk)
                .get();
            
            for (var doc in studentSnap.docs) {
              _assignedStudentIds.add(doc.id);
            }
          }
        }
      } catch (e) {
        debugPrint('Social Media Data Loading Error: $e');
      }
    }

    if (mounted) {
      setState(() {
        userData = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.indigo,
        title: Text(
          'Okul Sosyal Medya',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('social_media_posts')
            .where('institutionId', isEqualTo: widget.institutionId.toUpperCase())
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Hata: ${snapshot.error}'));
          }

          final List<dynamic> userSchoolTypes = userData?['schoolTypes'] ?? [];
          final currentUserId = _auth.currentUser?.uid;
          final currentUserEmail = _auth.currentUser?.email;

          // Manual sorting by createdAt after fetching
          final List<QueryDocumentSnapshot> allDocs = 
              List.from(snapshot.data?.docs ?? []);
          
          allDocs.sort((a, b) {
            final dataA = a.data() as Map<String, dynamic>;
            final dataB = b.data() as Map<String, dynamic>;
            final timeA = dataA['createdAt'] as Timestamp?;
            final timeB = dataB['createdAt'] as Timestamp?;
            if (timeA == null) return 1;
            if (timeB == null) return -1;
            return timeB.compareTo(timeA); // Descending
          });

          final filteredPosts = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final schoolTypeId = data['schoolTypeId'] as String?;
            final recipients = List<String>.from(data['recipients'] ?? []);

            // 1. Okul türü kontrolü
            if (schoolTypeId != null && !userSchoolTypes.contains(schoolTypeId)) {
              return false;
            }

            // 2. Alıcı kontrolü
            if (recipients.isEmpty || recipients.contains('ALL') || recipients.contains('TEACHER')) {
              return true;
            }

            if (currentUserId != null && recipients.contains(currentUserId)) {
              return true;
            }

            if (currentUserEmail != null && recipients.contains(currentUserEmail)) {
              return true;
            }

            for (final classId in _assignedClassIds) {
              if (recipients.contains(classId)) {
                return true;
              }
            }

            for (final studentId in _assignedStudentIds) {
              if (recipients.contains(studentId)) {
                return true;
              }
            }

            return false;
          }).toList();

          if (filteredPosts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'Henüz sosyal medya gönderisi yok',
                    style: GoogleFonts.inter(color: Colors.grey.shade500),
                  ),
                ],
              ),
            );
          }

          // Pinned sorting
          filteredPosts.sort((a, b) {
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

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredPosts.length,
            itemBuilder: (context, index) {
              final post = filteredPosts[index];
              final data = post.data() as Map<String, dynamic>;
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: PostCard(
                  postId: post.id,
                  data: data,
                  currentUserId: currentUserId,
                  currentUserEmail: currentUserEmail,
                  schoolTypeId: data['schoolTypeId'] ?? '',
                ),
              );
            },
          );
        },
      ),
    );
  }
}
