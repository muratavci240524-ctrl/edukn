import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/survey_model.dart';
import 'announcement_service.dart';

class SurveyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AnnouncementService _announcementService = AnnouncementService();

  // Anket Oluştur
  Future<String> createSurvey(Survey survey) async {
    final ref = _firestore.collection('surveys').doc();
    // ID'yi modeldeki ID yerine yeni oluşturulan ID ile güncelle
    // Modelde zaten constructor var, ama ID'yi override etmemiz gerekebilir
    // Aslında createSurvey çağrıldığında ID boş gelebilir, burada atarız.

    final payload = survey.toMap();
    payload['id'] = ref.id; // Override ID
    payload['createdAt'] = FieldValue.serverTimestamp();

    await ref.set(payload);
    return ref.id;
  }

  // Anket Güncelle
  Future<void> updateSurvey(Survey survey) async {
    await _firestore
        .collection('surveys')
        .doc(survey.id)
        .update(survey.toMap());
  }

  // Anket Sil
  Future<void> deleteSurvey(String surveyId) async {
    await _firestore.collection('surveys').doc(surveyId).delete();
  }

  // Anket Yayınla
  Future<void> publishSurvey(String surveyId, List<String> recipients) async {
    final docRef = _firestore.collection('surveys').doc(surveyId);
    final doc = await docRef.get();
    if (!doc.exists) throw Exception('Anket bulunamadı');

    final surveyData = doc.data()!;
    final survey = Survey.fromMap(surveyData, surveyId);

    // Durumu güncelle (Eğer zaten scheduled değilse)
    // Eğer anket planlanmışsa (scheduledAt doluysa), durum 'scheduled' olmalı/kalmalı.
    // Değilse 'published' olmalı.
    final isScheduled =
        survey.scheduledAt != null &&
        survey.scheduledAt!.isAfter(DateTime.now());

    await docRef.update({
      'status': isScheduled ? 'scheduled' : 'published',
      'publishedAt': isScheduled
          ? survey.scheduledAt
          : FieldValue.serverTimestamp(),
    });

    // Duyuru oluştur

    // Planlanan tarih varsa onu kullan, yoksa şu an
    final pDate = isScheduled ? survey.scheduledAt! : DateTime.now();
    final pTime =
        '${pDate.hour.toString().padLeft(2, '0')}:${pDate.minute.toString().padLeft(2, '0')}';

    await _announcementService.saveAnnouncement(
      title: survey.title,
      content: survey.description.isEmpty
          ? 'Lütfen anketi yanıtlayınız.'
          : survey.description,
      recipients: recipients,
      publishDate: pDate,
      publishTime: pTime,
      links: [
        {'name': 'Ankete Git', 'url': 'internal://survey/$surveyId'},
      ],
      schoolTypeId: survey.schoolTypeId,
    );
  }

  // Anketi Kapat
  Future<void> closeSurvey(String surveyId) async {
    await _firestore.collection('surveys').doc(surveyId).update({
      'status': 'closed',
      'closedAt': FieldValue.serverTimestamp(),
    });
  }

  // Zamanlanmış anketleri kontrol et ve yayınla
  Future<void> checkScheduledSurveys(String institutionId) async {
    final now = DateTime.now();
    final snapshot = await _firestore
        .collection('surveys')
        .where('institutionId', isEqualTo: institutionId)
        .where('status', isEqualTo: 'scheduled')
        .get();

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final scheduledAt = (data['scheduledAt'] as Timestamp?)?.toDate();
      if (scheduledAt != null && scheduledAt.isBefore(now)) {
        await doc.reference.update({
          'status': 'published',
          'publishedAt': scheduledAt,
        });
      }
    }
  }

  // Anketleri Getir (Institution ID'ye göre)
  // Stream içinde otomatik kontrol yok, UI tarafında initState'de çağrılmalı.
  Stream<List<Survey>> getSurveys(String institutionId) {
    return _firestore
        .collection('surveys')
        .where('institutionId', isEqualTo: institutionId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Survey.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  // Anketleri Filtreli Getir (Öğretmenler için)
  Stream<List<Survey>> getFilteredSurveys({
    required String institutionId,
    String? authorId,
    List<String>? targetedClassIds,
  }) {
    // Firestore supports multiple 'where' but 'orderBy' must be consistent.
    // Given the complexity of OR logic (author OR class), we'll do a broader fetch and filter in map.
    return _firestore
        .collection('surveys')
        .where('institutionId', isEqualTo: institutionId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) => Survey.fromMap(doc.data(), doc.id)).toList();
      
      if (authorId == null && targetedClassIds == null) return list;

      return list.where((survey) {
        // 1. I authored it
        if (authorId != null && survey.authorId == authorId) return true;

        // 2. Targets my classes
        if (targetedClassIds != null && targetedClassIds.isNotEmpty) {
           if (survey.targetType == SurveyTargetType.specific_classes) {
             return survey.targetIds.any((id) => targetedClassIds.contains(id));
           }
        }
        
        // 3. Targets all teachers (if I am a teacher)
        if (authorId != null && (survey.targetType == SurveyTargetType.teachers || survey.targetType == SurveyTargetType.all)) {
           return true; 
        }

        return false;
      }).toList();
    });
  }

  // Tek bir anket getir
  Future<Survey?> getSurvey(String surveyId) async {
    final doc = await _firestore.collection('surveys').doc(surveyId).get();
    if (!doc.exists) return null;
    return Survey.fromMap(doc.data()!, doc.id);
  }

  // Kullanıcının anket yanıtını getir
  Future<Map<String, dynamic>?> getUserResponse(
    String surveyId,
    String userId,
  ) async {
    final snapshot = await _firestore
        .collection('survey_responses')
        .where('surveyId', isEqualTo: surveyId)
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return snapshot.docs.first.data();
  }

  // Anket Yanıtla (Varsa güncelle, yoksa ekle)
  Future<void> submitResponse(
    String surveyId,
    Map<String, dynamic> answers,
  ) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Kullanıcı oturumu yok');

    // Check if exists
    final existingParams = await _firestore
        .collection('survey_responses')
        .where('surveyId', isEqualTo: surveyId)
        .where('userId', isEqualTo: uid)
        .limit(1)
        .get();

    if (existingParams.docs.isNotEmpty) {
      // Update
      final docId = existingParams.docs.first.id;
      await _firestore.collection('survey_responses').doc(docId).update({
        'answers': answers,
        'submittedAt': FieldValue.serverTimestamp(),
      });
      // Do NOT increment responseCount again if updating
    } else {
      // Insert
      final responsePayload = {
        'surveyId': surveyId,
        'userId': uid,
        'answers': answers,
        'submittedAt': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('survey_responses').add(responsePayload);

      // Anket istatistiğini güncelle (increment responseCount)
      await _firestore.collection('surveys').doc(surveyId).update({
        'responseCount': FieldValue.increment(1),
      });
    }
  }

  // Anket Yanıtlarını Getir (İstatistik için)
  Future<List<Map<String, dynamic>>> getSurveyResponses(String surveyId) async {
    final snapshot = await _firestore
        .collection('survey_responses')
        .where('surveyId', isEqualTo: surveyId)
        .get();

    return snapshot.docs.map((d) => d.data()).toList();
  }
}
