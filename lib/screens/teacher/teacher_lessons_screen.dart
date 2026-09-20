import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../school/teacher_schedule_view_screen.dart';
import '../../services/user_permission_service.dart';

class TeacherLessonsScreen extends StatefulWidget {
  final String institutionId;

  const TeacherLessonsScreen({Key? key, required this.institutionId}) : super(key: key);

  @override
  State<TeacherLessonsScreen> createState() => _TeacherLessonsScreenState();
}

class _TeacherLessonsScreenState extends State<TeacherLessonsScreen> {
  // ⚡ Cache-First RAM & Disk Önbelleği (Anında açılır, sıfır bekleme)
  static Map<String, dynamic>? _cachedUserData;
  static List<Map<String, dynamic>>? _cachedSchoolTypes;

  Map<String, dynamic>? userData;
  bool isLoading = true;
  List<Map<String, dynamic>> schoolTypes = [];

  Future<void> _loadFromDiskCache() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final prefs = await SharedPreferences.getInstance();
      final cachedStr = prefs.getString('edukn_teacher_lessons_types_${user.uid}_${widget.institutionId}');
      if (cachedStr != null && cachedStr.isNotEmpty && schoolTypes.isEmpty) {
        final List dec = json.decode(cachedStr);
        final list = dec.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (mounted && list.isNotEmpty) {
          setState(() {
            schoolTypes = list;
            userData = UserPermissionService.getCachedUserData();
            isLoading = false;
          });
          _cachedSchoolTypes = list;
          _cachedUserData = userData;
        }
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    if (_cachedSchoolTypes != null && _cachedSchoolTypes!.isNotEmpty) {
      userData = _cachedUserData;
      schoolTypes = List.from(_cachedSchoolTypes!);
      isLoading = false;
    } else {
      _loadFromDiskCache();
    }
    _loadTeacherData(isBackground: _cachedSchoolTypes != null && _cachedSchoolTypes!.isNotEmpty);
  }

  Future<void> _loadTeacherData({bool isBackground = false}) async {
    if (!isBackground) {
      setState(() => isLoading = true);
    }
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
      
      // Global Fallback: Eğer okul türü bulunamadıysa kurumun tüm okul türlerini al
      if (typeIds.isEmpty) {
        debugPrint('   ⚠️ Kurumun tüm okul türleri getiriliyor...');
        final instTypesSnap = await FirebaseFirestore.instance
            .collection('schoolTypes')
            .where('institutionId', isEqualTo: instId)
            .get();
        if (instTypesSnap.docs.isNotEmpty) {
          for (var doc in instTypesSnap.docs) {
            typeIds.add(doc.id);
          }
        } else {
          final instTypesSnap2 = await FirebaseFirestore.instance
              .collection('schoolTypes')
              .where('institutionId', isEqualTo: instId.toLowerCase())
              .get();
          for (var doc in instTypesSnap2.docs) {
            typeIds.add(doc.id);
          }
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

    _cachedUserData = data;
    _cachedSchoolTypes = List.from(loadedTypes);

    // 💾 Diske kalıcı kaydet
    SharedPreferences.getInstance().then((prefs) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      prefs.setString('edukn_teacher_lessons_types_${uid}_${widget.institutionId}', json.encode(loadedTypes));
    }).catchError((_) {});

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
        appBar: EduknAppBar(title: 'Derslerim'),
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
      appBar: EduknAppBar(title: 'Okul Türü Seçin'),
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
