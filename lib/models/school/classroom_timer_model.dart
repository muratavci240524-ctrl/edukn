import 'package:flutter/material.dart';

/// Senaryo Aşama Modeli
class TimerStep {
  final String id;
  final String title;
  final int durationMinutes;
  final int durationSeconds;
  final String instructionText;
  final bool isBreak; // Mola aşaması mı?
  final Color? customColor;

  TimerStep({
    required this.id,
    required this.title,
    this.durationMinutes = 0,
    this.durationSeconds = 0,
    required this.instructionText,
    this.isBreak = false,
    this.customColor,
  });

  int get totalSeconds => (durationMinutes * 60) + durationSeconds;

  String get formattedDuration {
    final m = durationMinutes.toString().padLeft(2, '0');
    final s = durationSeconds.toString().padLeft(2, '0');
    return '$m:$s';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'durationMinutes': durationMinutes,
      'durationSeconds': durationSeconds,
      'instructionText': instructionText,
      'isBreak': isBreak,
    };
  }

  factory TimerStep.fromMap(Map<String, dynamic> map) {
    return TimerStep(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      durationMinutes: map['durationMinutes'] ?? 0,
      durationSeconds: map['durationSeconds'] ?? 0,
      instructionText: map['instructionText'] ?? '',
      isBreak: map['isBreak'] ?? false,
    );
  }
}

/// Senaryo Şablon Modeli
class TimerTemplate {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final List<TimerStep> steps;
  final String category; // 'exam', 'study', 'debate', 'custom'
  final bool isCustom;
  final String? institutionId;

  TimerTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.steps,
    required this.category,
    this.isCustom = false,
    this.institutionId,
  });

  int get totalDurationMinutes =>
      steps.fold(0, (acc, step) => acc + step.durationMinutes + (step.durationSeconds / 60).ceil());

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'colorValue': color.toARGB32(),
      'steps': steps.map((s) => s.toMap()).toList(),
      'category': category,
      'isCustom': isCustom,
      'institutionId': institutionId,
    };
  }

  factory TimerTemplate.fromMap(Map<String, dynamic> map, String id) {
    final stepsRaw = (map['steps'] as List<dynamic>?) ?? [];
    final steps = stepsRaw.map((s) => TimerStep.fromMap(Map<String, dynamic>.from(s))).toList();

    return TimerTemplate(
      id: id,
      title: map['title'] ?? 'Özel Senaryo',
      description: map['description'] ?? '',
      icon: Icons.playlist_add_check_rounded,
      color: map['colorValue'] != null ? Color(map['colorValue']) : const Color(0xFF4F46E5),
      steps: steps,
      category: map['category'] ?? 'custom',
      isCustom: map['isCustom'] ?? true,
      institutionId: map['institutionId'],
    );
  }

  /// Hazır Yerleşik Şablonlar
  static List<TimerTemplate> get defaultTemplates => [
        TimerTemplate(
          id: 'lgs_exam',
          title: 'LGS Deneme Sınavı (2 Oturum)',
          description: 'Optik kodlama, Sözel Bölüm, Ara Dinlenme ve Sayısal Bölüm aşamaları.',
          icon: Icons.assignment_rounded,
          color: const Color(0xFF4F46E5),
          category: 'exam',
          steps: [
            TimerStep(
              id: 'lgs_1',
              title: '1. Aşama: Optik Kodlama ve Kurallar',
              durationMinutes: 5,
              instructionText: 'Lütfen optik formlarınızı kontrol ediniz, ad-soyad ve T.C. kimlik numaranızı doğru kodlayınız.',
              isBreak: false,
            ),
            TimerStep(
              id: 'lgs_2',
              title: '2. Aşama: Sözel Bölüm (50 Soru)',
              durationMinutes: 75,
              instructionText: 'Sözel bölüm başladı! Türkçe (20), İnkılap (10), Din (10), Yabancı Dil (10). Başarılar dileriz.',
              isBreak: false,
            ),
            TimerStep(
              id: 'lgs_3',
              title: '3. Aşama: Dinlenme & Mola',
              durationMinutes: 45,
              instructionText: 'Sözel bölüm tamamlandı. Lütfen sınıftan çıkıp hava alınız ve dinleniniz.',
              isBreak: true,
            ),
            TimerStep(
              id: 'lgs_4',
              title: '4. Aşama: Sayısal Bölüm (40 Soru)',
              durationMinutes: 80,
              instructionText: 'Sayısal bölüm başladı! Matematik (20) ve Fen Bilimleri (20). Sürenizi dikkatli kullanınız.',
              isBreak: false,
            ),
          ],
        ),
        TimerTemplate(
          id: 'yks_tyt_exam',
          title: 'YKS / TYT Deneme Sınavı',
          description: '165 dakikalık standart TYT deneme oturumu ve optik toplama.',
          icon: Icons.school_rounded,
          color: const Color(0xFF059669),
          category: 'exam',
          steps: [
            TimerStep(
              id: 'tyt_1',
              title: '1. Aşama: Kurallar ve Kitapçık Kontrolü',
              durationMinutes: 5,
              instructionText: 'Kitapçık sayfalarını kontrol ediniz. Eksik veya hatalı sayfa varsa gözetmene bildiriniz.',
              isBreak: false,
            ),
            TimerStep(
              id: 'tyt_2',
              title: '2. Aşama: TYT Sınavı (120 Soru)',
              durationMinutes: 165,
              instructionText: 'TYT sınavı başladı! İlk 120 dakika ve son 15 dakika salondan çıkış yasaktır.',
              isBreak: false,
            ),
            TimerStep(
              id: 'tyt_3',
              title: '3. Aşama: Optik ve Evrak Toplama',
              durationMinutes: 5,
              instructionText: 'Sınav süresi dolmuştur. Kalemleri bırakıp formların toplanmasını bekleyiniz.',
              isBreak: false,
            ),
          ],
        ),
        TimerTemplate(
          id: 'pomodoro_study',
          title: 'Pomodoro Odaklanma Etüdü',
          description: '25 Dk Odaklanma + 5 Dk Mola döngüleriyle verimli ders çalışma.',
          icon: Icons.timer_rounded,
          color: const Color(0xFFEA580C),
          category: 'study',
          steps: [
            TimerStep(
              id: 'pom_1',
              title: '1. Blok: Odaklanmış Çalışma',
              durationMinutes: 25,
              instructionText: 'Tüm dikkat dağıtıcıları kaldırınız ve hedefinize odaklanınız.',
              isBreak: false,
            ),
            TimerStep(
              id: 'pom_2',
              title: 'Kısa Mola',
              durationMinutes: 5,
              instructionText: 'Ayağa kalkın, su için ve gözlerinizi dinlendirin.',
              isBreak: true,
            ),
            TimerStep(
              id: 'pom_3',
              title: '2. Blok: Odaklanmış Çalışma',
              durationMinutes: 25,
              instructionText: 'İkinci çalışma bloğu başladı. Konsantrasyonunuzu koruyun.',
              isBreak: false,
            ),
            TimerStep(
              id: 'pom_4',
              title: 'Uzun Dinlenme Molası',
              durationMinutes: 15,
              instructionText: 'Tebrikler! İki çalışma bloğunu tamamladınız. 15 dakika hak edilmiş mola.',
              isBreak: true,
            ),
          ],
        ),
        TimerTemplate(
          id: 'debate_session',
          title: 'Münazara / Sunum Oturumu',
          description: 'Açılış, savunma, serbest tartışma ve jüri değerlendirme aşamaları.',
          icon: Icons.record_voice_over_rounded,
          color: const Color(0xFF7C3AED),
          category: 'debate',
          steps: [
            TimerStep(
              id: 'deb_1',
              title: '1. Tur: Hükümet & Muhalefet Açılış',
              durationMinutes: 4,
              instructionText: 'Grup sözcüleri tezlerini ve ana argümanlarını sunar.',
              isBreak: false,
            ),
            TimerStep(
              id: 'deb_2',
              title: '2. Tur: Karşı Tez ve Çürütmeler',
              durationMinutes: 6,
              instructionText: 'Gruplar karşı tarafın argümanlarına yanıt verir.',
              isBreak: false,
            ),
            TimerStep(
              id: 'deb_3',
              title: '3. Tur: Serbest Tartışma & Soru-Cevap',
              durationMinutes: 10,
              instructionText: 'Tüm üyeler söz hakkı alarak soru sorabilir ve tartışabilir.',
              isBreak: false,
            ),
            TimerStep(
              id: 'deb_4',
              title: '4. Tur: Kapanış ve Jüri Değerlendirmesi',
              durationMinutes: 5,
              instructionText: 'Kapanış özetleri ve jüri puanlama süreci.',
              isBreak: false,
            ),
          ],
        ),
      ];
}

/// Kronometre Tur (Lap) Modeli
class StopwatchLap {
  final int lapNumber;
  final int lapTimeMs; // Bu turun süresi
  final int totalTimeMs; // Toplam geçen süre
  final String note;

  StopwatchLap({
    required this.lapNumber,
    required this.lapTimeMs,
    required this.totalTimeMs,
    this.note = '',
  });

  String get formattedLapTime => formatStopwatchTime(lapTimeMs);
  String get formattedTotalTime => formatStopwatchTime(totalTimeMs);

  static String formatStopwatchTime(int milliseconds) {
    final minutes = (milliseconds ~/ 60000).toString().padLeft(2, '0');
    final seconds = ((milliseconds % 60000) ~/ 1000).toString().padLeft(2, '0');
    final hundredths = ((milliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$minutes:$seconds.$hundredths';
  }
}
