import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Öğrenci Hareket / Pusula Türleri (Geç - İzin - Erken Alma - Revir - Görüşme)
enum StudentMovementType {
  lateSlip, // Geç Kağıdı
  exitPermission, // Çıkış İzni (Güvenlik Kapı Onaylı)
  earlyPickup, // Veli Erken Alma & "Okula Geldim" Bildirimi
  infirmary, // Revir Sevk & Sağlık İşlemi
  interview, // Rehberlik / İdare / Öğretmen Görüşmesi
}

extension StudentMovementTypeExt on StudentMovementType {
  String get firestoreKey {
    switch (this) {
      case StudentMovementType.lateSlip:
        return 'late';
      case StudentMovementType.exitPermission:
        return 'exit_permission';
      case StudentMovementType.earlyPickup:
        return 'early_pickup';
      case StudentMovementType.infirmary:
        return 'infirmary';
      case StudentMovementType.interview:
        return 'interview';
    }
  }

  static StudentMovementType fromKey(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'exit_permission':
      case 'exit':
      case 'izin':
        return StudentMovementType.exitPermission;
      case 'early_pickup':
      case 'erken_alma':
      case 'erken':
        return StudentMovementType.earlyPickup;
      case 'infirmary':
      case 'revir':
        return StudentMovementType.infirmary;
      case 'interview':
      case 'gorusme':
        return StudentMovementType.interview;
      case 'late':
      case 'gec':
      default:
        return StudentMovementType.lateSlip;
    }
  }

  String get shortLabel {
    switch (this) {
      case StudentMovementType.lateSlip:
        return 'GEÇ';
      case StudentMovementType.exitPermission:
        return 'İZİN';
      case StudentMovementType.earlyPickup:
        return 'ERKEN';
      case StudentMovementType.infirmary:
        return 'REVİR';
      case StudentMovementType.interview:
        return 'GÖRÜŞME';
    }
  }

  String get fullTitle {
    switch (this) {
      case StudentMovementType.lateSlip:
        return 'Derse Kabul / Geç Kağıdı';
      case StudentMovementType.exitPermission:
        return 'Öğrenci Çıkış İzin Belgesi';
      case StudentMovementType.earlyPickup:
        return 'Veli Erken Alma ve Teslim Pusulası';
      case StudentMovementType.infirmary:
        return 'Revir Sevk ve Müdahale Kağıdı';
      case StudentMovementType.interview:
        return 'Öğrenci Görüşme Pusulası';
    }
  }

  IconData get icon {
    switch (this) {
      case StudentMovementType.lateSlip:
        return Icons.schedule_rounded;
      case StudentMovementType.exitPermission:
        return Icons.sensor_door_rounded;
      case StudentMovementType.earlyPickup:
        return Icons.directions_car_filled_rounded;
      case StudentMovementType.infirmary:
        return Icons.local_hospital_rounded;
      case StudentMovementType.interview:
        return Icons.record_voice_over_rounded;
    }
  }

  Color get color {
    switch (this) {
      case StudentMovementType.lateSlip:
        return const Color(0xFFF59E0B); // Amber / Orange
      case StudentMovementType.exitPermission:
        return const Color(0xFF0284C7); // Sky / Blue
      case StudentMovementType.earlyPickup:
        return const Color(0xFF0D9488); // Teal / Emerald
      case StudentMovementType.infirmary:
        return const Color(0xFFE11D48); // Rose / Red
      case StudentMovementType.interview:
        return const Color(0xFF7C3AED); // Violet / Purple
    }
  }
}

