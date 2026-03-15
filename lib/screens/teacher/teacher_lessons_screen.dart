import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../school/teacher_schedule_view_screen.dart';
import '../../services/user_permission_service.dart';

class TeacherLessonsScreen extends StatefulWidget {
  final String institutionId;

  const TeacherLessonsScreen({Key? key, required this.institutionId}) : super(key: key);

  @override
  State<TeacherLessonsScreen> createState() => _TeacherLessonsScreenState();
}

class _TeacherLessonsScreenState extends State<TeacherLessonsScreen> {
  Map<String, dynamic>? userData;
  bool isLoading = true;
  List<Map<String, dynamic>> schoolTypes = [];

  @override
  void initState() {
    super.initState();
    _loadTeacherData();
  }

  Future<void> _loadTeacherData() async {
    final data = await UserPermissionService.loadUserData();
    if (!mounted) return;

    if (data == null) {
      setState(() => isLoading = false);
      return;
    }

    // Doğru ID'yi belirle (DocID, UID, Name)
    final teacherId = (data['id'] ?? FirebaseAuth.instance.currentUser?.uid).toString();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final fullName = (data['fullName'] ?? "").toString();
    final instId = (data['institutionId'] ?? widget.institutionId ?? "").toString().toUpperCase();

    debugPrint('🔍 Derslerim Tanılama - UID: $currentUid, DocID: $teacherId, Name: $fullName, Inst: "$instId"');

    Set<String> typeIds = Set<String>.from((data['schoolTypes'] ?? []).map((e) => e.toString()));
    
    // Eğer okul türleri boşsa, workLocations (isim bazlı) alanına bak
    if (typeIds.isEmpty && data['workLocations'] != null) {
      final List<dynamic> locations = data['workLocations'];
      debugPrint('   - workLocations bulundu: $locations');
      if (locations.isNotEmpty) {
        final typesSnap = await FirebaseFirestore.instance
            .collection('schoolTypes')
            .where('institutionId', isEqualTo: instId)
            .get();
        
        for (var loc in locations) {
          final match = typesSnap.docs.where((doc) => 
            doc.data()['typeName'] == loc || doc.id == loc
          );
          if (match.isNotEmpty) {
            typeIds.add(match.first.id);
          }
        }
      }
    }

    // Ders atamalarından okul türlerini bul (Genişletilmiş arama)
    if (teacherId.isNotEmpty) {
      debugPrint('   🔍 Genişletilmiş atama araması başlatılıyor...');
      
      final queries = [
        // 1. Strateji: DocID ile
        FirebaseFirestore.instance.collection('lessonAssignments')
            .where('institutionId', isEqualTo: instId)
            .where('teacherIds', arrayContains: teacherId).get(),
            
        // 2. Strateji: UID ile
        if (currentUid != null && currentUid != teacherId)
          FirebaseFirestore.instance.collection('lessonAssignments')
              .where('institutionId', isEqualTo: instId)
              .where('teacherIds', arrayContains: currentUid).get(),

        // 3. Strateji: İsim ile
        if (fullName.isNotEmpty)
          FirebaseFirestore.instance.collection('lessonAssignments')
              .where('institutionId', isEqualTo: instId)
              .where('teacherNames', arrayContains: fullName).get(),
              
        // 4. Strateji: Küçük harf InstId
        FirebaseFirestore.instance.collection('lessonAssignments')
            .where('institutionId', isEqualTo: instId.toLowerCase())
            .where('teacherIds', arrayContains: teacherId).get(),
      ];

      final snaps = await Future.wait(queries);
      for (var snap in snaps) {
        for (var doc in snap.docs) {
          final tid = doc.data()['schoolTypeId']?.toString();
          if (tid != null) typeIds.add(tid);
        }
      }
      
      // Global Fallback: Eğer hala yoksa kurum filtresiz ara
      if (typeIds.isEmpty) {
        debugPrint('   ⚠️ Filtresiz global arama yapılıyor...');
        final globalSnap = await FirebaseFirestore.instance.collection('lessonAssignments')
            .where('teacherIds', arrayContains: teacherId).get();
        for (var doc in globalSnap.docs) {
          final tid = doc.data()['schoolTypeId']?.toString();
          if (tid != null) typeIds.add(tid);
        }
      }
    }

    if (typeIds.isEmpty) {
      debugPrint('   ❌ Hiçbir yöntemle okul türü bulunamadı.');
      if (mounted) {
        setState(() {
          userData = data;
          isLoading = false;
        });
      }
      return;
    }

    debugPrint('   ✅ Bulunan Okul Türü IDleri: $typeIds');
    final typeIdList = typeIds.toList();

    // Okul türü isimlerini al (Chunking 10)
    List<Map<String, dynamic>> loadedTypes = [];
    for (var i = 0; i < typeIdList.length; i += 10) {
      final chunk = typeIdList.skip(i).take(10).toList();
      
      // Try uppercase institutionId
      var typesSnap = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .where('institutionId', isEqualTo: instId)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      
      // Try lowercase institutionId if no results
      if (typesSnap.docs.isEmpty) {
        typesSnap = await FirebaseFirestore.instance
            .collection('schoolTypes')
            .where('institutionId', isEqualTo: instId.toLowerCase())
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
      }
      
      for (var doc in typesSnap.docs) {
        final d = doc.data();
        loadedTypes.add({
          'id': doc.id,
          'name': d['schoolTypeName'] ?? d['typeName'] ?? 'Okul Türü',
        });
      }
    }

    if (mounted) {
      setState(() {
        userData = data;
        schoolTypes = loadedTypes;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (schoolTypes.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ders Programım'), backgroundColor: Colors.indigo),
        body: const Center(child: Text('Size tanımlı bir okul türü bulunamadı.')),
      );
    }

    // Eğer birden fazla okul türü varsa seçim yaptır, tek ise direkt aç
    if (schoolTypes.length == 1) {
      return TeacherScheduleViewScreen(
        schoolTypeId: schoolTypes[0]['id'],
        schoolTypeName: schoolTypes[0]['name'],
        institutionId: widget.institutionId,
        isTeacherView: true,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Okul Türü Seçin'),
        backgroundColor: Colors.indigo,
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: schoolTypes.length,
        itemBuilder: (context, index) {
          final type = schoolTypes[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: const Icon(Icons.school, color: Colors.indigo),
              title: Text(type['name']),
              subtitle: const Text('Ders programını görüntüle'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => TeacherScheduleViewScreen(
                      schoolTypeId: type['id'],
                      schoolTypeName: type['name'],
                      institutionId: widget.institutionId,
                      isTeacherView: true,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
