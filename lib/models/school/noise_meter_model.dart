import 'package:flutter/material.dart';

/// Sınıf Etkinlik Hassasiyet Modları
enum NoisePresetType {
  exam,        // Sınav Modu (35-45 dB)
  study,       // Bireysel Etüt / Okuma (50-55 dB)
  groupWork,   // Grup Çalışması (65-70 dB)
  freeActivity,// Serbest Etkinlik (80-85 dB)
  custom,      // Manuel / Özel Ayar
}

class NoiseSensitivityPreset {
  final NoisePresetType type;
  final String title;
  final String description;
  final IconData icon;
  final double thresholdDb;
  final Color color;

  const NoiseSensitivityPreset({
    required this.type,
    required this.title,
    required this.description,
    required this.icon,
    required this.thresholdDb,
    required this.color,
  });

  static const List<NoiseSensitivityPreset> presets = [
    NoiseSensitivityPreset(
      type: NoisePresetType.exam,
      title: 'Sınav Modu',
      description: 'Mutlak sessizlik gerektiren resmi sınav ve denemeler',
      icon: Icons.quiz_rounded,
      thresholdDb: 45.0,
      color: Color(0xFFEF4444),
    ),
    NoiseSensitivityPreset(
      type: NoisePresetType.study,
      title: 'Bireysel Etüt',
      description: 'Kitap okuma, soru çözme ve bireysel odaklanma',
      icon: Icons.menu_book_rounded,
      thresholdDb: 55.0,
      color: Color(0xFF3B82F6),
    ),
    NoiseSensitivityPreset(
      type: NoisePresetType.groupWork,
      title: 'Grup Çalışması',
      description: 'Fısıltı ve kontrollü takım tartışmalarına uygun',
      icon: Icons.groups_rounded,
      thresholdDb: 70.0,
      color: Color(0xFF10B981),
    ),
    NoiseSensitivityPreset(
      type: NoisePresetType.freeActivity,
      title: 'Serbest Etkinlik',
      description: 'Oyun, drama, atölye ve beden eğitimi aktiviteleri',
      icon: Icons.celebration_rounded,
      thresholdDb: 85.0,
      color: Color(0xFFF59E0B),
    ),
  ];
}

/// Sessizlik Ödül Aşamaları (Gamification)
class SilenceRewardMilestone {
  final int targetSeconds;
  final String title;
  final String emoji;
  final String rewardName;
  final Color glowColor;

  const SilenceRewardMilestone({
    required this.targetSeconds,
    required this.title,
    required this.emoji,
    required this.rewardName,
    required this.glowColor,
  });

  static const List<SilenceRewardMilestone> defaultMilestones = [
    SilenceRewardMilestone(
      targetSeconds: 60,
      title: '1 Dakika Başarısı!',
      emoji: '⭐',
      rewardName: 'Bronz Sessizlik Yıldızı',
      glowColor: Color(0xFFF59E0B),
    ),
    SilenceRewardMilestone(
      targetSeconds: 180,
      title: '3 Dakika Harika Odak!',
      emoji: '🌟',
      rewardName: 'Gümüş Sessizlik Madalyası',
      glowColor: Color(0xFF38BDF8),
    ),
    SilenceRewardMilestone(
      targetSeconds: 300,
      title: '5 Dakika Mükemmel Sınıf!',
      emoji: '🏆',
      rewardName: 'Altın Sınıf Kupası',
      glowColor: Color(0xFFEAB308),
    ),
    SilenceRewardMilestone(
      targetSeconds: 600,
      title: '10 Dakika Efsanevi Disiplin!',
      emoji: '👑',
      rewardName: 'Şampiyonluk Tacı',
      glowColor: Color(0xFFA855F7),
    ),
  ];
}