/// Öğrenci Hareket Durumları
enum StudentMovementStatus {
  issuedLate, // Geç kağıdı verildi, derse yönlendirildi
  earlyPickupNotified, // Veli önceden erken alacağını haber verdi (planlanan saat bekleniyor)
  parentArrived, // Veli okula geldi ("Okula Geldim"), öğretmene haber verildi, öğrenci hazırlanıyor
  pendingGate, // Çıkış izni verildi / öğrenci kapıya yönlendirildi, güvenlik kapı onayı bekleniyor
  exitedSchool, // Güvenlik onayladı, öğrenci okuldan çıktı (kalan dersler izinli)
  inInfirmary, // Öğrenci şu an revirde (açık sağlık dosyası işlem bekliyor)
  inMeeting, // Öğrenci şu an görüşmede (yok yazılma koruması aktif)
  completed, // İşlem tamamlandı / öğrenci derse döndü
  cancelled, // İptal edildi
}

extension StudentMovementStatusExt on StudentMovementStatus {
  String get firestoreKey {
    switch (this) {
      case StudentMovementStatus.issuedLate:
        return 'issued_late';
      case StudentMovementStatus.earlyPickupNotified:
        return 'early_pickup_notified';
      case StudentMovementStatus.parentArrived:
        return 'parent_arrived';
      case StudentMovementStatus.pendingGate:
        return 'pending_gate';
      case StudentMovementStatus.exitedSchool:
        return 'exited_school';
      case StudentMovementStatus.inInfirmary:
        return 'in_infirmary';
      case StudentMovementStatus.inMeeting:
        return 'in_meeting';
      case StudentMovementStatus.completed:
        return 'completed';
      case StudentMovementStatus.cancelled:
        return 'cancelled';
    }
  }

  static StudentMovementStatus fromKey(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'early_pickup_notified':
        return StudentMovementStatus.earlyPickupNotified;
      case 'parent_arrived':
        return StudentMovementStatus.parentArrived;
      case 'pending_gate':
        return StudentMovementStatus.pendingGate;
      case 'exited_school':
        return StudentMovementStatus.exitedSchool;
      case 'in_infirmary':
        return StudentMovementStatus.inInfirmary;
      case 'in_meeting':
        return StudentMovementStatus.inMeeting;
      case 'completed':
        return StudentMovementStatus.completed;
      case 'cancelled':
        return StudentMovementStatus.cancelled;
      case 'issued_late':
      default:
        return StudentMovementStatus.issuedLate;
    }
  }

  String get label {
    switch (this) {
      case StudentMovementStatus.issuedLate:
        return 'Derse Yönlendirildi (Geç)';
      case StudentMovementStatus.earlyPickupNotified:
        return 'Erken Alma Bildirildi (Planlı)';
      case StudentMovementStatus.parentArrived:
        return 'Veli Okula Geldi • Öğrenci Hazırlanıyor';
      case StudentMovementStatus.pendingGate:
        return 'Güvenlik Çıkış Onayı Bekliyor';
      case StudentMovementStatus.exitedSchool:
        return 'Okuldan Çıkış Yaptı (İzinli)';
      case StudentMovementStatus.inInfirmary:
        return 'Şu An Revirde';
      case StudentMovementStatus.inMeeting:
        return 'Şu An Görüşmede';
      case StudentMovementStatus.completed:
        return 'Tamamlandı / Derse Döndü';
      case StudentMovementStatus.cancelled:
        return 'İptal Edildi';
    }
  }

  Color get color {
    switch (this) {
      case StudentMovementStatus.issuedLate:
        return const Color(0xFFD97706);
      case StudentMovementStatus.earlyPickupNotified:
        return const Color(0xFF0D9488);
      case StudentMovementStatus.parentArrived:
        return const Color(0xFF059669);
      case StudentMovementStatus.pendingGate:
        return const Color(0xFFEA580C);
      case StudentMovementStatus.exitedSchool:
        return const Color(0xFF0284C7);
      case StudentMovementStatus.inInfirmary:
        return const Color(0xFFE11D48);
      case StudentMovementStatus.inMeeting:
        return const Color(0xFF7C3AED);
      case StudentMovementStatus.completed:
        return const Color(0xFF059669);
      case StudentMovementStatus.cancelled:
        return const Color(0xFF64748B);
    }
  }
}

