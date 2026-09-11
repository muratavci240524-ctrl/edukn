import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/school/dynamic_course_group_model.dart';
import 'term_service.dart';

class DynamicGroupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('courseGroups');

  /// Yeni grup kaydeder veya günceller
  Future<String> saveGroup(DynamicCourseGroup group) async {
    try {
      final docRef = group.id.isEmpty ? _collection.doc() : _collection.doc(group.id);
      final finalGroup = group.copyWith(id: docRef.id);

      await docRef.set(finalGroup.toMap(), SetOptions(merge: true));

      // Öğrenci kayıtlarını senkronize et
      _syncStudentsEnrollments(finalGroup);

      return docRef.id;
    } catch (e) {
      debugPrint('❌ Error saving dynamic course group: $e');
      rethrow;
    }
  }

  /// Öğrencilerin dokümanına kur/kulüp bilgisini hafifçe işler (hızlı erişim için)
  Future<void> _syncStudentsEnrollments(DynamicCourseGroup group) async {
    try {
      final batch = _firestore.batch();
      int count = 0;

      for (var subGroup in group.subGroups) {
        for (var studentId in subGroup.studentIds) {
          if (studentId.isEmpty) continue;
          final studentRef = _firestore.collection('students').doc(studentId);
          batch.set(studentRef, {
            'courseGroupEnrollments': {
              group.id: subGroup.id,
            },
            'courseGroupNames': {
              group.id: subGroup.name,
            },
          }, SetOptions(merge: true));
          count++;

          if (count >= 400) {
            await batch.commit();
            count = 0;
          }
        }
      }

      if (count > 0) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint('⚠️ Student group enrollment sync warning: $e');
    }
  }

  /// Grup siler
  Future<void> deleteGroup(String groupId) async {
    try {
      await _collection.doc(groupId).delete();
    } catch (e) {
      debugPrint('❌ Error deleting group: $e');
      rethrow;
    }
  }

  /// Kurum ve okul türüne göre grupları listeler
  Future<List<DynamicCourseGroup>> fetchGroups({
    required String institutionId,
    required String schoolTypeId,
    String? termId,
    DynamicCourseGroupType? type,
  }) async {
    try {
      final effectiveTermId = termId ??
          await TermService().getSelectedTermId() ??
          await TermService().getActiveTermId();

      final instUpper = institutionId.toUpperCase();
      final instLower = institutionId.toLowerCase();

      Query<Map<String, dynamic>> query = _collection
          .where('institutionId', whereIn: [instUpper, instLower])
          .where('schoolTypeId', isEqualTo: schoolTypeId)
          .where('isActive', isEqualTo: true);

      if (type != null) {
        query = query.where('type', isEqualTo: type == DynamicCourseGroupType.club ? 'club' : 'track');
      }

      final snap = await query.get();

      final list = snap.docs.map((d) => DynamicCourseGroup.fromFirestore(d)).toList();

      if (effectiveTermId != null) {
        // Bu kuruma, okul türüne ve YALNIZCA SEÇİLİ MEVCUT TERMID'YE ait alt dönemler
        final periodsSnap = await _firestore
            .collection('workPeriods')
            .where('institutionId', whereIn: [instUpper, instLower])
            .where('schoolTypeId', isEqualTo: schoolTypeId)
            .where('termId', isEqualTo: effectiveTermId)
            .where('isActive', isEqualTo: true)
            .get();
        final periodIds = periodsSnap.docs.map((d) => d.id).toSet();

        return list.where((g) {
          // 1. TermId boşsa (genel)
          if (g.termId == null || g.termId!.trim().isEmpty) return true;
          // 2. TermId doğrudan seçili akademik döneme eşitse
          if (g.termId == effectiveTermId) return true;
          // 3. Grubun periodId veya termId alanı bu okulun alt dönemlerinden biriyse
          if (periodIds.contains(g.termId) || (g.periodId != null && periodIds.contains(g.periodId))) return true;
          return false;
        }).toList();
      }

      return list;
    } catch (e) {
      debugPrint('❌ Error fetching dynamic course groups: $e');
      return [];
    }
  }

  /// ID ile tek bir grubu getirir
  Future<DynamicCourseGroup?> getGroupById(String groupId) async {
    try {
      final doc = await _collection.doc(groupId).get();
      if (!doc.exists) return null;
      return DynamicCourseGroup.fromFirestore(doc);
    } catch (e) {
      debugPrint('❌ Error getting group by id: $e');
      return null;
    }
  }

  /// Belirli bir şube ve ders için tanımlı Dinamik Grubu bulur
  Future<DynamicCourseGroup?> findGroupForClassAndLesson({
    required String institutionId,
    required String schoolTypeId,
    required String classId,
    required String lessonId,
    String? termId,
  }) async {
    try {
      final allGroups = await fetchGroups(
        institutionId: institutionId,
        schoolTypeId: schoolTypeId,
        termId: termId,
      );

      for (var g in allGroups) {
        if (g.targetClassIds.contains(classId)) {
          // Kulüp tipinde lessonId eşleşmesine gerek yok, type yeterli
          if (g.lessonId == lessonId || g.type == DynamicCourseGroupType.club) {
            return g;
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error finding group: $e');
      return null;
    }
  }

  /// Bir alt gruptaki öğrencilerin tam öğrenci dokümanlarını ve asıl şube adlarını yükler
  Future<List<Map<String, dynamic>>> loadStudentsForSubGroup({
    required DynamicSubGroup subGroup,
    required String institutionId,
    required String schoolTypeId,
  }) async {
    if (subGroup.studentIds.isEmpty) return [];

    try {
      // Chunking 30 per query (Firestore whereIn limit)
      final List<Map<String, dynamic>> results = [];
      final studentIds = subGroup.studentIds.toSet().toList();

      for (var i = 0; i < studentIds.length; i += 30) {
        final chunk = studentIds.sublist(
          i,
          i + 30 > studentIds.length ? studentIds.length : i + 30,
        );

        final snap = await _firestore
            .collection('students')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (var doc in snap.docs) {
          final data = doc.data();
          data['id'] = doc.id;
          results.add(data);
        }
      }

      // Sınıf adlarını tamamla (eğer doc içinde yoksa)
      final classIds = results.map((s) => s['classId']?.toString()).whereType<String>().toSet();
      final Map<String, String> classNames = {};

      for (var cId in classIds) {
        if (cId.isEmpty) continue;
        final cDoc = await _firestore.collection('classes').doc(cId).get();
        if (cDoc.exists) {
          classNames[cId] = (cDoc.data()?['className'] ?? cDoc.data()?['name'] ?? '').toString();
        }
      }

      for (var s in results) {
        final cId = s['classId']?.toString() ?? '';
        if ((s['className'] == null || s['className'].toString().isEmpty) && classNames.containsKey(cId)) {
          s['className'] = classNames[cId];
        }
      }

      // İsme göre Türkçe sırala
      results.sort((a, b) {
        final nameA = '${a['firstName'] ?? ''} ${a['lastName'] ?? ''}'.trim();
        final nameB = '${b['firstName'] ?? ''} ${b['lastName'] ?? ''}'.trim();
        return nameA.toLowerCase().compareTo(nameB.toLowerCase());
      });

      return results;
    } catch (e) {
      debugPrint('❌ Error loading students for subGroup: $e');
      return [];
    }
  }

  /// Kulüp değerlendirmesi kaydetme
  Future<void> saveClubEvaluation({
    required String institutionId,
    required String schoolTypeId,
    required String termId,
    required String groupId,
    required String subGroupId,
    required String studentId,
    required Map<String, dynamic> evaluationData,
  }) async {
    try {
      final docId = '${termId}_${groupId}_${subGroupId}_$studentId';
      await _firestore.collection('clubEvaluations').doc(docId).set({
        'id': docId,
        'institutionId': institutionId,
        'schoolTypeId': schoolTypeId,
        'termId': termId,
        'groupId': groupId,
        'subGroupId': subGroupId,
        'studentId': studentId,
        'evaluation': evaluationData,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ Error saving club evaluation: $e');
      rethrow;
    }
  }

  /// Kulüp değerlendirmelerini yükleme
  Future<Map<String, Map<String, dynamic>>> loadClubEvaluations({
    required String termId,
    required String groupId,
    required String subGroupId,
  }) async {
    try {
      final snap = await _firestore
          .collection('clubEvaluations')
          .where('termId', isEqualTo: termId)
          .where('groupId', isEqualTo: groupId)
          .where('subGroupId', isEqualTo: subGroupId)
          .get();

      final Map<String, Map<String, dynamic>> res = {};
      for (var doc in snap.docs) {
        final data = doc.data();
        final sId = data['studentId']?.toString();
        final eval = data['evaluation'];
        if (sId != null && eval is Map) {
          res[sId] = Map<String, dynamic>.from(eval);
        }
      }
      return res;
    } catch (e) {
      debugPrint('❌ Error loading evaluations: $e');
      return {};
    }
  }
}
