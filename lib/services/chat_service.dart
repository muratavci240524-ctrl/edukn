import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/school/school_types/chat/chat_models.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  // Stream of conversations for current user
  Stream<List<Conversation>> getConversations([String? userId]) {
    final uid = userId ?? currentUserId;
    if (uid == null) return const Stream.empty();

    return _firestore
        .collection('conversations')
        .where('participantIds', arrayContains: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return Conversation.fromMap(doc.data(), doc.id);
          }).toList();
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
    // 1. Add to messages collection
    final messageRef = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(); // Auto-ID

    // Use transaction/batch if needed, but simple writes are fine for MVP
    await messageRef.set(message.toMap());

    // 2. Update conversation lastMessage
    await _firestore.collection('conversations').doc(conversationId).update({
      'lastMessage': message.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'unreadCount': FieldValue.increment(1), // TODO: logic per user
    });
  }

  // Create or Get Conversation
  Future<String> createConversation(List<String> participantIds) async {
    // For 1-on-1 chats, use deterministic ID to prevent duplicates
    if (participantIds.length == 2) {
      final sortedIds = List<String>.from(participantIds)..sort();
      final docId = sortedIds.join('_');
      final docRef = _firestore.collection('conversations').doc(docId);

      final doc = await docRef.get();
      if (doc.exists) {
        return docId;
      }

      // Create new if not exists
      final conversation = Conversation(
        id: docId,
        participantIds: participantIds,
        unreadCount: 0,
        // chatName/image handled by UI usually or derived from participants
      );

      await docRef.set(conversation.toMap());
      return docId;
    }

    // For Groups or other cases, use Auto ID
    final docRef = _firestore.collection('conversations').doc();
    final conversation = Conversation(
      id: docRef.id,
      participantIds: participantIds,
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
}

extension on Conversation {
  // Helper for constructor mismatch with toMap logic
  // toMap uses FieldValue, so we can't fully construct locally for initial saving properly without helper
  // But standard constructor is fine for local objects before saving.
}