/// Öğrencinin o anki veya kalan ders saati bilgisi
class ResolvedLessonSlot {
  final int lessonHour; // 1-based (1, 2, 3...)
  final String lessonId;
  final String lessonName;
  final String startTime; // 'HH:mm'
  final String endTime; // 'HH:mm'
  final List<String> teacherIds;
  final List<String> teacherNames;
  final String periodId;
  final String scheduleDayName;
  final bool isOffDayFallback;

  const ResolvedLessonSlot({
    required this.lessonHour,
    required this.lessonId,
    required this.lessonName,
    this.startTime = '',
    this.endTime = '',
    this.teacherIds = const [],
    this.teacherNames = const [],
    this.periodId = '',
    this.scheduleDayName = '',
    this.isOffDayFallback = false,
  });

  String get teacherSummary =>
      teacherNames.isNotEmpty ? teacherNames.join(', ') : 'Ders Öğretmeni';

  bool get hasTimeRange => startTime.isNotEmpty && endTime.isNotEmpty;

  String get timeRangeLabel => (startTime.isNotEmpty && endTime.isNotEmpty)
      ? '$startTime - $endTime'
      : '$lessonHour. Ders';
}

/// Tekil Öğrenci Hareket / İzin / Revir / Görüşme Kaydı
/// Koleksiyon Yolu: `schools/{schoolDocId}/studentMovements/{id}`
class StudentMovementRecord {
  final String id;
  final String institutionId;
  final String schoolDocId;
  final String schoolTypeId;
  final String schoolTypeName;
  final String dateStr; // 'YYYY-MM-DD'

  final StudentMovementType type;
  final StudentMovementStatus status;

  // Öğrenci Bilgileri
  final String studentId;
  final String studentName;
  final String studentNo;
  final String classId;
  final String className;
  final String bloodType;
  final String parentName;
  final String parentPhone;

  // Ders / Öğretmen Bağlamı
  final int lessonHour;
  final List<int> coveredLessonHours;
  final String lessonId;
  final String lessonName;
  final String lessonStartTime; // 'HH:mm'
  final String lessonEndTime; // 'HH:mm'
  final List<String> targetTeacherIds;
  final List<String> targetTeacherNames;

  // Sebep / Detaylar
  final String reason;
  final String notes;
  final String urgency; // Revir için: Normal / Öncelikli / Acil

  // Çıkış İzni, Veli Erken Alma & Güvenlik Kapı Onayı Alanları
  final String exitMode; // 'Veli Eşliğinde', 'Veli Erken Alma', vb.
  final String receiverName; // Teslim alan veli/yakın adı
  final String receiverRelation; // Yakınlık derecesi
  final String receiverPhone; // İletişim telefonu
  final String vehiclePlate; // Veli araç plakası / kapı notu (isteğe bağlı)
  final String plannedExitTime; // Planlanan çıkış/erken alış saati 'HH:mm'
  final DateTime? parentArrivedAt; // Velinin "Okula Geldim" bildirdiği saat
  final String requestSource; // 'parent_portal' | 'school_admin'
  final DateTime? gateApprovedAt;
  final String gateApprovedByUid;
  final String gateApprovedByName;
  final String gateNote;
  final List<int>
  autoExcusedHours; // Güvenlik onayı sonrası otomatik izinli yazılan ders saatleri

  // Revir & Sağlık İşlemleri Entegrasyonu Alanları
  final String
  healthVisitId; // `schools/{schoolDocId}/healthVisits/{id}` ile birebir bağ
  final String infirmaryTreatment; // Revirde yapılan işlem özeti
  final bool medicationGiven;
  final String medicationName;
  final String
  infirmaryOutcome; // 'Derse Döndü', 'Eve Sevk Edildi', 'İstirahat Etti'
  final String handledByInfirmaryName; // İşlemi yapan revir/sağlık görevlisi

