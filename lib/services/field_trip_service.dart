import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/field_trip_model.dart';
import '../models/survey_model.dart';
import 'survey_service.dart';

class FieldTripService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SurveyService _surveyService = SurveyService();

  Future<String> createFieldTrip(FieldTrip trip) async {
    final ref = _firestore.collection('field_trips').doc();
    await ref.set(trip.toMap());

    // If participation survey is needed, we should probably create it here or call a separate method.
    // However, the SurveyService.createSurvey creates a document.
    // The user flow implies creating the trip first, then maybe the survey is auto-created or created as part of the flow.
    // We will handle survey creation in the UI or a higher level controller, but we can have helper here.

    return ref.id;
  }

  Future<void> updateFieldTrip(FieldTrip trip) async {
    await _firestore
        .collection('field_trips')
        .doc(trip.id)
        .update(trip.toMap());
  }

  Future<void> deleteFieldTrip(String id) async {
    await _firestore.collection('field_trips').doc(id).delete();
  }

  Stream<List<FieldTrip>> getFieldTrips(
    String institutionId,
    String schoolTypeId,
  ) {
    return _firestore
        .collection('field_trips')
        .where('institutionId', isEqualTo: institutionId)
        .where('schoolTypeId', isEqualTo: schoolTypeId)
        .snapshots()
        .map((snapshot) {
          final trips = snapshot.docs
              .map((doc) => FieldTrip.fromMap(doc.data(), doc.id))
              .toList();
          trips.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return trips;
        });
  }

  Future<FieldTrip?> getFieldTrip(String id) async {
    final doc = await _firestore.collection('field_trips').doc(id).get();
    if (!doc.exists) return null;
    return FieldTrip.fromMap(doc.data()!, doc.id);
  }

  // Toggle Payment Status
  Future<void> togglePaymentStatus(
    String tripId,
    String studentId,
    bool isPaid,
  ) async {
    final docRef = _firestore.collection('field_trips').doc(tripId);

    // Use dot notation to update specific map field
    await docRef.update({'paymentStatus.$studentId': isPaid});
  }

  // Create Participation Survey Helper
  Future<String> createParticipationSurvey(
    FieldTrip trip,
    DateTime publishDate,
  ) async {
    // Create generic questions
    final questions = [
      SurveyQuestion(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: 'Bu geziye katılmayı onaylıyor musunuz? (${trip.name})',
        type: SurveyQuestionType.singleChoice,
        isRequired: true,
        options: ['Evet, katılıyorum', 'Hayır, katılmıyorum'],
      ),
    ];

    if (trip.isPaid) {
      questions.add(
        SurveyQuestion(
          id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
          text:
              'Gezi ücreti olan ${trip.amount} TL ödemeyi kabul ediyor musunuz?',
          type: SurveyQuestionType.singleChoice,
          isRequired: true,
          options: ['Evet, kabul ediyorum', 'Hayır'],
        ),
      );
    }

    final section = SurveySection(
      id: 'main',
      title: 'Gezi Katılım',
      questions: questions,
    );

    final survey = Survey(
      id: '', // Will be set by service
      institutionId: trip.institutionId,
      schoolTypeId: trip.schoolTypeId,
      title: '${trip.name} - Katılım Anketi',
      description:
          'Gezi Amacı: ${trip.purpose}\nHareket: ${trip.departureTime.toString().substring(0, 16)}\nDönüş: ${trip.returnTime.toString().substring(0, 16)}',
      authorId: trip.authorId,
      createdAt: DateTime.now(),
      status: SurveyStatus.draft, // Will be scheduled or published
      targetType: SurveyTargetType
          .students, // We will manually target specific students via announcement
      targetIds:
          trip.targetBranchIds, // Store branch IDs as target IDs generally
      sections: [section],
      scheduledAt: publishDate,
    );

    final surveyId = await _surveyService.createSurvey(survey);

    // Update Field Trip with Survey ID
    await updateFieldTrip(
      FieldTrip(
        id: trip.id,
        institutionId: trip.institutionId,
        schoolTypeId: trip.schoolTypeId,
        schoolTypeName: trip.schoolTypeName,
        name: trip.name,
        purpose: trip.purpose,
        departureTime: trip.departureTime,
        returnTime: trip.returnTime,
        classLevel: trip.classLevel,
        targetBranchIds: trip.targetBranchIds,
        targetStudentIds: trip.targetStudentIds,
        totalStudents: trip.totalStudents,
        participationSurveyId: surveyId, // Link
        surveyPublishDate: publishDate,
        isPaid: trip.isPaid,
        amount: trip.amount,
        paymentStatus: trip.paymentStatus,
        feedbackSurveyId: trip.feedbackSurveyId,
        authorId: trip.authorId,
        createdAt: trip.createdAt,
        status: trip.status,
      ),
    );

    // Schedule Publication?
    if (publishDate.isAfter(DateTime.now())) {
      // SurveyService checkScheduledSurveys handles this globally usually?
      // Or we set status to scheduled.
      await _firestore.collection('surveys').doc(surveyId).update({
        'status': 'scheduled',
        'scheduledAt': Timestamp.fromDate(publishDate),
      });
    } else {
      // Publish Immediately
      await _surveyService.publishSurvey(surveyId, trip.targetStudentIds);
    }

    return surveyId;
  }
}
