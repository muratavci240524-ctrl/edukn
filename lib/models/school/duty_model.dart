class DutyLocation {
  final String id;
  final String institutionId;
  final String name;
  final List<int> activeDays; // 1=Mon, 7=Sun
  final String startTime; // "09:00"
  final String endTime; // "17:00"
  final String description;
  final bool checkOtherDays; // If true, show warning for teachers in other days
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
    this.eligibilities = const {},
  });

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
      eligibilities: parsedElig,
    );
  }
}

class DutyScheduleItem {
  final String id;
  final String institutionId;
  final String periodId;
  final String locationId;
  final int dayOfWeek; // 1=Mon
  final String teacherId;
  final String teacherName;
  final DateTime? weekStart; // For weekly schedules

  DutyScheduleItem({
    required this.id,
    required this.institutionId,
    required this.periodId,
    required this.locationId,
    required this.dayOfWeek,
    required this.teacherId,
    required this.teacherName,
    this.weekStart,
  });

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'periodId': periodId,
      'locationId': locationId,
      'dayOfWeek': dayOfWeek,
      'teacherId': teacherId,
      'teacherName': teacherName,
      'weekStart': weekStart?.toIso8601String(),
    };
  }

  factory DutyScheduleItem.fromMap(Map<String, dynamic> map, String docId) {
    return DutyScheduleItem(
      id: docId,
      institutionId: map['institutionId'] ?? '',
      periodId: map['periodId'] ?? '',
      locationId: map['locationId'] ?? '',
      dayOfWeek: map['dayOfWeek'] ?? 0,
      teacherId: map['teacherId'] ?? '',
      teacherName: map['teacherName'] ?? '',
      weekStart: map['weekStart'] != null
          ? DateTime.parse(map['weekStart'])
          : null,
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