  // Görüşme Alanları
  final String
  interviewUnit; // 'Rehberlik / PDR Servisi', 'Okul İdaresi', 'Ders Öğretmeni'
  final String interviewerName;
  final bool protectAttendance; // Yok yazılmasın koruması

  // Düzenleyen / Zaman Damgaları
  final String createdByUid;
  final String createdByName;
  final String createdByRole;
  final DateTime createdAt;
  final DateTime? completedAt;

  const StudentMovementRecord({
    required this.id,
    required this.institutionId,
    required this.schoolDocId,
    required this.schoolTypeId,
    this.schoolTypeName = '',
    required this.dateStr,
    required this.type,
    required this.status,
    required this.studentId,
    required this.studentName,
    this.studentNo = '',
    required this.classId,
    required this.className,
    this.bloodType = '',
    this.parentName = '',
    this.parentPhone = '',
    this.lessonHour = 1,
    this.coveredLessonHours = const [],
    this.lessonId = '',
    this.lessonName = '',
    this.lessonStartTime = '',
    this.lessonEndTime = '',
    this.targetTeacherIds = const [],
    this.targetTeacherNames = const [],
    this.reason = '',
    this.notes = '',
    this.urgency = 'Normal',
    this.exitMode = '',
    this.receiverName = '',
    this.receiverRelation = '',
    this.receiverPhone = '',
    this.vehiclePlate = '',
    this.plannedExitTime = '',
    this.parentArrivedAt,
    this.requestSource = 'school_admin',
    this.gateApprovedAt,
    this.gateApprovedByUid = '',
    this.gateApprovedByName = '',
    this.gateNote = '',
    this.autoExcusedHours = const [],
    this.healthVisitId = '',
    this.infirmaryTreatment = '',
    this.medicationGiven = false,
    this.medicationName = '',
    this.infirmaryOutcome = '',
    this.handledByInfirmaryName = '',
    this.interviewUnit = '',
    this.interviewerName = '',
    this.protectAttendance = true,
    required this.createdByUid,
    required this.createdByName,
    this.createdByRole = '',
    required this.createdAt,
    this.completedAt,
  });

  /// Öğrencinin şu anda aktif olarak sınıf dışında / kapı bekleyişinde ("Kim Nerede?" radarında) olup olmadığı
  bool get isActivelyOutOfClass =>
      status == StudentMovementStatus.inInfirmary ||
      status == StudentMovementStatus.inMeeting ||
      status == StudentMovementStatus.parentArrived ||
      status == StudentMovementStatus.pendingGate ||
      status == StudentMovementStatus.exitedSchool;

  /// Öğrencinin anlık olarak tam nerede olduğunu açıklayan etiket
  String get liveLocationDescription {
    switch (status) {
      case StudentMovementStatus.inInfirmary:
        return 'Revirde (${urgency == "Acil" ? "ACİL • " : ""}${reason.isNotEmpty ? reason : "Muayene / Gözlem"})';
      case StudentMovementStatus.inMeeting:
        final unit = interviewUnit.isNotEmpty ? interviewUnit : 'Görüşmede';
        final who = interviewerName.isNotEmpty ? ' • $interviewerName' : '';
        return '$unit$who';
      case StudentMovementStatus.earlyPickupNotified:
        final pTime = plannedExitTime.isNotEmpty ? plannedExitTime : 'Bugün';
        final who = receiverName.isNotEmpty ? ' • Alacak: $receiverName' : '';
        return 'Veli Erken Alma Bildirdi (Planlanan: $pTime$who)';
      case StudentMovementStatus.parentArrived:
        final who = receiverName.isNotEmpty ? receiverName : 'Velisi';
        final plate = vehiclePlate.isNotEmpty ? ' ($vehiclePlate)' : '';
        return 'Veli Okula Geldi ($who$plate) • Öğrenci Çıkışa Hazırlanıyor';
      case StudentMovementStatus.pendingGate:
        if (type == StudentMovementType.earlyPickup) {
          return 'Öğrenci Çıkış Kapısına Yönlendirildi • Veli Teslim Onayı Bekliyor';
        }
        return 'Çıkış İzni Verildi • Güvenlik Kapısına Yönlendirildi';
      case StudentMovementStatus.exitedSchool:
        final rec = receiverName.isNotEmpty ? ' ($receiverName)' : '';
        if (type == StudentMovementType.earlyPickup) {
          return 'Velisine Erken Teslim Edildi$rec';
        }
        return 'Okuldan Çıkış Yaptı$rec';
      case StudentMovementStatus.issuedLate:
        return '$lessonHour. Derse Geç Kağıdıyla Girdi';
      case StudentMovementStatus.completed:
        if (type == StudentMovementType.infirmary) {
          return 'Revirden Döndü${infirmaryOutcome.isNotEmpty ? " ($infirmaryOutcome)" : ""}';
        }
        return 'Sınıfa / Derse Döndü';
      case StudentMovementStatus.cancelled:
        return 'İptal Edildi';
    }
  }

