import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/guidance/demand_model.dart';

class DemandService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'guidance_demands';

  // Talep oluştur
  Future<String> createDemand(DemandModel demand) async {
    final docRef = await _firestore.collection(_collection).add(demand.toMap());
    return docRef.id;
  }

  // Talebi güncelle
  Future<void> updateDemand(String docId, Map<String, dynamic> data) async {
    await _firestore.collection(_collection).doc(docId).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Talebi kapat
  Future<void> closeDemand({
    required String docId,
    required String closingNote,
    required String closerUid,
    required String closerName,
  }) async {
    await _firestore.collection(_collection).doc(docId).update({
      'status': DemandStatus.completed.name,
      'closingNote': closingNote,
      'closerUid': closerUid,
      'closerName': closerName,
      'closedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Talepleri getir (Stream)
  // Not: İndeks hatalarından kaçınmak için orderBy işlemini uygulama içinde yapıyoruz.
  Stream<List<DemandModel>> streamDemands({
    required String institutionId,
    String? schoolTypeId,
  }) {
    Query query = _firestore.collection(_collection)
        .where('institutionId', isEqualTo: institutionId);

    if (schoolTypeId != null && schoolTypeId.isNotEmpty) {
      query = query.where('schoolTypeId', isEqualTo: schoolTypeId);
    }

    return query.snapshots().map((snapshot) {
      final list = snapshot.docs.map((doc) => DemandModel.fromMap(doc.id, doc.data() as Map<String, dynamic>)).toList();
      
      // Tarihe göre uygulama içinde sırala (Yeni en üstte)
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      return list;
    });
  }
}
