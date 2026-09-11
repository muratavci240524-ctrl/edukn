import 'package:flutter/material.dart';

/// Çekiliş Animasyon Modları
enum PickerAnimationMode {
  /// 🎡 Renkli Çarkıfelek (Fortune Wheel)
  wheel,

  /// 🎰 Neon Slot Makinesi (Slot Machine Roller)
  slot,
}

extension PickerAnimationModeExtension on PickerAnimationMode {
  String get title {
    switch (this) {
      case PickerAnimationMode.wheel:
        return 'Renkli Çarkıfelek';
      case PickerAnimationMode.slot:
        return 'Slot Makinesi';
    }
  }

  IconData get icon {
    switch (this) {
      case PickerAnimationMode.wheel:
        return Icons.pie_chart_rounded;
      case PickerAnimationMode.slot:
        return Icons.view_carousel_rounded;
    }
  }
}

/// Çekiliş Havuzundaki Öğrenci Modeli
class PickerStudent {
  final String id;
  final String name;
  final String? studentNumber;
  final String? className;
  final String gender; // 'E', 'K' veya 'unspecified'
  final String? avatarUrl;
  bool isPresent; // Yoklama / havuzda aktif mi?
  bool isPicked; // Bu turda daha önce seçildi mi?

  PickerStudent({
    required this.id,
    required this.name,
    this.studentNumber,
    this.className,
    this.gender = 'unspecified',
    this.avatarUrl,
    this.isPresent = true,
    this.isPicked = false,
  });

  bool get isFemale {
    final g = gender.trim().toLowerCase();
    return g.startsWith('k') || g.startsWith('f') || g == 'kadın' || g == 'kız';
  }

  bool get isMale {
    final g = gender.trim().toLowerCase();
    return g.startsWith('e') || g.startsWith('m') || g == 'erkek';
  }

  String get shortName {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length <= 1) return name;
    return '${parts.first} ${parts.last[0]}.';
  }

  PickerStudent clone() {
    return PickerStudent(
      id: id,
      name: name,
      studentNumber: studentNumber,
      className: className,
      gender: gender,
      avatarUrl: avatarUrl,
      isPresent: isPresent,
      isPicked: isPicked,
    );
  }
}

/// Seçim Geçmişi / Log Kaydı
class PickerLog {
  final String id;
  final String studentId;
  final String studentName;
  final String? className;
  final String gender;
  final DateTime pickedAt;
  final int orderNumber;

  PickerLog({
    required this.id,
    required this.studentId,
    required this.studentName,
    this.className,
    required this.gender,
    required this.pickedAt,
    required this.orderNumber,
  });

  bool get isFemale {
    final g = gender.trim().toLowerCase();
    return g.startsWith('k') || g.startsWith('f') || g == 'kadın' || g == 'kız';
  }

  bool get isMale {
    final g = gender.trim().toLowerCase();
    return g.startsWith('e') || g.startsWith('m') || g == 'erkek';
  }
}