  String get lessonTimeRangeLabel =>
      (lessonStartTime.isNotEmpty && lessonEndTime.isNotEmpty)
      ? '$lessonStartTime - $lessonEndTime'
      : lessonStartTime;

  int get elapsedMinutes {
    final start = parentArrivedAt ?? createdAt;
    final end = completedAt ?? DateTime.now();
    final diff = end.difference(start).inMinutes;
    return diff < 0 ? 0 : diff;
  }

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'schoolDocId': schoolDocId,
      'schoolTypeId': schoolTypeId,
      'schoolTypeName': schoolTypeName,
      'dateStr': dateStr,
      'type': type.firestoreKey,
      'status': status.firestoreKey,
      'studentId': studentId,
      'studentName': studentName,
      'studentNo': studentNo,
      'classId': classId,
      'className': className,
      'bloodType': bloodType,
      'parentName': parentName,
      'parentPhone': parentPhone,
      'lessonHour': lessonHour,
      'coveredLessonHours': coveredLessonHours,
      'lessonId': lessonId,
      'lessonName': lessonName,
      'lessonStartTime': lessonStartTime,
      'lessonEndTime': lessonEndTime,
      'targetTeacherIds': targetTeacherIds,
      'targetTeacherNames': targetTeacherNames,
      'reason': reason,
      'notes': notes,
      'urgency': urgency,
      'exitMode': exitMode,
      'receiverName': receiverName,
      'receiverRelation': receiverRelation,
      'receiverPhone': receiverPhone,
      'vehiclePlate': vehiclePlate,
      'plannedExitTime': plannedExitTime,
      'parentArrivedAt': parentArrivedAt != null
          ? Timestamp.fromDate(parentArrivedAt!)
          : null,
      'requestSource': requestSource,
      'gateApprovedAt': gateApprovedAt != null
          ? Timestamp.fromDate(gateApprovedAt!)
          : null,
      'gateApprovedByUid': gateApprovedByUid,
      'gateApprovedByName': gateApprovedByName,
      'gateNote': gateNote,
      'autoExcusedHours': autoExcusedHours,
      'healthVisitId': healthVisitId,
      'infirmaryTreatment': infirmaryTreatment,
      'medicationGiven': medicationGiven,
      'medicationName': medicationName,
      'infirmaryOutcome': infirmaryOutcome,
      'handledByInfirmaryName': handledByInfirmaryName,
      'interviewUnit': interviewUnit,
      'interviewerName': interviewerName,
      'protectAttendance': protectAttendance,
      'createdByUid': createdByUid,
      'createdByName': createdByName,
      'createdByRole': createdByRole,
      'createdAt': Timestamp.fromDate(createdAt),
      'completedAt': completedAt != null
          ? Timestamp.fromDate(completedAt!)
          : null,
    };
  }

  factory StudentMovementRecord.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return StudentMovementRecord.fromMap(d, doc.id);
  }

  factory StudentMovementRecord.fromMap(Map<String, dynamic> d, String id) {
    DateTime parseDt(dynamic raw, {DateTime? fallback}) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is String && raw.isNotEmpty) {
        return DateTime.tryParse(raw) ?? (fallback ?? DateTime.now());
      }
      return fallback ?? DateTime.now();
    }

    List<int> parseInts(dynamic raw) {
      if (raw is Iterable) {
        return raw
            .map((e) => e is int ? e : int.tryParse(e.toString()))
            .whereType<int>()
            .toList();
      }
      return const [];
    }

    List<String> parseStrings(dynamic raw) {
      if (raw is Iterable) {
        return raw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    }

    return StudentMovementRecord(
      id: id,
      institutionId: (d['institutionId'] ?? '').toString(),
      schoolDocId: (d['schoolDocId'] ?? '').toString(),
      schoolTypeId: (d['schoolTypeId'] ?? '').toString(),
      schoolTypeName: (d['schoolTypeName'] ?? '').toString(),
      dateStr: (d['dateStr'] ?? '').toString(),
      type: StudentMovementTypeExt.fromKey(d['type']?.toString()),
      status: StudentMovementStatusExt.fromKey(d['status']?.toString()),
      studentId: (d['studentId'] ?? '').toString(),
      studentName: (d['studentName'] ?? '').toString(),
      studentNo: (d['studentNo'] ?? '').toString(),
      classId: (d['classId'] ?? '').toString(),
      className: (d['className'] ?? '').toString(),
      bloodType: (d['bloodType'] ?? '').toString(),
      parentName: (d['parentName'] ?? '').toString(),
      parentPhone: (d['parentPhone'] ?? '').toString(),
      lessonHour: d['lessonHour'] is int
          ? d['lessonHour'] as int
          : (int.tryParse((d['lessonHour'] ?? '1').toString()) ?? 1),
      coveredLessonHours: parseInts(d['coveredLessonHours']),
      lessonId: (d['lessonId'] ?? '').toString(),
      lessonName: (d['lessonName'] ?? '').toString(),
      lessonStartTime: (d['lessonStartTime'] ?? '').toString(),
      lessonEndTime: (d['lessonEndTime'] ?? '').toString(),
      targetTeacherIds: parseStrings(d['targetTeacherIds']),
      targetTeacherNames: parseStrings(d['targetTeacherNames']),
      reason: (d['reason'] ?? '').toString(),
      notes: (d['notes'] ?? '').toString(),
      urgency: (d['urgency'] ?? 'Normal').toString(),
      exitMode: (d['exitMode'] ?? '').toString(),
      receiverName: (d['receiverName'] ?? '').toString(),
      receiverRelation: (d['receiverRelation'] ?? '').toString(),
      receiverPhone: (d['receiverPhone'] ?? '').toString(),
      vehiclePlate: (d['vehiclePlate'] ?? '').toString(),
      plannedExitTime: (d['plannedExitTime'] ?? '').toString(),
      parentArrivedAt: d['parentArrivedAt'] != null
          ? parseDt(d['parentArrivedAt'])
          : null,
      requestSource: (d['requestSource'] ?? 'school_admin').toString(),
      gateApprovedAt: d['gateApprovedAt'] != null
          ? parseDt(d['gateApprovedAt'])
          : null,
      gateApprovedByUid: (d['gateApprovedByUid'] ?? '').toString(),
      gateApprovedByName: (d['gateApprovedByName'] ?? '').toString(),
      gateNote: (d['gateNote'] ?? '').toString(),
      autoExcusedHours: parseInts(d['autoExcusedHours']),
      healthVisitId: (d['healthVisitId'] ?? '').toString(),
      infirmaryTreatment: (d['infirmaryTreatment'] ?? '').toString(),
      medicationGiven: d['medicationGiven'] == true,
      medicationName: (d['medicationName'] ?? '').toString(),
      infirmaryOutcome: (d['infirmaryOutcome'] ?? '').toString(),
      handledByInfirmaryName: (d['handledByInfirmaryName'] ?? '').toString(),
      interviewUnit: (d['interviewUnit'] ?? '').toString(),
      interviewerName: (d['interviewerName'] ?? '').toString(),
      protectAttendance: d['protectAttendance'] != false,
      createdByUid: (d['createdByUid'] ?? '').toString(),
      createdByName: (d['createdByName'] ?? '').toString(),
      createdByRole: (d['createdByRole'] ?? '').toString(),
      createdAt: parseDt(d['createdAt']),
      completedAt: d['completedAt'] != null ? parseDt(d['completedAt']) : null,
    );
  }
}

