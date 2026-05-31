import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/assessment/external_exam_message_model.dart';
import '../models/assessment/external_exam_registration_model.dart';
import 'sms_service.dart';

class ExternalExamMessagingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SmsService _smsService = SmsService();

  static const _messagesCollection = 'external_exam_messages';
  static const _registrationsCollection = 'external_exam_registrations';
  static const _emailQueueCollection = 'message_queue';

  // ─────────────── SEND MESSAGE ─────────────────────────────────────────────

  /// Mesaj gönderir: email ve/veya SMS kanalıyla
  /// Returns: {success: bool, emailCount: int, smsCount: int, message: String}
  Future<Map<String, dynamic>> sendMessage({
    required String examId,
    required String institutionId,
    required String schoolId,
    required String title,
    required String content,
    required MessageType messageType,
    required MessageChannel channel,
    required List<String> gradeLevels,
    required List<String> sessionIds,
    required bool onlyScanned,
    required String sentBy,
  }) async {
    try {
      // 1. Hedef başvuruları sorgula
      final recipients = await _getTargetRegistrations(
        examId: examId,
        gradeLevels: gradeLevels,
        sessionIds: sessionIds,
        onlyScanned: onlyScanned,
      );

      if (recipients.isEmpty) {
        return {
          'success': false,
          'message': 'Seçilen kriterlere uygun başvuru bulunamadı.',
          'emailCount': 0,
          'smsCount': 0,
        };
      }

      int emailCount = 0;
      int smsCount = 0;

      // 2. E-posta gönderimi (Firestore queue → Cloud Function)
      if (channel == MessageChannel.email || channel == MessageChannel.both) {
        final emailRecipients = recipients
            .where((r) =>
                (r.parentEmail?.isNotEmpty ?? false) ||
                (r.email?.isNotEmpty ?? false))
            .toList();

        if (emailRecipients.isNotEmpty) {
          await _queueEmails(
            recipients: emailRecipients,
            title: title,
            content: content,
            examId: examId,
          );
          emailCount = emailRecipients.length;
        }
      }

      // 3. SMS gönderimi
      if (channel == MessageChannel.sms || channel == MessageChannel.both) {
        final phones = recipients
            .map((r) => r.parentPhone)
            .where((p) => p.isNotEmpty)
            .toSet()
            .toList();

        if (phones.isNotEmpty) {
          final smsResult = await _smsService.sendSms(
            phones: phones,
            message: '$title\n\n$content',
            schoolId: schoolId,
          );

          smsCount = (smsResult['sentCount'] as int?) ?? phones.length;
          debugPrint('SMS sonuç: ${smsResult['message']}');
        }
      }

      // 4. Mesaj kaydını Firestore'a yaz
      final messageRecord = ExternalExamMessage(
        examId: examId,
        institutionId: institutionId,
        title: title,
        content: content,
        messageType: messageType,
        channel: channel,
        targetGradeLevels: gradeLevels,
        targetSessions: sessionIds,
        onlyScanned: onlyScanned,
        recipientCount: recipients.length,
        emailCount: emailCount,
        smsCount: smsCount,
        sentAt: DateTime.now(),
        createdBy: sentBy,
      );

      await _firestore
          .collection(_messagesCollection)
          .add(messageRecord.toMap());

      return {
        'success': true,
        'message': '${recipients.length} kişiye mesaj gönderildi.',
        'emailCount': emailCount,
        'smsCount': smsCount,
        'recipientCount': recipients.length,
      };
    } catch (e) {
      debugPrint('Mesaj gönderme hatası: $e');
      return {
        'success': false,
        'message': 'Gönderim hatası: $e',
        'emailCount': 0,
        'smsCount': 0,
      };
    }
  }

  // ─────────────── MESSAGE HISTORY ─────────────────────────────────────────

  Stream<List<ExternalExamMessage>> getMessageHistory(String examId) {
    return _firestore
        .collection(_messagesCollection)
        .where('examId', isEqualTo: examId)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => ExternalExamMessage.fromMap(doc.data(), doc.id))
              .toList();
          list.sort((a, b) => b.sentAt.compareTo(a.sentAt));
          return list;
        });
  }

  // ─────────────── PREVIEW COUNT ───────────────────────────────────────────

  /// Gönderim öncesi alıcı sayısını önizle
  Future<Map<String, int>> previewRecipientCount({
    required String examId,
    required List<String> gradeLevels,
    required List<String> sessionIds,
    required bool onlyScanned,
  }) async {
    try {
      final recipients = await _getTargetRegistrations(
        examId: examId,
        gradeLevels: gradeLevels,
        sessionIds: sessionIds,
        onlyScanned: onlyScanned,
      );

      final withEmail = recipients
          .where((r) =>
              (r.parentEmail?.isNotEmpty ?? false) ||
              (r.email?.isNotEmpty ?? false))
          .length;

      final withPhone = recipients
          .where((r) => r.parentPhone.isNotEmpty)
          .length;

      return {
        'total': recipients.length,
        'withEmail': withEmail,
        'withPhone': withPhone,
      };
    } catch (e) {
      debugPrint('Önizleme sayım hatası: $e');
      return {'total': 0, 'withEmail': 0, 'withPhone': 0};
    }
  }

  // ─────────────── PRIVATE HELPERS ─────────────────────────────────────────

  Future<List<ExternalExamRegistration>> _getTargetRegistrations({
    required String examId,
    required List<String> gradeLevels,
    required List<String> sessionIds,
    required bool onlyScanned,
  }) async {
    try {
      var query = _firestore
          .collection(_registrationsCollection)
          .where('examId', isEqualTo: examId);

      // Sadece 1 seans seçiliyse db bazlı filtrele
      if (sessionIds.isNotEmpty && sessionIds.length == 1) {
        query = query.where('sessionId', isEqualTo: sessionIds.first);
      }

      final snapshot = await query.get();
      var results = snapshot.docs
          .map((doc) => ExternalExamRegistration.fromMap(doc.data(), doc.id))
          .toList();

      // Sınıf filtresi (client-side)
      if (gradeLevels.isNotEmpty) {
        results = results
            .where((r) => gradeLevels.contains(r.gradeLevel))
            .toList();
      }

      // Çoklu seans filtresi (client-side)
      if (sessionIds.isNotEmpty) {
        results = results
            .where((r) => sessionIds.contains(r.sessionId))
            .toList();
      }
      
      // Yoklama alındı filtresi
      if (onlyScanned) {
        results = results.where((r) => r.isScanned == true).toList();
      }

      return results;
    } catch (e) {
      debugPrint('Hedef alıcı getirme hatası: $e');
      return [];
    }
  }

  /// E-postaları Firestore kuyruğuna yazar (Cloud Function gönderir)
  Future<void> _queueEmails({
    required List<ExternalExamRegistration> recipients,
    required String title,
    required String content,
    required String examId,
  }) async {
    final batch = _firestore.batch();

    for (final reg in recipients) {
      final emailAddress = reg.parentEmail?.isNotEmpty == true
          ? reg.parentEmail!
          : reg.email;
      if (emailAddress == null || emailAddress.isEmpty) continue;

      final docRef = _firestore.collection(_emailQueueCollection).doc();
      batch.set(docRef, {
        'to': emailAddress,
        'message': {
          'subject': title,
          'text': content,
          'html': '<p>${content.replaceAll('\n', '<br>')}</p>',
        },
        'examId': examId,
        'registrationId': reg.id,
        'recipientName': reg.parentFullName,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    debugPrint('✅ ${recipients.length} e-posta kuyruğa eklendi');
  }
}
