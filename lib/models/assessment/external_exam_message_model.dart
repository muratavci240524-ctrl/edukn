import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { duyuru, guncelleme, bilgilendirme, hatirlatma }

enum MessageChannel { email, sms, both }

class ExternalExamMessage {
  final String? id;
  final String examId;
  final String institutionId;
  final String title;
  final String content;
  final MessageType messageType;
  final MessageChannel channel;
  final List<String> targetGradeLevels; // empty = all grades
  final List<String> targetSessions;    // empty = all sessions
  final bool onlyScanned;               // whether it was filtered by scanned only
  final int recipientCount;
  final int emailCount;
  final int smsCount;
  final DateTime sentAt;
  final String createdBy;

  const ExternalExamMessage({
    this.id,
    required this.examId,
    required this.institutionId,
    required this.title,
    required this.content,
    required this.messageType,
    required this.channel,
    required this.targetGradeLevels,
    required this.targetSessions,
    required this.onlyScanned,
    required this.recipientCount,
    required this.emailCount,
    required this.smsCount,
    required this.sentAt,
    required this.createdBy,
  });

  String get messageTypeName {
    switch (messageType) {
      case MessageType.duyuru:
        return 'Duyuru';
      case MessageType.guncelleme:
        return 'Güncelleme';
      case MessageType.bilgilendirme:
        return 'Bilgilendirme';
      case MessageType.hatirlatma:
        return 'Hatırlatma';
    }
  }

  String get messageTypeEmoji {
    switch (messageType) {
      case MessageType.duyuru:
        return '📢';
      case MessageType.guncelleme:
        return '🔄';
      case MessageType.bilgilendirme:
        return 'ℹ️';
      case MessageType.hatirlatma:
        return '🔔';
    }
  }

  String get channelName {
    switch (channel) {
      case MessageChannel.email:
        return 'E-posta';
      case MessageChannel.sms:
        return 'SMS';
      case MessageChannel.both:
        return 'E-posta + SMS';
    }
  }

  String get targetSummary {
    if (targetGradeLevels.isEmpty) return 'Tüm Başvurular';
    return '${targetGradeLevels.join(', ')}. Sınıflar';
  }

  static MessageType _typeFromString(String? s) {
    switch (s) {
      case 'guncelleme':
        return MessageType.guncelleme;
      case 'bilgilendirme':
        return MessageType.bilgilendirme;
      case 'hatirlatma':
        return MessageType.hatirlatma;
      default:
        return MessageType.duyuru;
    }
  }

  static String _typeToString(MessageType t) {
    switch (t) {
      case MessageType.duyuru:
        return 'duyuru';
      case MessageType.guncelleme:
        return 'guncelleme';
      case MessageType.bilgilendirme:
        return 'bilgilendirme';
      case MessageType.hatirlatma:
        return 'hatirlatma';
    }
  }

  static MessageChannel _channelFromString(String? s) {
    switch (s) {
      case 'sms':
        return MessageChannel.sms;
      case 'both':
        return MessageChannel.both;
      default:
        return MessageChannel.email;
    }
  }

  static String _channelToString(MessageChannel c) {
    switch (c) {
      case MessageChannel.email:
        return 'email';
      case MessageChannel.sms:
        return 'sms';
      case MessageChannel.both:
        return 'both';
    }
  }

  Map<String, dynamic> toMap() => {
        'examId': examId,
        'institutionId': institutionId,
        'title': title,
        'content': content,
        'messageType': _typeToString(messageType),
        'channel': _channelToString(channel),
        'targetGradeLevels': targetGradeLevels,
        'targetSessions': targetSessions,
        'onlyScanned': onlyScanned,
        'recipientCount': recipientCount,
        'emailCount': emailCount,
        'smsCount': smsCount,
        'sentAt': Timestamp.fromDate(sentAt),
        'createdBy': createdBy,
      };

  factory ExternalExamMessage.fromMap(
    Map<String, dynamic> map,
    String id,
  ) =>
      ExternalExamMessage(
        id: id,
        examId: map['examId'] ?? '',
        institutionId: map['institutionId'] ?? '',
        title: map['title'] ?? '',
        content: map['content'] ?? '',
        messageType: _typeFromString(map['messageType']),
        channel: _channelFromString(map['channel']),
        targetGradeLevels:
            List<String>.from(map['targetGradeLevels'] ?? []),
        targetSessions: List<String>.from(map['targetSessions'] ?? []),
        onlyScanned: map['onlyScanned'] ?? false,
        recipientCount: map['recipientCount'] ?? 0,
        emailCount: map['emailCount'] ?? 0,
        smsCount: map['smsCount'] ?? 0,
        sentAt: (map['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        createdBy: map['createdBy'] ?? '',
      );
}