/// Tek bir kapı / ziyaretçi / öğrenci çıkış olayı için Aç-Kapa ve Alıcı ayarları
class GateNotificationEventConfig {
  final bool enabled;
  final Map<String, bool> recipients;

  const GateNotificationEventConfig({
    required this.enabled,
    required this.recipients,
  });

  bool isRecipientEnabled(String key, {bool fallback = false}) {
    if (!enabled) return false;
    return recipients[key] ?? fallback;
  }

  GateNotificationEventConfig copyWith({
    bool? enabled,
    Map<String, bool>? recipients,
  }) {
    return GateNotificationEventConfig(
      enabled: enabled ?? this.enabled,
      recipients: recipients ?? Map<String, bool>.from(this.recipients),
    );
  }

  Map<String, dynamic> toMap() {
    return {'enabled': enabled, 'recipients': recipients};
  }

  factory GateNotificationEventConfig.fromMap(
    dynamic raw, {
    required GateNotificationEventConfig defaults,
  }) {
    if (raw is! Map) return defaults;
    final mergedRecipients = Map<String, bool>.from(defaults.recipients);
    final rawRec = raw['recipients'];
    if (rawRec is Map) {
      rawRec.forEach((k, v) {
        mergedRecipients[k.toString()] = v == true;
      });
    }
    return GateNotificationEventConfig(
      enabled: raw['enabled'] is bool
          ? raw['enabled'] as bool
          : defaults.enabled,
      recipients: mergedRecipients,
    );
  }
}

