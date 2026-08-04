import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../screens/school/school_types/chat/chat_models.dart';
import '../screens/school/school_types/chat/settings/chat_settings_dialog.dart';
import 'term_service.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;
  String? get currentUserEmail => _auth.currentUser?.email;

  /// Dinamik Veli - Öğretmen Mesai Saatleri Kontrolü
  /// Yöneticiler (Müdür, Müdür Yrd, Genel Müdür) 7/24 mesajlaşabilir.
  bool isWithinWorkingHours({bool isAdminOrManager = false}) {
    if (isAdminOrManager) return true; // Yöneticiler 7/24 muaf

    final now = DateTime.now();
    // Hafta sonu izni
    if (!globalChatSettings.allowWeekendMessaging) {
      if (now.weekday == DateTime.sunday || now.weekday == DateTime.saturday) {
        return false;
      }
    }

    final currentMinutes = now.hour * 60 + now.minute;
    final startMinutes = globalChatSettings.startWorkingTime.hour * 60 +
        globalChatSettings.startWorkingTime.minute;
    final endMinutes = globalChatSettings.endWorkingTime.hour * 60 +
        globalChatSettings.endWorkingTime.minute;

    return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
  }

  /// Yönetici Kontrolü (Silme yetkisi ve 7/24 iletişim için)
  bool isManagerRole(String roleOrType) {
    if (roleOrType.isEmpty) return true;
    final lower = TurkishStringUtils.toLowerTr(roleOrType);
    return lower.contains('admin') ||
        lower.contains('manager') ||
        lower.contains('yonetici') ||
        lower.contains('yönetici') ||
        lower.contains('genel müdür') ||
        lower.contains('genel mudur') ||
        lower.contains('mudur') ||
        lower.contains('müdür') ||
        lower.contains('principal');
  }

  /// Mesaj Silme (SADECE Yöneticiler Silebilir!)
  Future<bool> deleteMessage({
    required String conversationId,
    required String messageId,
    required String userRole,
  }) async {
    if (!isManagerRole(userRole)) {
      debugPrint("❌ Yetkisiz mesaj silme denemesi: Sadece yöneticiler silebilir.");
      return false;
    }

    try {
      await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId)
          .delete();
      return true;
    } catch (e) {
      debugPrint("Mesaj silinirken hata: $e");
      return false;
    }
  }

  /// Mesaj Düzenleme (Kendi mesajını düzenle — 10 dk içinde)
  Future<bool> editMessage({
    required String conversationId,
    required String messageId,
    required String newContent,
  }) async {
    try {
      await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId)
          .update({
        'content': newContent,
        'isEdited': true,
      });
      return true;
    } catch (e) {
      debugPrint("Mesaj düzenlenirken hata: $e");
      return false;
    }
  }

  // Stream of conversations for current user
  Stream<List<Conversation>> getConversations([String? userId]) {
    final uid = userId ?? currentUserId;
    if (uid == null) return const Stream.empty();

    return Stream.fromFuture(TermService().getSelectedTermId()).asyncExpand((termId) {
      Query query = _firestore.collection('conversations').where('participantIds', arrayContains: uid);
      
      if (termId != null && termId.isNotEmpty) {
        query = query.where('termId', isEqualTo: termId);
      }

      return query.snapshots().map((snapshot) {
        final list = snapshot.docs.map((doc) {
          return Conversation.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        }).toList();

        // Sıralama: En son güncellenen en üstte
        list.sort((a, b) {
          final aTime = a.lastMessage?.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.lastMessage?.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });

        return list;
      });
    });
  }

  // Stream of messages for a conversation
  Stream<List<ChatMessage>> getMessages(String conversationId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return ChatMessage.fromMap(doc.data(), doc.id);
      }).toList();
    });
  }

  // Send a message
  Future<void> sendMessage(String conversationId, ChatMessage message) async {
    final messageRef = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc();

    final convDoc = await _firestore.collection('conversations').doc(conversationId).get();
    final participants = List<String>.from(convDoc.data()?['participantIds'] ?? []);

    final messageData = message.toMap();
    messageData['participants'] = participants; // Cloud Function notification için gerekli

    await messageRef.set(messageData);

    Map<String, dynamic> updates = {
      'lastMessage': message.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'unreadCount': FieldValue.increment(1),
    };

    for (final pId in participants) {
      if (pId != message.senderId) {
        updates['unreadCounts.$pId'] = FieldValue.increment(1);
      }
    }

    await _firestore.collection('conversations').doc(conversationId).update(updates);
  }

  // Mark as read
  Future<void> markAsRead(String conversationId) async {
    final uid = currentUserId;
    if (uid == null) return;

    await _firestore.collection('conversations').doc(conversationId).update({
      'unreadCounts.$uid': 0,
    });
  }

  // Create or Get Conversation
  Future<String> createConversation(List<String> participantIds, {bool isGroup = false, String? groupName}) async {
    final termId = await TermService().getActiveTermId();
    if (participantIds.length == 2 && !isGroup) {
      final sortedIds = List<String>.from(participantIds)..sort();
      final docId = termId != null && termId.isNotEmpty 
          ? '${sortedIds.join('_')}_$termId' 
          : sortedIds.join('_');
      final docRef = _firestore.collection('conversations').doc(docId);

      final doc = await docRef.get();
      if (doc.exists) {
        return docId;
      }

      final conversation = Conversation(
        id: docId,
        participantIds: participantIds,
        unreadCount: 0,
        isGroup: false,
        termId: termId,
      );

      await docRef.set(conversation.toMap());
      return docId;
    }

    final docRef = _firestore.collection('conversations').doc();
    final conversation = Conversation(
      id: docRef.id,
      participantIds: participantIds,
      unreadCount: 0,
      isGroup: true,
      chatName: groupName ?? 'Yeni Grup',
      termId: termId,
    );

    await docRef.set(conversation.toMap());
    return docRef.id;
  }

  // Archive/Unarchive
  Future<void> toggleArchive(String conversationId, bool isArchived) async {
    await _firestore.collection('conversations').doc(conversationId).update({
      'isArchived': isArchived,
    });
  }

  /// Yıldızlama / Yıldız Kaldırma (Firestore Sync)
  Future<void> toggleStarMessage(String conversationId, String messageId, bool isStarred) async {
    try {
      await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId)
          .update({
        'isStarred': isStarred,
      });
    } catch (e) {
      debugPrint("Yıldızlama hatası: $e");
    }
  }
}
