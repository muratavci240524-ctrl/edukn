import 'package:cloud_firestore/cloud_firestore.dart';

/// Türkçe Karakter ve Sıralama (Collation) Yardımcı Sınıfı
class TurkishStringUtils {
  static String toLowerTr(String input) {
    return input
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .replaceAll('Ğ', 'ğ')
        .replaceAll('Ü', 'ü')
        .replaceAll('Ş', 'ş')
        .replaceAll('Ö', 'ö')
        .replaceAll('Ç', 'ç')
        .toLowerCase();
  }

  /// Türkçe karakterleri aramalar için İngilizce harflere normalize eder
  /// (Ör: "anıl" -> "anil", "İSMAİL" -> "ismail")
  static String normalizeForSearch(String input) {
    return input
        .replaceAll('İ', 'i')
        .replaceAll('I', 'i')
        .replaceAll('ı', 'i')
        .replaceAll('Ğ', 'g')
        .replaceAll('ğ', 'g')
        .replaceAll('Ü', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('Ş', 's')
        .replaceAll('ş', 's')
        .replaceAll('Ö', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('Ç', 'c')
        .replaceAll('ç', 'c')
        .toLowerCase();
  }

  /// Türkçe Alfabeye göre karşılaştırma (Alphabetical Collation)
  /// A, B, C, Ç, D, E, F, G, Ğ, H, I, İ, J, K, L, M, N, O, Ö, P, R, S, Ş, T, U, Ü, V, Y, Z
  static int compareTr(String a, String b) {
    final aLower = toLowerTr(a);
    final bLower = toLowerTr(b);

    final minLen = aLower.length < bLower.length ? aLower.length : bLower.length;
    for (int i = 0; i < minLen; i++) {
      final charA = aLower[i];
      final charB = bLower[i];
      if (charA != charB) {
        final weightA = _charWeight(charA);
        final weightB = _charWeight(charB);
        return weightA.compareTo(weightB);
      }
    }
    return aLower.length.compareTo(bLower.length);
  }

  static int _charWeight(String char) {
    switch (char) {
      case 'a': return 1;
      case 'b': return 2;
      case 'c': return 3;
      case 'ç': return 4;
      case 'd': return 5;
      case 'e': return 6;
      case 'f': return 7;
      case 'g': return 8;
      case 'ğ': return 9;
      case 'h': return 10;
      case 'ı': return 11;
      case 'i': return 12;
      case 'j': return 13;
      case 'k': return 14;
      case 'l': return 15;
      case 'm': return 16;
      case 'n': return 17;
      case 'o': return 18;
      case 'ö': return 19;
      case 'p': return 20;
      case 'r': return 21;
      case 's': return 22;
      case 'ş': return 23;
      case 't': return 24;
      case 'u': return 25;
      case 'ü': return 26;
      case 'v': return 27;
      case 'y': return 28;
      case 'z': return 29;
      default: return char.codeUnitAt(0) + 100;
    }
  }
}

class ChatUser {
  final String id;
  final String name;
  final String? email;
  final String? avatarUrl;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? userType; // 'student', 'parent', 'teacher', 'admin', 'principal', 'staff'
  final String? role; // Detay rol e.g. 'Matematik Öğretmeni', 'Müdür Yardımcısı'
  final String? schoolTypeId;
  final String? motherName;
  final String? motherPhone;
  final String? fatherName;
  final String? fatherPhone;
  final List<String> classIds;
  final List<String> teacherIds; // Öğrencinin öğretmen id'leri
  final List<String> studentIds; // Öğretmenin öğrenci id'leri

  ChatUser({
    required this.id,
    required this.name,
    this.email,
    this.avatarUrl,
    this.isOnline = false,
    this.lastSeen,
    this.userType,
    this.role,
    this.schoolTypeId,
    this.motherName,
    this.motherPhone,
    this.fatherName,
    this.fatherPhone,
    this.classIds = const [],
    this.teacherIds = const [],
    this.studentIds = const [],
  });

  factory ChatUser.fromMap(Map<String, dynamic> data, String id) {
    final name = data['name'] ??
        data['fullName'] ??
        data['displayName'] ??
        'İsimsiz Kullanıcı';
    return ChatUser(
      id: id,
      name: name,
      email: data['email'],
      avatarUrl: data['photoUrl'] ?? data['avatarUrl'],
      isOnline: data['isOnline'] ?? false,
      lastSeen: data['lastSeen'] != null
          ? (data['lastSeen'] as Timestamp).toDate()
          : null,
      userType: data['userType'] ?? data['role'] ?? 'user',
      role: () {
        final title = data['title']?.toString();
        final roleTitle = data['roleTitle']?.toString();
        final role = data['role']?.toString();
        final userType = data['userType']?.toString();
        
        final lowerValues = [title?.toLowerCase(), roleTitle?.toLowerCase(), role?.toLowerCase(), userType?.toLowerCase()];
        
        for (var v in lowerValues) {
          if (v == null) continue;
          if (v.contains('genel müdür') || v == 'genel_mudur') return 'Genel Müdür';
          if (v == 'müdür' || v == 'mudur' || v == 'okul müdürü') return 'Müdür';
          if (v == 'müdür yardımcısı' || v == 'mudur_yardimcisi' || v.contains('müdür yardımcısı')) return 'Müdür Yardımcısı';
          if (v == 'admin' || v == 'kurum yöneticisi') return 'Yönetici';
        }
        
        return roleTitle ?? role ?? title;
      }(),
      schoolTypeId: data['schoolTypeId'],
      motherName: data['motherName'] ?? data['anneAdi'],
      motherPhone: data['motherPhone'] ?? data['anneTel'],
      fatherName: data['fatherName'] ?? data['babaAdi'],
      fatherPhone: data['fatherPhone'] ?? data['babaTel'],
      classIds: List<String>.from(data['classIds'] ?? []),
      teacherIds: List<String>.from(data['teacherIds'] ?? []),
      studentIds: List<String>.from(data['studentIds'] ?? []),
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
  final String? recipientChannel; // 'student', 'mother', 'father'

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
    this.isEdited = false,
    this.recipientChannel,
  });

  final bool isStarred;
  final bool isForwarded;
  final bool isEdited;
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
    bool? isEdited,
    ChatMessage? repliedMessage,
    String? recipientChannel,
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
      isEdited: isEdited ?? this.isEdited,
      repliedMessage: repliedMessage ?? this.repliedMessage,
      recipientChannel: recipientChannel ?? this.recipientChannel,
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
      'isEdited': isEdited,
      'repliedMessage': repliedMessage?.toMap(),
      'recipientChannel': recipientChannel,
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
      isEdited: data['isEdited'] ?? false,
      repliedMessage: data['repliedMessage'] != null
          ? ChatMessage.fromMap(
              data['repliedMessage'],
              '',
            )
          : null,
      recipientChannel: data['recipientChannel'],
    );
  }
}

// Global state for Starrred Messages (Demo purposes)
List<ChatMessage> globalStarredMessages = [];

enum MessageType { text, image, file, audio, call }

class Conversation {
  final String id;
  final List<String> participantIds;
  ChatMessage? lastMessage;
  final int unreadCount;
  final Map<String, int> unreadCounts;
  final String? chatName; // For groups
  final String? chatImage;
  bool isArchived;
  bool isPinned;
  final bool isGroup;
  final String? termId;

  Conversation({
    required this.id,
    required this.participantIds,
    this.lastMessage,
    this.unreadCount = 0,
    this.unreadCounts = const {},
    this.chatName,
    this.chatImage,
    this.isArchived = false,
    this.isPinned = false,
    this.isGroup = false,
    this.termId,
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
      'isPinned': isPinned,
      'isGroup': isGroup,
      'termId': termId,
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
      isPinned: data['isPinned'] ?? false,
      isGroup: data['isGroup'] ?? false,
      termId: data['termId'],
    );
  }
}

// Global state for Conversations (Session Persistence)
List<Conversation> sessionConversations = [];