/// Güvenlik Kapı, Ziyaretçi Giriş-Çıkış ve Öğrenci Çıkış İzni Bildirim Ayarları
/// (`schools/{schoolId}.appSettings.gateNotificationSettings` ve
/// okul türü bazlı `appSettings.schoolTypeGateNotificationSettings[schoolTypeId]`)
class GateNotificationSettings {
  final GateNotificationEventConfig visitorEntry;
  final GateNotificationEventConfig visitorExit;
  final GateNotificationEventConfig studentExitPermission;
  final GateNotificationEventConfig studentGateExitConfirmed;
  final GateNotificationEventConfig earlyPickupNotice;

  const GateNotificationSettings({
    this.visitorEntry = const GateNotificationEventConfig(
      enabled: true,
      recipients: {
        'mudur': true,
        'mudur_yardimcisi': true,
        'host_staff': true,
        'guvenlik': false,
      },
    ),
    this.visitorExit = const GateNotificationEventConfig(
      enabled: true,
      recipients: {
        'mudur': true,
        'mudur_yardimcisi': true,
        'host_staff': true,
        'guvenlik': false,
      },
    ),
    this.studentExitPermission = const GateNotificationEventConfig(
      enabled: true,
      recipients: {
        'guvenlik': true,
        'mudur': true,
        'mudur_yardimcisi': true,
        'ogretmen': true,
        'veli': false,
      },
    ),
    this.studentGateExitConfirmed = const GateNotificationEventConfig(
      enabled: true,
      recipients: {
        'mudur': true,
        'mudur_yardimcisi': true,
        'issuer': true,
        'ogretmen': true,
        'veli': true,
      },
    ),
    this.earlyPickupNotice = const GateNotificationEventConfig(
      enabled: true,
      recipients: {
        'guvenlik': true,
        'mudur': true,
        'mudur_yardimcisi': true,
        'ogretmen': true,
        'veli': true,
      },
    ),
  });

