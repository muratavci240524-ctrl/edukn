class DutyLocation {
  final String id;
  final String institutionId;
  final String name;
  final List<int> activeDays; // 1=Mon, 7=Sun
  final String startTime; // "09:00"
  final String endTime; // "17:00"
  final String description;
  final bool checkOtherDays; // If true, show warning for teachers in other days
  final int order; // Sıralama önceliği
  final String group; // Nöbet Grubu (Örn: Kat Nöbetleri, Aziz Sancar, Hafta Sonu)
  final Map<String, List<String>>
  eligibilities; // Key: "dayId" (e.g. "1"), Value: List of Teacher IDs

  DutyLocation({
    required this.id,
    required this.institutionId,
    required this.name,
    required this.activeDays,
    this.startTime = '',
    this.endTime = '',
    this.description = '',
    this.checkOtherDays = true,
    this.order = 0,
    this.group = '',
    this.eligibilities = const {},
  });

  DutyLocation copyWith({
    String? id,
    String? institutionId,
    String? name,
    List<int>? activeDays,
    String? startTime,
    String? endTime,
    String? description,
    bool? checkOtherDays,
    int? order,
    String? group,
    Map<String, List<String>>? eligibilities,
  }) {
    return DutyLocation(
      id: id ?? this.id,
      institutionId: institutionId ?? this.institutionId,
      name: name ?? this.name,
      activeDays: activeDays ?? this.activeDays,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      description: description ?? this.description,
      checkOtherDays: checkOtherDays ?? this.checkOtherDays,
      order: order ?? this.order,
      group: group ?? this.group,
      eligibilities: eligibilities ?? this.eligibilities,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'institutionId': institutionId,
      'name': name,
      'activeDays': activeDays,
      'startTime': startTime,
      'endTime': endTime,
      'description': description,
      'checkOtherDays': checkOtherDays,
      'order': order,
      'group': group,
      'eligibilities': eligibilities,
    };
  }

  factory DutyLocation.fromMap(Map<String, dynamic> map) {
    // Helper to parse Map<String, List<String>> safely
    Map<String, List<String>> parsedElig = {};
    if (map['eligibilities'] != null) {
      final raw = map['eligibilities'] as Map<String, dynamic>;
      raw.forEach((key, value) {
        parsedElig[key] = List<String>.from(value ?? []);
      });
    }

    return DutyLocation(
      id: map['id'] ?? '',
      institutionId: map['institutionId'] ?? '',
      name: map['name'] ?? '',
      activeDays: List<int>.from(map['activeDays'] ?? []),
      startTime: map['startTime'] ?? '',
      endTime: map['endTime'] ?? '',
      description: map['description'] ?? '',
      checkOtherDays: map['checkOtherDays'] ?? true,
      order: (map['order'] ?? 0) as int,
      group: map['group'] ?? '',
      eligibilities: parsedElig,
    );
  }
}

class DutyScheduleItem {
  final String id;
  final String institutionId;
  final String periodId;
  final String? termId;
  final String locationId;
  final String? locationName;
  final int dayOfWeek; // 1=Mon
  final String teacherId;
  final String teacherName;
  final DateTime? weekStart; // For weekly schedules
  final String? notifiedTeacherId;
  final bool? notificationSent;
  final String? dutyDate;

  DutyScheduleItem({
    required this.id,
    required this.institutionId,
    required this.periodId,
    this.termId,
    required this.locationId,
    this.locationName,
    required this.dayOfWeek,
    required this.teacherId,
    required this.teacherName,
    this.weekStart,
    this.notifiedTeacherId,
    this.notificationSent,
    this.dutyDate,
  });

  DutyScheduleItem copyWith({
    String? id,
    String? institutionId,
    String? periodId,
    String? termId,
    String? locationId,
    String? locationName,
    int? dayOfWeek,
    String? teacherId,
    String? teacherName,
    DateTime? weekStart,
    String? notifiedTeacherId,
    bool? notificationSent,
    String? dutyDate,
  }) {
    return DutyScheduleItem(
      id: id ?? this.id,
      institutionId: institutionId ?? this.institutionId,
      periodId: periodId ?? this.periodId,
      termId: termId ?? this.termId,
      locationId: locationId ?? this.locationId,
      locationName: locationName ?? this.locationName,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      teacherId: teacherId ?? this.teacherId,
      teacherName: teacherName ?? this.teacherName,
      weekStart: weekStart ?? this.weekStart,
      notifiedTeacherId: notifiedTeacherId ?? this.notifiedTeacherId,
      notificationSent: notificationSent ?? this.notificationSent,
      dutyDate: dutyDate ?? this.dutyDate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'periodId': periodId,
      'termId': termId,
      'locationId': locationId,
      'locationName': locationName,
      'dayOfWeek': dayOfWeek,
      'teacherId': teacherId,
      'teacherName': teacherName,
      'weekStart': weekStart?.toIso8601String(),
      'notifiedTeacherId': notifiedTeacherId,
      'notificationSent': notificationSent,
      'dutyDate': dutyDate,
    };
  }

  factory DutyScheduleItem.fromMap(Map<String, dynamic> map, String docId) {
    return DutyScheduleItem(
      id: docId,
      institutionId: map['institutionId'] ?? '',
      periodId: map['periodId'] ?? '',
      termId: map['termId'] as String?,
      locationId: map['locationId'] ?? '',
      locationName: map['locationName'] as String?,
      dayOfWeek: map['dayOfWeek'] ?? 0,
      teacherId: map['teacherId'] ?? '',
      teacherName: map['teacherName'] ?? '',
      weekStart: map['weekStart'] != null
          ? DateTime.parse(map['weekStart'])
          : null,
      notifiedTeacherId: map['notifiedTeacherId'] as String?,
      notificationSent: map['notificationSent'] == true,
      dutyDate: map['dutyDate'] as String?,
    );
  }
}

// Replaces TeacherDutyPreference for location-centric approach
class DutyEligibility {
  final String id;
  final String institutionId;
  final String locationId;
  final int dayOfWeek; // 1=Mon, 7=Sun
  final List<String> eligibleTeacherIds;

  DutyEligibility({
    this.id = '',
    required this.institutionId,
    required this.locationId,
    required this.dayOfWeek,
    required this.eligibleTeacherIds,
  });

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'locationId': locationId,
      'dayOfWeek': dayOfWeek,
      'eligibleTeacherIds': eligibleTeacherIds,
    };
  }

  factory DutyEligibility.fromMap(Map<String, dynamic> map, String docId) {
    return DutyEligibility(
      id: docId,
      institutionId: map['institutionId'] ?? '',
      locationId: map['locationId'] ?? '',
      dayOfWeek: map['dayOfWeek'] ?? 0,
      eligibleTeacherIds: List<String>.from(map['eligibleTeacherIds'] ?? []),
    );
  }
}

class DutyRules {
  final String institutionId;
  final bool rotateLocations;

  DutyRules({required this.institutionId, this.rotateLocations = true});

  Map<String, dynamic> toMap() {
    return {'institutionId': institutionId, 'rotateLocations': rotateLocations};
  }

  factory DutyRules.fromMap(Map<String, dynamic> map) {
    return DutyRules(
      institutionId: map['institutionId'] ?? '',
      rotateLocations: map['rotateLocations'] ?? true,
    );
  }
}
