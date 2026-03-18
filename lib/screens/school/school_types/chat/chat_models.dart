import 'package:cloud_firestore/cloud_firestore.dart';

class ChatUser {
  final String id;
  final String name;
  final String? avatarUrl;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? userType; // 'student', 'teacher', 'staff'
  final String? role; // Detail role e.g. 'Math Teacher'

  ChatUser({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.isOnline = false,
    this.lastSeen,
    this.userType,
    this.role,
  });

  factory ChatUser.fromMap(Map<String, dynamic> data, String id) {
    return ChatUser(
      id: id,
      name: data['name'] ?? 'Unknown',
      avatarUrl: data['photoUrl'],
      isOnline: data['isOnline'] ?? false,
      lastSeen: data['lastSeen'] != null
          ? (data['lastSeen'] as Timestamp).toDate()
          : null,
    );
  }
}

class ChatMessage {
  final String id;
  final String senderId;
  final String content;
  final DateTime timestamp;
  final bool isRead;
  final MessageType type;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.content,
    required this.timestamp,
    this.isRead = false,
    this.type = MessageType.text,
    this.isStarred = false,
    this.repliedMessage,
    this.isForwarded = false,
  });

  final bool isStarred;
  final bool isForwarded;
  final ChatMessage? repliedMessage;

  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? content,
    DateTime? timestamp,
    bool? isRead,
    MessageType? type,
    bool? isStarred,
    bool? isForwarded,
    ChatMessage? repliedMessage,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      type: type ?? this.type,
      isStarred: isStarred ?? this.isStarred,
      isForwarded: isForwarded ?? this.isForwarded,
      repliedMessage: repliedMessage ?? this.repliedMessage,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'content': content,
      'timestamp': Timestamp.fromDate(timestamp),
      'isRead': isRead,
      'type': type.toString().split('.').last,
      'isStarred': isStarred,
      'isForwarded': isForwarded,
      'repliedMessage': repliedMessage?.toMap(),
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> data, String id) {
    return ChatMessage(
      id: id,
      senderId: data['senderId'] ?? '',
      content: data['content'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: data['isRead'] ?? false,
      type: MessageType.values.firstWhere(
        (e) => e.toString().split('.').last == (data['type'] ?? 'text'),
        orElse: () => MessageType.text,
      ),
      isStarred: data['isStarred'] ?? false,
      isForwarded: data['isForwarded'] ?? false,
      repliedMessage: data['repliedMessage'] != null
          ? ChatMessage.fromMap(
              data['repliedMessage'],
              '',
            ) // ID not stored in nested
          : null,
    );
  }
}

// Global state for Starrred Messages (Demo purposes)
List<ChatMessage> globalStarredMessages = [];

enum MessageType { text, image, file, audio }

class Conversation {
  final String id;
  final List<String> participantIds;
  ChatMessage? lastMessage;
  final int unreadCount;
  final Map<String, int> unreadCounts;
  final String? chatName; // For groups
  final String? chatImage;
  bool isArchived;

  Conversation({
    required this.id,
    required this.participantIds,
    this.lastMessage,
    this.unreadCount = 0,
    this.unreadCounts = const {},
    this.chatName,
    this.chatImage,
    this.isArchived = false,
  });

  List<ChatMessage> messages = [];

  Map<String, dynamic> toMap() {
    return {
      'participantIds': participantIds,
      'lastMessage': lastMessage?.toMap(),
      'unreadCount': unreadCount,
      'unreadCounts': unreadCounts,
      'chatName': chatName,
      'chatImage': chatImage,
      'isArchived': isArchived,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory Conversation.fromMap(Map<String, dynamic> data, String id) {
    Map<String, int> counts = {};
    if (data['unreadCounts'] != null) {
      (data['unreadCounts'] as Map).forEach((key, value) {
        counts[key.toString()] = value as int;
      });
    }

    return Conversation(
      id: id,
      participantIds: List<String>.from(data['participantIds'] ?? []),
      lastMessage: data['lastMessage'] != null
          ? ChatMessage.fromMap(data['lastMessage'], '')
          : null,
      unreadCount: data['unreadCount'] ?? 0,
      unreadCounts: counts,
      chatName: data['chatName'],
      chatImage: data['chatImage'],
      isArchived: data['isArchived'] ?? false,
    );
  }
}

// Global state for Conversations (Session Persistence)
List<Conversation> sessionConversations = [];