  GateNotificationEventConfig eventByKey(String eventKey) {
    switch (eventKey) {
      case 'visitorEntry':
        return visitorEntry;
      case 'visitorExit':
        return visitorExit;
      case 'studentExitPermission':
        return studentExitPermission;
      case 'studentGateExitConfirmed':
        return studentGateExitConfirmed;
      case 'earlyPickupNotice':
        return earlyPickupNotice;
      default:
        return visitorEntry;
    }
  }

  GateNotificationSettings updateEvent(
    String eventKey,
    GateNotificationEventConfig next,
  ) {
    switch (eventKey) {
      case 'visitorEntry':
        return GateNotificationSettings(
          visitorEntry: next,
          visitorExit: visitorExit,
          studentExitPermission: studentExitPermission,
          studentGateExitConfirmed: studentGateExitConfirmed,
          earlyPickupNotice: earlyPickupNotice,
        );
      case 'visitorExit':
        return GateNotificationSettings(
          visitorEntry: visitorEntry,
          visitorExit: next,
          studentExitPermission: studentExitPermission,
          studentGateExitConfirmed: studentGateExitConfirmed,
          earlyPickupNotice: earlyPickupNotice,
        );
      case 'studentExitPermission':
        return GateNotificationSettings(
          visitorEntry: visitorEntry,
          visitorExit: visitorExit,
          studentExitPermission: next,
          studentGateExitConfirmed: studentGateExitConfirmed,
          earlyPickupNotice: earlyPickupNotice,
        );
      case 'studentGateExitConfirmed':
        return GateNotificationSettings(
          visitorEntry: visitorEntry,
          visitorExit: visitorExit,
          studentExitPermission: studentExitPermission,
          studentGateExitConfirmed: next,
          earlyPickupNotice: earlyPickupNotice,
        );
      case 'earlyPickupNotice':
        return GateNotificationSettings(
          visitorEntry: visitorEntry,
          visitorExit: visitorExit,
          studentExitPermission: studentExitPermission,
          studentGateExitConfirmed: studentGateExitConfirmed,
          earlyPickupNotice: next,
        );
      default:
        return this;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'visitorEntry': visitorEntry.toMap(),
      'visitorExit': visitorExit.toMap(),
      'studentExitPermission': studentExitPermission.toMap(),
      'studentGateExitConfirmed': studentGateExitConfirmed.toMap(),
      'earlyPickupNotice': earlyPickupNotice.toMap(),
    };
  }

  factory GateNotificationSettings.fromMap(dynamic raw) {
    const def = GateNotificationSettings();
    if (raw is! Map) return def;
    return GateNotificationSettings(
      visitorEntry: GateNotificationEventConfig.fromMap(
        raw['visitorEntry'],
        defaults: def.visitorEntry,
      ),
      visitorExit: GateNotificationEventConfig.fromMap(
        raw['visitorExit'],
        defaults: def.visitorExit,
      ),
      studentExitPermission: GateNotificationEventConfig.fromMap(
        raw['studentExitPermission'],
        defaults: def.studentExitPermission,
      ),
      studentGateExitConfirmed: GateNotificationEventConfig.fromMap(
        raw['studentGateExitConfirmed'],
        defaults: def.studentGateExitConfirmed,
      ),
      earlyPickupNotice: GateNotificationEventConfig.fromMap(
        raw['earlyPickupNotice'],
        defaults: def.earlyPickupNotice,
      ),
    );
  }
}
