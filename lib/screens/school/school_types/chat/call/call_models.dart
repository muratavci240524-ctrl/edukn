import 'package:cloud_firestore/cloud_firestore.dart';

enum CallType { voice, video }
enum CallStatus { ringing, accepted, rejected, ended }

class CallSession {
  final String id;
  final String callerId;
  final String callerName;
  final String? callerRole;
  final String? callerAvatar;
  final String receiverId;
  final String receiverName;
  final String? receiverRole;
  final String? receiverAvatar;
  final CallType callType;
  final CallStatus status;
  final DateTime createdAt;

  CallSession({
    required this.id,
    required this.callerId,
    required this.callerName,
    this.callerRole,
    this.callerAvatar,
    required this.receiverId,
    required this.receiverName,
    this.receiverRole,
    this.receiverAvatar,
    required this.callType,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'callerId': callerId,
      'callerName': callerName,
      'callerRole': callerRole,
      'callerAvatar': callerAvatar,
      'receiverId': receiverId,
      'receiverName': receiverName,
      'receiverRole': receiverRole,
      'receiverAvatar': receiverAvatar,
      'callType': callType.toString().split('.').last,
      'status': status.toString().split('.').last,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory CallSession.fromMap(Map<String, dynamic> data, String id) {
    return CallSession(
      id: id,
      callerId: data['callerId'] ?? '',
      callerName: data['callerName'] ?? 'Bilinmeyen Kullanıcı',
      callerRole: data['callerRole'],
      callerAvatar: data['callerAvatar'],
      receiverId: data['receiverId'] ?? '',
      receiverName: data['receiverName'] ?? 'Bilinmeyen Kullanıcı',
      receiverRole: data['receiverRole'],
      receiverAvatar: data['receiverAvatar'],
      callType: data['callType'] == 'video' ? CallType.video : CallType.voice,
      status: CallStatus.values.firstWhere(
        (e) => e.toString().split('.').last == (data['status'] ?? 'ringing'),
        orElse: () => CallStatus.ringing,
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  CallSession copyWith({
    String? id,
    String? callerId,
    String? callerName,
    String? callerRole,
    String? callerAvatar,
    String? receiverId,
    String? receiverName,
    String? receiverRole,
    String? receiverAvatar,
    CallType? callType,
    CallStatus? status,
    DateTime? createdAt,
  }) {
    return CallSession(
      id: id ?? this.id,
      callerId: callerId ?? this.callerId,
      callerName: callerName ?? this.callerName,
      callerRole: callerRole ?? this.callerRole,
      callerAvatar: callerAvatar ?? this.callerAvatar,
      receiverId: receiverId ?? this.receiverId,
      receiverName: receiverName ?? this.receiverName,
      receiverRole: receiverRole ?? this.receiverRole,
      receiverAvatar: receiverAvatar ?? this.receiverAvatar,
      callType: callType ?? this.callType,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
