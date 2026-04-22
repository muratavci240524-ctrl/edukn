import 'package:cloud_firestore/cloud_firestore.dart';

enum DemandStatus {
  open,        // Açık
  pending,     // Beklemede
  inProgress,  // İşlemde
  completed,   // Tamamlandı
  cancelled    // İptal Edildi
}

enum DemandPriority {
  low,
  medium,
  high,
  urgent
}

class DemandModel {
  final String id;
  final String institutionId;
  final String schoolTypeId;
  final String termId;
  
  final String senderUid;
  final String senderName;
  final String senderRole; // admin, teacher, parent, student
  
  final List<String> receiverUids; // Birden fazla alıcı desteği
  final List<String> receiverNames;
  
  final String? studentUid;
  final String? studentName;
  final String? studentClassName;
  
  final String title;
  final String description;
  final String category; // Akademik, Disiplin, Rehberlik, Sosyal, Diğer
  final DemandPriority priority;
  final DemandStatus status;
  
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? closedAt;
  final String? closingNote;
  final String? closerUid;
  final String? closerName;

  DemandModel({
    required this.id,
    required this.institutionId,
    required this.schoolTypeId,
    required this.termId,
    required this.senderUid,
    required this.senderName,
    required this.senderRole,
    this.receiverUids = const [],
    this.receiverNames = const [],
    this.studentUid,
    this.studentName,
    this.studentClassName,
    required this.title,
    required this.description,
    required this.category,
    this.priority = DemandPriority.medium,
    this.status = DemandStatus.open,
    required this.createdAt,
    this.updatedAt,
    this.closedAt,
    this.closingNote,
    this.closerUid,
    this.closerName,
  });

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'schoolTypeId': schoolTypeId,
      'termId': termId,
      'senderUid': senderUid,
      'senderName': senderName,
      'senderRole': senderRole,
      'receiverUids': receiverUids,
      'receiverNames': receiverNames,
      'studentUid': studentUid,
      'studentName': studentName,
      'studentClassName': studentClassName,
      'title': title,
      'description': description,
      'category': category,
      'priority': priority.name,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'closedAt': closedAt != null ? Timestamp.fromDate(closedAt!) : null,
      'closingNote': closingNote,
      'closerUid': closerUid,
      'closerName': closerName,
    };
  }

  factory DemandModel.fromMap(String id, Map<String, dynamic> map) {
    return DemandModel(
      id: id,
      institutionId: map['institutionId'] ?? '',
      schoolTypeId: map['schoolTypeId'] ?? '',
      termId: map['termId'] ?? '',
      senderUid: map['senderUid'] ?? '',
      senderName: map['senderName'] ?? '',
      senderRole: map['senderRole'] ?? '',
      receiverUids: List<String>.from(map['receiverUids'] ?? []),
      receiverNames: List<String>.from(map['receiverNames'] ?? []),
      studentUid: map['studentUid'],
      studentName: map['studentName'],
      studentClassName: map['studentClassName'],
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      category: map['category'] ?? 'Diğer',
      priority: DemandPriority.values.firstWhere(
        (e) => e.name == (map['priority'] ?? 'medium'),
        orElse: () => DemandPriority.medium,
      ),
      status: DemandStatus.values.firstWhere(
        (e) => e.name == (map['status'] ?? 'open'),
        orElse: () => DemandStatus.open,
      ),
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      closedAt: (map['closedAt'] as Timestamp?)?.toDate(),
      closingNote: map['closingNote'],
      closerUid: map['closerUid'],
      closerName: map['closerName'],
    );
  }
}
