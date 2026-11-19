import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../models/school/butterfly_exam_model.dart';
import '../../../../models/school/seating_plan_model.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../services/butterfly_distribution_service.dart';
import '../../../../services/term_service.dart';
import '../../../../widgets/edukn_app_bar.dart';
import '../../../../widgets/custom_date_range_picker.dart';
import '../../../../widgets/custom_time_picker.dart';
import 'butterfly_exam_detail_screen.dart';

/// Kelebek Sınav Oluşturma Sihirbazı (4 Adımlı, Deneme Sınavı & Derslik & Gözetmen Entegreli)
class ButterflyExamWizardScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final ExamDistribution? existingDistribution;

  const ButterflyExamWizardScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.existingDistribution,
  });

  @override
  State<ButterflyExamWizardScreen> createState() => _ButterflyExamWizardScreenState();
}

class _ButterflyExamWizardScreenState extends State<ButterflyExamWizardScreen> {
  int _currentStep = 0;

  // 1. Adım: Sınav Bilgileri & Deneme Sınavı Entegrasyonu
  bool _isTrialExamMode = false;
  List<TrialExam> _availableTrialExams = [];
  TrialExam? _selectedTrialExam;

  final _titleController = TextEditingController(text: '1. Dönem Ortak Sınavı');
  final _lessonController = TextEditingController(text: 'Matematik');
  DateTime _examDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _examTime = const TimeOfDay(hour: 9, minute: 30);
  final _notesController = TextEditingController();

  // 2. Adım: Sınıflar, Öğrenciler & 3 Dağıtım Modu
  bool _isLoadingClasses = true;
  bool _isLoadingStudents = false;
  DistributionMode _distributionMode = DistributionMode.fullCross;
  List<Map<String, dynamic>> _availableClasses = [];
  final Set<String> _selectedClassIds = {};
  final List<ExamStudent> _selectedStudents = [];

  // 3. Adım: Sınav Salonları, Oturumlar, Masa Düzenleri & Gözetmenler
  bool _isLoadingLayouts = true;
  bool _isLoadingClassrooms = true;
  bool _isLoadingTeachers = true;

  int _sessionCount = 1; // Kaç ders/oturum saati (1, 2, 3...)
  final int _sessionDurationMinutes = 40; // Varsayılan oturum süresi (dakika)
  final int _breakMinutes = 15; // Oturumlar arası mola süresi (dakika)
  List<Map<String, dynamic>> _sessionConfigs = [
    {
      'title': '1. Oturum',
      'durationMinutes': 75,
      'breakMinutes': 15,
      'splitCount': 1,
    }
  ];
  List<Map<String, dynamic>> _sessionSlots = []; // Oturum ve gözetmenlik saatleri listesi
  List<String> _instructions = []; // Sınav uygulama yönergesi maddeleri

  List<ClassroomLayout> _availableLayouts = [];
  List<Map<String, dynamic>> _availableClassrooms = [];
  List<Map<String, dynamic>> _availableTeachers = [];
  final List<Map<String, dynamic>> _configuredRooms = []; // {classroomId, classroomName, layoutId, layout, customCapacity, supervisorId, supervisorName, supervisors}

  // 4. Adım: Dağıtım Ayarları (Boşlukları Eşit Dağıt Switch & PDF Sınav Adı Switch)
  bool _balanceEmptySeats = true;
  bool _showExamTitleOnPdf = true;
  bool _isDistributing = false;

  @override
  void initState() {
    super.initState();
    _initFromExistingDistribution();
    _initDefaultSessionSlots();
    _initDefaultInstructions();
    _loadAllInitialData();
  }

  void _initFromExistingDistribution() {
    final existing = widget.existingDistribution;
    if (existing == null) return;

    _titleController.text = existing.title;
    _lessonController.text = existing.lessonName;
    _examDate = existing.examDate;
    _examTime = _parseTimeOfDay(existing.examTime);
    _notesController.text = existing.notes ?? '';
    _showExamTitleOnPdf = existing.showExamTitleOnPdf;

    if (existing.instructions.isNotEmpty) {
      _instructions = List<String>.from(existing.instructions);
    }
    if (existing.sessionSlots.isNotEmpty) {
      final firstStart = existing.sessionSlots.first['startTime']?.toString();
      if (firstStart != null && firstStart.trim().isNotEmpty) {
        _examTime = _parseTimeOfDay(firstStart);
      }
      final parsedConfigs = _buildSessionConfigsFromRawSlots(existing.sessionSlots);
      if (parsedConfigs.isNotEmpty) {
        _sessionConfigs = parsedConfigs;
      }
      _sessionSlots = List<Map<String, dynamic>>.from(existing.sessionSlots);
      _sessionCount = _sessionConfigs.length;
    }
    _selectedClassIds.addAll(existing.selectedClassIds);

    if (existing.distributionMode != null) {
      final modeMatch = DistributionMode.values
          .where((m) => m.name == existing.distributionMode)
          .firstOrNull;
      if (modeMatch != null) _distributionMode = modeMatch;
    }

    if (existing.rooms.isNotEmpty) {
      _configuredRooms.clear();
      for (final r in existing.rooms) {
        _configuredRooms.add({
          'classroomId': r.classroomId,
          'classroomName': r.classroomName,
          'layoutId': r.layoutId,
          'layout': r.layoutSnapshot,
          'customCapacity': r.totalCapacity,
          'supervisorId': r.supervisorId,
          'supervisorName': r.supervisorName ?? '',
          'supervisors': List<Map<String, dynamic>>.from(r.supervisors),
          'sessionSplits': Map<String, dynamic>.from(r.sessionSplits),
          'auto': false,
        });
      }
    }
  }

  TimeOfDay _parseTimeOfDay(String timeStr) {
    final match = RegExp(r'(\d{1,2})[:.](\d{2})').firstMatch(timeStr);
    if (match != null) {
      final h = int.tryParse(match.group(1)!) ?? 9;
      final m = int.tryParse(match.group(2)!) ?? 30;
      return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
    }
    return const TimeOfDay(hour: 9, minute: 30);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _lessonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // TÜM ENTEGRE VERİLERİ YÜKLEME (GÜVENLİ & SIRALI)
  // ===========================================================================
  Future<void> _loadAllInitialData() async {
    await _loadLayouts();
    await Future.wait([
      _loadTrialExams(),
      _loadClasses(),
      _loadClassrooms(),
      _loadTeachers(),
    ]);

    if (widget.existingDistribution != null && _selectedClassIds.isNotEmpty) {
      await _fetchStudentsForSelectedClasses();
    }
  }

  /// Otomatik işaretli salonlar, kendinden önceki salonun derslik listesindeki bir sonraki
  /// dersliğini (701 -> 702 -> 703) alır. Elle değiştirilmiş salonlar korunur.
  void _reflowAutoRooms() {
    if (_availableClassrooms.isEmpty) return;
    for (int i = 1; i < _configuredRooms.length; i++) {
      final room = _configuredRooms[i];
      if (room['auto'] != true) continue;
      final prevId = _configuredRooms[i - 1]['classroomId'];
      final prevIdx = _availableClassrooms.indexWhere((c) => c['id'] == prevId);
      if (prevIdx < 0) continue;
      final used = <dynamic>{
        for (int j = 0; j < _configuredRooms.length; j++)
          if (j != i) _configuredRooms[j]['classroomId'],
      };
      Map<String, dynamic>? next;
      for (int k = prevIdx + 1; k < _availableClassrooms.length; k++) {
        if (!used.contains(_availableClassrooms[k]['id'])) {
          next = _availableClassrooms[k];
          break;
        }
      }
      if (next == null) continue;
      room['classroomId'] = next['id'];
      room['classroomName'] = next['name'];
      room['customCapacity'] = (next['capacity'] as int?) ?? room['customCapacity'];
      if (next['layoutId'] != null) {
        final l = _findLayoutForClassroom(next['layoutId'] as String?);
        room['layout'] = l;
        room['layoutId'] = l.id;
      }
    }
  }

  // ===========================================================================
  // OTURUM, YÖNERGE & ÇOKLU GÖZETMEN YARDIMCILARI
  // ===========================================================================
  void _initDefaultSessionSlots() {
    if (widget.existingDistribution != null && widget.existingDistribution!.sessionSlots.isNotEmpty) {
      return;
    }
    _recalcSessionSlots();
  }

  List<Map<String, dynamic>> _computeSlotsFromConfigs({
    required TimeOfDay startTime,
    required List<Map<String, dynamic>> configs,
  }) {
    final slots = <Map<String, dynamic>>[];
    DateTime currentStart = DateTime(
      _examDate.year,
      _examDate.month,
      _examDate.day,
      startTime.hour,
      startTime.minute,
    );

    int globalSlotIdx = 0;

    for (int sIdx = 0; sIdx < configs.length; sIdx++) {
      final config = configs[sIdx];
      final title = config['title']?.toString() ?? '${sIdx + 1}. Oturum';
      final duration = (config['durationMinutes'] as int?) ?? 40;
      final breakMins = (config['breakMinutes'] as int?) ?? 15;
      final splitCount = (config['splitCount'] as int?) ?? 1;

      final sessionEnd = currentStart.add(Duration(minutes: duration));

      if (splitCount <= 1) {
        slots.add({
          'slotIndex': globalSlotIdx++,
          'sessionIndex': sIdx,
          'sessionTitle': title,
          'dutyIndex': 0,
          'label': title,
          'startTime': DateFormat('HH:mm').format(currentStart),
          'endTime': DateFormat('HH:mm').format(sessionEnd),
          'durationMinutes': duration,
          'breakMinutes': breakMins,
        });
      } else {
        List<int> durations = [];
        final rawDurations = config['customSplitDurations'];
        if (rawDurations is List && rawDurations.length == splitCount) {
          durations = rawDurations.map((e) => (e as int?) ?? (duration ~/ splitCount)).toList();
          final sum = durations.fold<int>(0, (a, b) => a + b);
          if (sum != duration) {
            durations[splitCount - 1] += (duration - sum);
          }
        } else {
          final basePart = duration ~/ splitCount;
          durations = List.generate(splitCount, (_) => basePart);
          final diff = duration - (basePart * splitCount);
          durations[splitCount - 1] += diff;
          config['customSplitDurations'] = List<int>.from(durations);
        }

        DateTime partStart = currentStart;
        for (int p = 0; p < splitCount; p++) {
          final pDuration = durations[p];
          final partEnd = partStart.add(Duration(minutes: pDuration));
          final isLast = p == splitCount - 1;

          slots.add({
            'slotIndex': globalSlotIdx++,
            'sessionIndex': sIdx,
            'sessionTitle': title,
            'dutyIndex': p,
            'label': '$title (${p + 1}. Devre)',
            'startTime': DateFormat('HH:mm').format(partStart),
            'endTime': DateFormat('HH:mm').format(partEnd),
            'durationMinutes': pDuration,
            'breakMinutes': isLast ? breakMins : 0,
          });

          partStart = partEnd;
        }
      }

      currentStart = sessionEnd.add(Duration(minutes: breakMins));
    }

    return slots;
  }

  void _recalcSessionSlots() {
    if (_sessionConfigs.isEmpty) {
      _sessionConfigs = [
        {
          'title': '1. Oturum',
          'durationMinutes': _sessionDurationMinutes,
          'breakMinutes': _breakMinutes,
          'splitCount': 1,
        }
      ];
    }
    _sessionCount = _sessionConfigs.length;
    _sessionSlots = _computeSlotsFromConfigs(
      startTime: _examTime,
      configs: _sessionConfigs,
    );
    for (final r in _configuredRooms) {
      _syncRoomSupervisorsWithEffectiveSlots(r);
    }
  }

  void _initDefaultInstructions() {
    if (widget.existingDistribution != null && widget.existingDistribution!.instructions.isNotEmpty) {
      return;
    }
    _instructions = [
      'Gözetmen öğretmenler sınav başlangıç saatinden 15 dakika önce sınav evraklarını idareden teslim almalıdır.',
      'Öğrenciler sınav salonuna cep telefonu, akıllı saat veya haberleşme araçlarıyla giremez.',
      'Sınav başlamadan önce öğrencilerin kimlik ve salon oturma planı kontrolleri eksiksiz yapılmalıdır.',
      'Sınav evrak poşeti öğrenciler huzurunda açılarak optik form ve kitapçıklar kontrol edilmelidir.',
      'Sınavın ilk 15 dakikası ve son 10 dakikası hiçbir öğrencinin salondan çıkışına izin verilmez.',
      'Sınav bitiminde sınav evrakları eksiksiz toplanarak salon yoklama tutanağı gözetmen tarafından imzalanmalıdır.',
    ];
  }

  List<Map<String, dynamic>> _getEffectiveSlotsForRoom(Map<String, dynamic> room) {
    final List<Map<String, dynamic>> baseSlots = _sessionSlots.isNotEmpty
        ? _sessionSlots
        : _computeSlotsFromConfigs(startTime: _examTime, configs: _sessionConfigs);

    final Map<int, List<Map<String, dynamic>>> grouped = {};
    for (int i = 0; i < baseSlots.length; i++) {
      final s = baseSlots[i];
      final sIdx = (s['sessionIndex'] as num?)?.toInt() ?? i;
      grouped.putIfAbsent(sIdx, () => []).add(s);
    }

    final sessionKeys = grouped.keys.toList()..sort();
    final rawSplits = room['sessionSplits'] as Map?;
    final List<Map<String, dynamic>> effective = [];
    int roomSlotIdx = 0;

    for (final sIdx in sessionKeys) {
      final gSlots = grouped[sIdx]!;
      final firstSlot = gSlots.first;
      final lastSlot = gSlots.last;

      String sessionTitle = (firstSlot['sessionTitle'] ?? firstSlot['label'] ?? '${sIdx + 1}. Oturum').toString().trim();
      sessionTitle = sessionTitle.replaceAll(RegExp(r'\s*\(\d+\.\s*Devre\)\s*$', caseSensitive: false), '').trim();
      if (sessionTitle.isEmpty) sessionTitle = '${sIdx + 1}. Oturum';

      final String startStr = firstSlot['startTime']?.toString() ??
          DateFormat('HH:mm').format(DateTime(_examDate.year, _examDate.month, _examDate.day, _examTime.hour, _examTime.minute));
      final String endStr = lastSlot['endTime']?.toString() ?? '';
      final int totalDuration = gSlots
          .fold<int>(0, (acc, s) => acc + ((s['durationMinutes'] as num?)?.toInt() ?? 40))
          .clamp(5, 600);
      final int breakAfter = (lastSlot['breakMinutes'] as num?)?.toInt() ?? 0;

      final dynamic overrideRaw = rawSplits != null ? rawSplits['$sIdx'] : null;
      if (overrideRaw is Map) {
        final splitMap = Map<String, dynamic>.from(overrideRaw);
        final int splitCount = ((splitMap['splitCount'] as num?)?.toInt() ?? 1).clamp(1, 4);

        if (splitCount <= 1) {
          effective.add({
            'slotIndex': roomSlotIdx++,
            'sessionIndex': sIdx,
            'sessionTitle': sessionTitle,
            'dutyIndex': 0,
            'label': sessionTitle,
            'startTime': startStr,
            'endTime': endStr,
            'durationMinutes': totalDuration,
            'breakMinutes': breakAfter,
            'isRoomCustomSplit': gSlots.length != 1,
          });
        } else {
          List<int> durations = [];
          final rawDur = splitMap['durations'];
          if (rawDur is List && rawDur.length == splitCount) {
            durations = rawDur.map((e) => ((e as num?)?.toInt() ?? (totalDuration ~/ splitCount)).clamp(5, 600)).toList();
            final currentSum = durations.fold<int>(0, (acc, d) => acc + d);
            if (currentSum != totalDuration) {
              if (currentSum > 0 && (totalDuration - currentSum).abs() > splitCount * 2) {
                int assigned = 0;
                for (int p = 0; p < splitCount - 1; p++) {
                  final scaled = ((durations[p] * totalDuration) / currentSum).round().clamp(5, totalDuration - 5);
                  durations[p] = scaled;
                  assigned += scaled;
                }
                durations[splitCount - 1] = (totalDuration - assigned).clamp(5, 600);
              } else {
                durations[splitCount - 1] = (durations[splitCount - 1] + (totalDuration - currentSum)).clamp(5, 600);
              }
            }
          } else {
            final basePart = totalDuration ~/ splitCount;
            durations = List.generate(splitCount, (_) => basePart);
            durations[splitCount - 1] += totalDuration - (basePart * splitCount);
          }

          final parsedStart = _parseTimeOfDay(startStr);
          DateTime partStart = DateTime(
            _examDate.year,
            _examDate.month,
            _examDate.day,
            parsedStart.hour,
            parsedStart.minute,
          );

          for (int p = 0; p < splitCount; p++) {
            final pDur = durations[p];
            final partEnd = partStart.add(Duration(minutes: pDur));
            effective.add({
              'slotIndex': roomSlotIdx++,
              'sessionIndex': sIdx,
              'sessionTitle': sessionTitle,
              'dutyIndex': p,
              'label': '$sessionTitle (${p + 1}. Devre)',
              'startTime': DateFormat('HH:mm').format(partStart),
              'endTime': DateFormat('HH:mm').format(partEnd),
              'durationMinutes': pDur,
              'breakMinutes': p == splitCount - 1 ? breakAfter : 0,
              'isRoomCustomSplit': true,
            });
            partStart = partEnd;
          }
        }
      } else {
        for (final gs in gSlots) {
          effective.add({
            ...gs,
            'slotIndex': roomSlotIdx++,
            'isRoomCustomSplit': false,
          });
        }
      }
    }

    return effective;
  }

  Map<String, Map<String, dynamic>> _extractRoomSupervisorsBySessionDuty(Map<String, dynamic> room) {
    final Map<String, Map<String, dynamic>> byKey = {};
    final rawList = room['supervisors'];
    if (rawList is List && rawList.isNotEmpty) {
      for (final raw in rawList) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final supId = m['supervisorId']?.toString() ?? '';
        if (supId.isEmpty) continue;

        int sIdx;
        int dIdx;
        if (m['sessionIndex'] is num) {
          sIdx = (m['sessionIndex'] as num).toInt();
          dIdx = (m['dutyIndex'] as num?)?.toInt() ?? 0;
        } else {
          final legacySlot = (m['slotIndex'] as num?)?.toInt() ?? 0;
          if (legacySlot >= 0 && legacySlot < _sessionSlots.length) {
            sIdx = (_sessionSlots[legacySlot]['sessionIndex'] as num?)?.toInt() ?? legacySlot;
            dIdx = (_sessionSlots[legacySlot]['dutyIndex'] as num?)?.toInt() ?? 0;
          } else {
            sIdx = legacySlot;
            dIdx = 0;
          }
        }
        byKey['$sIdx:$dIdx'] = m;
      }
    } else if (room['supervisorId'] != null && room['supervisorId'].toString().isNotEmpty) {
      byKey['0:0'] = {
        'slotIndex': 0,
        'sessionIndex': 0,
        'dutyIndex': 0,
        'supervisorId': room['supervisorId'].toString(),
        'supervisorName': room['supervisorName']?.toString() ?? '',
      };
    }
    return byKey;
  }

  void _syncRoomSupervisorsWithEffectiveSlots(Map<String, dynamic> room) {
    final effectiveSlots = _getEffectiveSlotsForRoom(room);
    final byKey = _extractRoomSupervisorsBySessionDuty(room);
    final List<Map<String, dynamic>> synced = [];

    for (int i = 0; i < effectiveSlots.length; i++) {
      final slot = effectiveSlots[i];
      final sIdx = (slot['sessionIndex'] as num?)?.toInt() ?? i;
      final dIdx = (slot['dutyIndex'] as num?)?.toInt() ?? 0;
      final existing = byKey['$sIdx:$dIdx'];
      if (existing != null) {
        final supId = existing['supervisorId']?.toString() ?? '';
        if (supId.isNotEmpty) {
          synced.add({
            'slotIndex': i,
            'sessionIndex': sIdx,
            'dutyIndex': dIdx,
            'slotLabel': slot['label']?.toString() ?? '${i + 1}. Oturum',
            'startTime': slot['startTime']?.toString() ?? '',
            'endTime': slot['endTime']?.toString() ?? '',
            'durationMinutes': slot['durationMinutes'],
            'supervisorId': supId,
            'supervisorName': existing['supervisorName']?.toString() ?? '',
          });
        }
      }
    }

    room['supervisors'] = synced;
    final firstSlotSup = byKey['0:0'];
    if (firstSlotSup != null && (firstSlotSup['supervisorId']?.toString().isNotEmpty ?? false)) {
      room['supervisorId'] = firstSlotSup['supervisorId']?.toString();
      room['supervisorName'] = firstSlotSup['supervisorName']?.toString() ?? '';
    } else if (synced.isNotEmpty) {
      room['supervisorId'] = synced.first['supervisorId']?.toString();
      room['supervisorName'] = synced.first['supervisorName']?.toString() ?? '';
    } else {
      room['supervisorId'] = null;
      room['supervisorName'] = '';
    }
  }

  Map<String, dynamic>? _getSupervisorForRoomSlot(Map<String, dynamic> room, int slotIndex) {
    final effectiveSlots = _getEffectiveSlotsForRoom(room);
    if (slotIndex >= 0 && slotIndex < effectiveSlots.length) {
      final slot = effectiveSlots[slotIndex];
      final sIdx = (slot['sessionIndex'] as num?)?.toInt() ?? slotIndex;
      final dIdx = (slot['dutyIndex'] as num?)?.toInt() ?? 0;
      final byKey = _extractRoomSupervisorsBySessionDuty(room);
      final found = byKey['$sIdx:$dIdx'];
      if (found != null) return Map<String, dynamic>.from(found);
    }
    return null;
  }

  void _setSupervisorForRoomSlot(Map<String, dynamic> room, int slotIndex, String? teacherId, String? teacherName) {
    final effectiveSlots = _getEffectiveSlotsForRoom(room);
    if (slotIndex < 0 || slotIndex >= effectiveSlots.length) return;
    final slot = effectiveSlots[slotIndex];
    final sIdx = (slot['sessionIndex'] as num?)?.toInt() ?? slotIndex;
    final dIdx = (slot['dutyIndex'] as num?)?.toInt() ?? 0;

    final byKey = _extractRoomSupervisorsBySessionDuty(room);
    if (teacherId == null || teacherId.isEmpty) {
      byKey.remove('$sIdx:$dIdx');
    } else {
      byKey['$sIdx:$dIdx'] = {
        'slotIndex': slotIndex,
        'sessionIndex': sIdx,
        'dutyIndex': dIdx,
        'supervisorId': teacherId,
        'supervisorName': teacherName ?? '',
      };
    }

    final List<Map<String, dynamic>> synced = [];
    for (int i = 0; i < effectiveSlots.length; i++) {
      final sl = effectiveSlots[i];
      final slS = (sl['sessionIndex'] as num?)?.toInt() ?? i;
      final slD = (sl['dutyIndex'] as num?)?.toInt() ?? 0;
      final ex = byKey['$slS:$slD'];
      if (ex != null && (ex['supervisorId']?.toString().isNotEmpty ?? false)) {
        synced.add({
          'slotIndex': i,
          'sessionIndex': slS,
          'dutyIndex': slD,
          'slotLabel': sl['label']?.toString() ?? '${i + 1}. Oturum',
          'startTime': sl['startTime']?.toString() ?? '',
          'endTime': sl['endTime']?.toString() ?? '',
          'durationMinutes': sl['durationMinutes'],
          'supervisorId': ex['supervisorId'],
          'supervisorName': ex['supervisorName'] ?? '',
        });
      }
    }

    room['supervisors'] = synced;
    final firstSup = byKey['0:0'];
    if (firstSup != null && (firstSup['supervisorId']?.toString().isNotEmpty ?? false)) {
      room['supervisorId'] = firstSup['supervisorId']?.toString();
      room['supervisorName'] = firstSup['supervisorName']?.toString() ?? '';
    } else if (synced.isNotEmpty) {
      room['supervisorId'] = synced.first['supervisorId']?.toString();
      room['supervisorName'] = synced.first['supervisorName']?.toString() ?? '';
    } else {
      room['supervisorId'] = null;
      room['supervisorName'] = '';
    }
  }

  /// Sadece seçili salonda ilgili oturumu 1, 2, 3 veya 4 gözetmen devresine bölme modalı (Uzun basılı tutunca açılır)
  void _showRoomSessionSplitModal(Map<String, dynamic> room, int sessionIndex) {
    final baseSlots = _sessionSlots.isNotEmpty
        ? _sessionSlots
        : _computeSlotsFromConfigs(startTime: _examTime, configs: _sessionConfigs);
    final gSlots = baseSlots.where((s) => ((s['sessionIndex'] as num?)?.toInt() ?? 0) == sessionIndex).toList();
    if (gSlots.isEmpty) return;

    String sessionTitle = (gSlots.first['sessionTitle'] ?? gSlots.first['label'] ?? '${sessionIndex + 1}. Oturum')
        .toString()
        .replaceAll(RegExp(r'\s*\(\d+\.\s*Devre\)\s*$', caseSensitive: false), '')
        .trim();
    if (sessionTitle.isEmpty) sessionTitle = '${sessionIndex + 1}. Oturum';

    final String startStr = gSlots.first['startTime']?.toString() ?? '09:00';
    final String endStr = gSlots.last['endTime']?.toString() ?? '';
    final int totalDuration = gSlots
        .fold<int>(0, (acc, s) => acc + ((s['durationMinutes'] as num?)?.toInt() ?? 40))
        .clamp(8, 600);
    final int globalSplitCount = gSlots.length.clamp(1, 4);

    final rawSplits = room['sessionSplits'] as Map?;
    final existingOverride = (rawSplits != null && rawSplits['$sessionIndex'] is Map)
        ? Map<String, dynamic>.from(rawSplits['$sessionIndex'] as Map)
        : null;

    int selectedSplit = existingOverride != null
        ? (((existingOverride['splitCount'] as num?)?.toInt() ?? globalSplitCount).clamp(1, 4))
        : globalSplitCount;

    List<int> buildDefaultDurations(int count) {
      final base = totalDuration ~/ count;
      final list = List<int>.generate(count, (_) => base);
      list[count - 1] += totalDuration - (base * count);
      return list;
    }

    List<int> tempDurations;
    if (existingOverride != null &&
        existingOverride['durations'] is List &&
        (existingOverride['durations'] as List).length == selectedSplit) {
      tempDurations = (existingOverride['durations'] as List)
          .map((e) => ((e as num?)?.toInt() ?? (totalDuration ~/ selectedSplit)).clamp(5, totalDuration))
          .toList();
      final sum = tempDurations.fold<int>(0, (acc, d) => acc + d);
      if (sum != totalDuration) {
        tempDurations[selectedSplit - 1] = (tempDurations[selectedSplit - 1] + (totalDuration - sum)).clamp(5, totalDuration);
      }
    } else if (selectedSplit == globalSplitCount && gSlots.length == selectedSplit) {
      tempDurations = gSlots.map((s) => ((s['durationMinutes'] as num?)?.toInt() ?? (totalDuration ~/ selectedSplit))).toList();
    } else {
      tempDurations = buildDefaultDurations(selectedSplit);
    }

    final roomName = (room['classroomName'] ?? 'Salon').toString();
    final byKey = _extractRoomSupervisorsBySessionDuty(room);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final parsedStart = _parseTimeOfDay(startStr);
            DateTime cursor = DateTime(_examDate.year, _examDate.month, _examDate.day, parsedStart.hour, parsedStart.minute);
            final List<Map<String, String>> previewRanges = [];
            for (int p = 0; p < selectedSplit; p++) {
              final next = cursor.add(Duration(minutes: tempDurations[p]));
              previewRanges.add({
                'start': DateFormat('HH:mm').format(cursor),
                'end': DateFormat('HH:mm').format(next),
              });
              cursor = next;
            }

            void selectCount(int newCount) {
              setModalState(() {
                selectedSplit = newCount;
                tempDurations = buildDefaultDurations(newCount);
              });
            }

            void adjustPartDuration(int pIdx, int delta) {
              if (selectedSplit <= 1) return;
              final int neighborIdx = pIdx < selectedSplit - 1 ? pIdx + 1 : pIdx - 1;
              final int newVal = tempDurations[pIdx] + delta;
              final int newNeighbor = tempDurations[neighborIdx] - delta;
              if (newVal < 5 || newNeighbor < 5) return;
              setModalState(() {
                tempDurations[pIdx] = newVal;
                tempDurations[neighborIdx] = newNeighbor;
              });
            }

            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetCtx).size.height * 0.84),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3E8FF),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(Icons.call_split_rounded, color: Color(0xFF7C3AED), size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Derslik $roomName • $sessionTitle Devre Bölme',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15.5, color: const Color(0xFF1E293B)),
                                  ),
                                  Text(
                                    'Sadece bu salonda "$sessionTitle ($startStr - $endStr • $totalDuration dk)" oturumunu bölün. Diğer salonlar etkilenmez.',
                                    style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: () => Navigator.pop(sheetCtx),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Kaç Gözetmen Devresine Bölünsün?',
                                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: const Color(0xFF334155)),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [1, 2, 3, 4].map((cnt) {
                                  final bool isSelected = selectedSplit == cnt;
                                  return Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(right: cnt < 4 ? 8 : 0),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => selectCount(cnt),
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 150),
                                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                                          decoration: BoxDecoration(
                                            color: isSelected ? const Color(0xFFF3E8FF) : const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: isSelected ? const Color(0xFF7C3AED) : const Color(0xFFE2E8F0),
                                              width: isSelected ? 1.8 : 1,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                cnt == 1 ? '1 Devre' : '$cnt Devre',
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w800,
                                                  color: isSelected ? const Color(0xFF6D28D9) : const Color(0xFF1E293B),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                cnt == 1 ? 'Tek Gözetmen' : '$cnt Gözetmen',
                                                style: GoogleFonts.inter(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: isSelected ? const Color(0xFF7C3AED) : const Color(0xFF64748B),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                selectedSplit == 1
                                    ? 'Önizleme (Tek Gözetmen)'
                                    : 'Devre Saatleri & Süre Dağılımı (Toplam $totalDuration dk)',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
                              ),
                              const SizedBox(height: 8),
                              ...List.generate(selectedSplit, (p) {
                                final existingSupName = byKey['$sessionIndex:$p']?['supervisorName']?.toString() ?? '';
                                final range = previewRanges[p];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEDE9FE),
                                          borderRadius: BorderRadius.circular(7),
                                        ),
                                        child: Text(
                                          selectedSplit == 1 ? sessionTitle : '${p + 1}. Devre',
                                          style: GoogleFonts.inter(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFF6D28D9),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${range['start']} - ${range['end']}',
                                              style: GoogleFonts.inter(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFF1E293B),
                                              ),
                                            ),
                                            Text(
                                              existingSupName.isNotEmpty
                                                  ? 'Atanmış: $existingSupName'
                                                  : 'Uygulandıktan sonra gözetmen seçilebilir',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: existingSupName.isNotEmpty
                                                    ? const Color(0xFF059669)
                                                    : const Color(0xFF94A3B8),
                                                fontWeight: existingSupName.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (selectedSplit > 1) ...[
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => adjustPartDuration(p, -5),
                                          icon: const Icon(Icons.remove_circle_outline_rounded, size: 20, color: Color(0xFF64748B)),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(7),
                                            border: Border.all(color: const Color(0xFFCBD5E1)),
                                          ),
                                          child: Text(
                                            '${tempDurations[p]} dk',
                                            style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: const Color(0xFF4F46E5)),
                                          ),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => adjustPartDuration(p, 5),
                                          icon: const Icon(Icons.add_circle_outline_rounded, size: 20, color: Color(0xFF7C3AED)),
                                        ),
                                      ] else
                                        Text(
                                          '$totalDuration dk',
                                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF64748B)),
                                        ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                        child: Row(
                          children: [
                            if (existingOverride != null) ...[
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF64748B),
                                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                                  minimumSize: const Size(0, 46),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () {
                                  setState(() {
                                    final map = Map<String, dynamic>.from((room['sessionSplits'] as Map?) ?? {});
                                    map.remove('$sessionIndex');
                                    room['sessionSplits'] = map;
                                    _syncRoomSupervisorsWithEffectiveSlots(room);
                                  });
                                  Navigator.pop(sheetCtx);
                                  ScaffoldMessenger.of(this.context).showSnackBar(
                                    SnackBar(
                                      content: Text('↩️ Derslik $roomName "$sessionTitle" genel oturum düzenine döndürüldü.'),
                                      backgroundColor: const Color(0xFF475569),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.restart_alt_rounded, size: 17),
                                label: const Text('Genel Ayara Dön'),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF7C3AED),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 46),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () {
                                  setState(() {
                                    final map = Map<String, dynamic>.from((room['sessionSplits'] as Map?) ?? {});
                                    final defaultGlobalDurs = gSlots
                                        .map((s) => (s['durationMinutes'] as num?)?.toInt() ?? (totalDuration ~/ globalSplitCount))
                                        .toList();
                                    bool matchesGlobal = selectedSplit == globalSplitCount &&
                                        defaultGlobalDurs.length == tempDurations.length;
                                    if (matchesGlobal) {
                                      for (int k = 0; k < tempDurations.length; k++) {
                                        if (defaultGlobalDurs[k] != tempDurations[k]) {
                                          matchesGlobal = false;
                                          break;
                                        }
                                      }
                                    }

                                    if (matchesGlobal) {
                                      map.remove('$sessionIndex');
                                    } else {
                                      map['$sessionIndex'] = {
                                        'splitCount': selectedSplit,
                                        'durations': List<int>.from(tempDurations),
                                      };
                                    }
                                    room['sessionSplits'] = map;
                                    _syncRoomSupervisorsWithEffectiveSlots(room);
                                  });
                                  Navigator.pop(sheetCtx);
                                  ScaffoldMessenger.of(this.context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        selectedSplit == 1
                                            ? '✅ Derslik $roomName • "$sessionTitle" tek devre olarak ayarlandı!'
                                            : '✅ Derslik $roomName • "$sessionTitle" sadece bu salonda $selectedSplit devreye bölündü!',
                                      ),
                                      backgroundColor: const Color(0xFF10B981),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                                label: Text(
                                  'Sadece Bu Salona Uygula',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  int? _minutesBetweenTimes(String? startStr, String? endStr) {
    if (startStr == null || endStr == null) return null;
    final m1 = RegExp(r'(\d{1,2})[:.](\d{2})').firstMatch(startStr);
    final m2 = RegExp(r'(\d{1,2})[:.](\d{2})').firstMatch(endStr);
    if (m1 == null || m2 == null) return null;
    final startMins = (int.tryParse(m1.group(1)!) ?? 0) * 60 + (int.tryParse(m1.group(2)!) ?? 0);
    final endMins = (int.tryParse(m2.group(1)!) ?? 0) * 60 + (int.tryParse(m2.group(2)!) ?? 0);
    final diff = endMins - startMins;
    return diff > 0 ? diff : null;
  }

  /// Kayıtlı sessionSlots listesinden oturum sayısı, süreler, devre bölünmeleri ve mola düzenini birebir geri üretir.
  List<Map<String, dynamic>> _buildSessionConfigsFromRawSlots(List<dynamic> rawSlots) {
    final Map<int, List<Map<String, dynamic>>> grouped = {};
    for (int i = 0; i < rawSlots.length; i++) {
      final raw = rawSlots[i];
      if (raw is! Map) continue;
      final slot = Map<String, dynamic>.from(raw);
      final sIdx = (slot['sessionIndex'] as num?)?.toInt() ?? (slot['slotIndex'] as num?)?.toInt() ?? i;
      grouped.putIfAbsent(sIdx, () => []).add(slot);
    }

    final sessionKeys = grouped.keys.toList()..sort();
    final List<Map<String, dynamic>> configs = [];

    for (int k = 0; k < sessionKeys.length; k++) {
      final key = sessionKeys[k];
      final groupSlots = grouped[key]!;
      groupSlots.sort((a, b) {
        final da = (a['dutyIndex'] as num?)?.toInt() ?? (a['slotIndex'] as num?)?.toInt() ?? 0;
        final db = (b['dutyIndex'] as num?)?.toInt() ?? (b['slotIndex'] as num?)?.toInt() ?? 0;
        return da.compareTo(db);
      });

      final firstSlot = groupSlots.first;
      final lastSlot = groupSlots.last;

      String rawTitle = (firstSlot['sessionTitle'] ?? firstSlot['label'] ?? '${k + 1}. Oturum').toString().trim();
      rawTitle = rawTitle.replaceAll(RegExp(r'\s*\(\d+\.\s*Devre\)\s*$', caseSensitive: false), '').trim();
      if (rawTitle.isEmpty) rawTitle = '${k + 1}. Oturum';

      final List<int> splitDurations = [];
      for (final s in groupSlots) {
        final dur = (s['durationMinutes'] as num?)?.toInt() ??
            _minutesBetweenTimes(s['startTime']?.toString(), s['endTime']?.toString()) ??
            40;
        splitDurations.add(dur.clamp(5, 300));
      }
      final int totalDuration = splitDurations.fold<int>(0, (acc, d) => acc + d);

      int? breakMins = (lastSlot['breakMinutes'] as num?)?.toInt();
      if (breakMins == null) {
        if (k + 1 < sessionKeys.length) {
          final nextFirst = grouped[sessionKeys[k + 1]]!.first;
          breakMins = _minutesBetweenTimes(lastSlot['endTime']?.toString(), nextFirst['startTime']?.toString()) ?? 15;
        } else {
          breakMins = 15;
        }
      }

      final conf = <String, dynamic>{
        'title': rawTitle,
        'durationMinutes': totalDuration,
        'breakMinutes': breakMins.clamp(0, 180),
        'splitCount': groupSlots.length,
      };
      if (groupSlots.length > 1) {
        conf['customSplitDurations'] = splitDurations;
      }
      configs.add(conf);
    }

    return configs;
  }

  Future<List<Map<String, dynamic>>> _loadPreviousExamsForCopy() async {
    final List<Map<String, dynamic>> results = [];
    final Set<String> seenIds = {};
    final currentId = widget.existingDistribution?.id;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('butterfly_exams')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();
      for (final d in snap.docs) {
        if (currentId != null && currentId.isNotEmpty && d.id == currentId) continue;
        if (seenIds.add(d.id)) {
          results.add({...d.data(), '_docId': d.id});
        }
      }
    } catch (e) {
      debugPrint('butterfly_exams okuma hatası (fallback denenecek): $e');
    }

    if (results.isEmpty) {
      try {
        final snap2 = await FirebaseFirestore.instance
            .collection('seating_plans')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('type', isEqualTo: 'butterfly_exam')
            .get();
        for (final d in snap2.docs) {
          if (currentId != null && currentId.isNotEmpty && d.id == currentId) continue;
          if (seenIds.add(d.id)) {
            results.add({...d.data(), '_docId': d.id});
          }
        }
      } catch (e) {
        debugPrint('seating_plans fallback okuma hatası: $e');
      }
    }

    DateTime extractSortDate(Map<String, dynamic> m) {
      final c = m['createdAt'];
      if (c is Timestamp) return c.toDate();
      if (c is DateTime) return c;
      final ed = m['examDate'];
      if (ed is Timestamp) return ed.toDate();
      if (ed is DateTime) return ed;
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    results.sort((a, b) => extractSortDate(b).compareTo(extractSortDate(a)));
    return results;
  }

  /// Önceki Sınavdan Seçmeli Olarak Salon, Gözetmen, Oturum/Saat/Mola ve Sınav Kurallarını Çek Modalı
  Future<void> _showCopySupervisorsModal() async {
    final futureExams = _loadPreviousExamsForCopy();
    String searchQuery = '';
    final Map<String, Set<String>> activePartsByExam = {};

    Set<String> getActiveParts(String examKey) {
      return activePartsByExam.putIfAbsent(
        examKey,
        () => <String>{'rooms', 'sessions', 'supervisors', 'rules'},
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.80,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.copy_all_rounded, color: Color(0xFF4F46E5), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Önceki Sınavdan Tüm Düzeni Çek',
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B)),
                              ),
                              Text(
                                'Tüm başlıklar aktif gelir. Çekilmesini istemediğiniz başlığın üstüne tıklayarak pasif yapabilirsiniz.',
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        onChanged: (v) => setModalState(() => searchQuery = v.trim().toLowerCase()),
                        decoration: InputDecoration(
                          hintText: 'Önceki sınav adı veya ders ara...',
                          hintStyle: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF64748B)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: futureExams,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final allExams = snapshot.data ?? [];
                        final filteredExams = searchQuery.isEmpty
                            ? allExams
                            : allExams.where((data) {
                                final t = (data['title'] ?? '').toString().toLowerCase();
                                final l = (data['lessonName'] ?? '').toString().toLowerCase();
                                return t.contains(searchQuery) || l.contains(searchQuery);
                              }).toList();

                        if (filteredExams.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.history_rounded, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text(
                                  allExams.isEmpty
                                      ? 'Henüz kayıtlı önceki kelebek sınavı bulunamadı.'
                                      : 'Aramanızla eşleşen önceki sınav bulunamadı.',
                                  style: GoogleFonts.inter(color: Colors.grey.shade600, fontSize: 13.5),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredExams.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final data = filteredExams[index];
                            final String examKey = (data['_docId'] ?? 'exam_$index').toString();
                            final Set<String> activeParts = getActiveParts(examKey);

                            final examTitle = data['title']?.toString() ?? 'İsimsiz Sınav';
                            final lesson = data['lessonName']?.toString() ?? '';
                            final roomsList = (data['rooms'] as List<dynamic>?) ?? [];
                            final rawSlots = (data['sessionSlots'] as List<dynamic>?) ?? [];
                            final rawRules = (data['instructions'] as List<dynamic>?) ?? [];

                            int totalSups = 0;
                            int totalSeats = 0;
                            for (final r in roomsList) {
                              if (r is Map) {
                                if (r['supervisors'] is List && (r['supervisors'] as List).isNotEmpty) {
                                  totalSups += (r['supervisors'] as List)
                                      .where((s) => s is Map && (s['supervisorId']?.toString().isNotEmpty ?? false))
                                      .length;
                                } else if (r['supervisorId'] != null && r['supervisorId'].toString().isNotEmpty) {
                                  totalSups++;
                                }
                                if (r['seats'] is List && (r['seats'] as List).isNotEmpty) {
                                  totalSeats += (r['seats'] as List).length;
                                } else if (r['customCapacity'] is num) {
                                  totalSeats += (r['customCapacity'] as num).toInt();
                                }
                              }
                            }

                            final parsedConfigs = _buildSessionConfigsFromRawSlots(rawSlots);
                            final int sessionCnt = parsedConfigs.isNotEmpty ? parsedConfigs.length : 1;
                            String timeSummary = data['examTime']?.toString() ?? '';
                            if (rawSlots.isNotEmpty && rawSlots.first is Map && rawSlots.last is Map) {
                              final st = (rawSlots.first as Map)['startTime']?.toString() ?? '';
                              final et = (rawSlots.last as Map)['endTime']?.toString() ?? '';
                              if (st.isNotEmpty && et.isNotEmpty) {
                                timeSummary = '$st - $et';
                              }
                            }

                            DateTime? examDate;
                            final dt = data['examDate'];
                            if (dt is Timestamp) examDate = dt.toDate();

                            void togglePart(String partKey) {
                              setModalState(() {
                                if (activeParts.contains(partKey)) {
                                  activeParts.remove(partKey);
                                } else {
                                  activeParts.add(partKey);
                                }
                              });
                            }

                            final int activeCount = activeParts.length;
                            final String btnLabel = activeCount == 4
                                ? 'Tümünü Çek'
                                : (activeCount == 0 ? 'Seçim Yapın' : 'Seçilenleri Çek ($activeCount)');

                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            examTitle,
                                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14.5, color: const Color(0xFF1E293B)),
                                          ),
                                          const SizedBox(height: 5),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              if (lesson.isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFEEF2FF),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    lesson,
                                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF4F46E5)),
                                                  ),
                                                ),
                                              if (examDate != null)
                                                Text(
                                                  DateFormat('dd.MM.yyyy').format(examDate),
                                                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            children: [
                                              _buildExamCopyMetaChip(
                                                icon: Icons.meeting_room_outlined,
                                                label: totalSeats > 0
                                                    ? '${roomsList.length} Salon ($totalSeats Koltuk)'
                                                    : '${roomsList.length} Salon',
                                                color: const Color(0xFF4F46E5),
                                                isActive: activeParts.contains('rooms'),
                                                onTap: () => togglePart('rooms'),
                                              ),
                                              _buildExamCopyMetaChip(
                                                icon: Icons.schedule_rounded,
                                                label: timeSummary.isNotEmpty
                                                    ? '$sessionCnt Oturum ($timeSummary)'
                                                    : '$sessionCnt Oturum',
                                                color: const Color(0xFF0284C7),
                                                isActive: activeParts.contains('sessions'),
                                                onTap: () => togglePart('sessions'),
                                              ),
                                              _buildExamCopyMetaChip(
                                                icon: Icons.person_outline_rounded,
                                                label: '$totalSups Gözetmen',
                                                color: const Color(0xFF047857),
                                                isActive: activeParts.contains('supervisors'),
                                                onTap: () => togglePart('supervisors'),
                                              ),
                                              _buildExamCopyMetaChip(
                                                icon: Icons.gavel_rounded,
                                                label: '${rawRules.length} Kural',
                                                color: const Color(0xFF7C3AED),
                                                isActive: activeParts.contains('rules'),
                                                onTap: () => togglePart('rules'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF4F46E5),
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor: const Color(0xFFE2E8F0),
                                        disabledForegroundColor: const Color(0xFF94A3B8),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      ),
                                      icon: Icon(
                                        activeCount == 0 ? Icons.block_rounded : Icons.arrow_downward_rounded,
                                        size: 16,
                                      ),
                                      label: Text(btnLabel, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                                      onPressed: activeCount == 0
                                          ? null
                                          : () {
                                              final summaryParts = _applyFullSetupFromExam(
                                                data,
                                                activeParts: Set<String>.from(activeParts),
                                              );
                                              Navigator.pop(ctx);
                                              if (summaryParts.isNotEmpty) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('✅ "$examTitle" sınavından ${summaryParts.join(', ')} aktarıldı!'),
                                                    backgroundColor: const Color(0xFF10B981),
                                                  ),
                                                );
                                              }
                                            },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildExamCopyMetaChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    const Color passiveFg = Color(0xFF94A3B8);
    return Tooltip(
      message: isActive
          ? 'Aktif (Çekilecek) — Pasif yapmak için tıklayın'
          : 'Pasif (Çekilmeyecek) — Aktif yapmak için tıklayın',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: isActive ? color.withValues(alpha: 0.11) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive ? color.withValues(alpha: 0.45) : const Color(0xFFCBD5E1),
                width: isActive ? 1.2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isActive ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
                  size: 13.5,
                  color: isActive ? color : passiveFg,
                ),
                const SizedBox(width: 4),
                Icon(icon, size: 13, color: isActive ? color : passiveFg),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? color : passiveFg,
                    decoration: isActive ? TextDecoration.none : TextDecoration.lineThrough,
                    decorationColor: passiveFg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Seçilen önceki sınavın yalnızca aktif (seçili) bırakılan bölümlerini
  /// (`rooms`, `sessions`, `supervisors`, `rules`) bu sınava aktarır.
  List<String> _applyFullSetupFromExam(
    Map<String, dynamic> examData, {
    Set<String> activeParts = const {'rooms', 'sessions', 'supervisors', 'rules'},
  }) {
    String normName(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\-_/.]'), '');

    final bool pullRooms = activeParts.contains('rooms');
    final bool pullSessions = activeParts.contains('sessions');
    final bool pullSupervisors = activeParts.contains('supervisors');
    final bool pullRules = activeParts.contains('rules');

    final List<String> pulledSummary = [];

    String resolveTeacherName(String? tId, String? fallbackName) {
      final cleanFallback = (fallbackName ?? '').trim();
      if (cleanFallback.isNotEmpty) return cleanFallback;
      if (tId != null && tId.isNotEmpty) {
        final foundT = _availableTeachers.where((t) => t['id']?.toString() == tId).firstOrNull;
        if (foundT != null) return (foundT['name'] ?? '').toString();
      }
      return '';
    }

    ({String? primaryId, String primaryName, List<Map<String, dynamic>> list}) extractRoomSupervisors(Map<String, dynamic> pr) {
      final List<Map<String, dynamic>> resolvedSupervisors = [];
      if (pr['supervisors'] is List && (pr['supervisors'] as List).isNotEmpty) {
        for (final rawSup in (pr['supervisors'] as List)) {
          if (rawSup is! Map) continue;
          final sm = Map<String, dynamic>.from(rawSup);
          final sId = sm['supervisorId']?.toString();
          if (sId == null || sId.isEmpty) continue;
          final sSlotIdx = (sm['slotIndex'] as num?)?.toInt() ?? 0;
          final sName = resolveTeacherName(sId, sm['supervisorName']?.toString());
          resolvedSupervisors.add({
            ...sm,
            'slotIndex': sSlotIdx,
            'supervisorId': sId,
            'supervisorName': sName,
          });
        }
      }

      String? primarySupId = pr['supervisorId']?.toString();
      String primarySupName = resolveTeacherName(primarySupId, pr['supervisorName']?.toString());

      if (resolvedSupervisors.isNotEmpty) {
        final slot0 = resolvedSupervisors.firstWhere(
          (s) => s['slotIndex'] == 0,
          orElse: () => resolvedSupervisors.first,
        );
        primarySupId = slot0['supervisorId']?.toString();
        primarySupName = (slot0['supervisorName'] ?? '').toString();
      } else if (primarySupId != null && primarySupId.isNotEmpty) {
        resolvedSupervisors.add({
          'slotIndex': 0,
          'supervisorId': primarySupId,
          'supervisorName': primarySupName,
        });
      }

      return (
        primaryId: (primarySupId != null && primarySupId.isNotEmpty) ? primarySupId : null,
        primaryName: primarySupName,
        list: resolvedSupervisors,
      );
    }

    setState(() {
      if (pullSessions) {
        final rawSlots = (examData['sessionSlots'] as List<dynamic>?) ?? [];
        if (rawSlots.isNotEmpty) {
          final firstSlot = rawSlots.first;
          if (firstSlot is Map && (firstSlot['startTime']?.toString().trim().isNotEmpty ?? false)) {
            _examTime = _parseTimeOfDay(firstSlot['startTime'].toString());
          } else if (examData['examTime']?.toString().trim().isNotEmpty ?? false) {
            _examTime = _parseTimeOfDay(examData['examTime'].toString());
          }

          final parsedConfigs = _buildSessionConfigsFromRawSlots(rawSlots);
          if (parsedConfigs.isNotEmpty) {
            _sessionConfigs = parsedConfigs;
          }
          _recalcSessionSlots();
          pulledSummary.add('$_sessionCount oturum/saat-mola düzeni');
        } else if (examData['examTime']?.toString().trim().isNotEmpty ?? false) {
          final rawExamTime = examData['examTime'].toString();
          _examTime = _parseTimeOfDay(rawExamTime);
          int? durFromStr;
          if (rawExamTime.contains('-')) {
            final parts = rawExamTime.split('-');
            if (parts.length >= 2) {
              durFromStr = _minutesBetweenTimes(parts[0].trim(), parts[1].trim());
            }
          }
          _sessionConfigs = [
            {
              'title': '1. Oturum',
              'durationMinutes': durFromStr ?? 75,
              'breakMinutes': 15,
              'splitCount': 1,
            },
          ];
          _recalcSessionSlots();
          pulledSummary.add('$_sessionCount oturum/saat düzeni');
        }
      }

      if (pullRules) {
        if (examData['instructions'] is List) {
          final pulledRules = (examData['instructions'] as List)
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (pulledRules.isNotEmpty) {
            _instructions = pulledRules;
            pulledSummary.add('${_instructions.length} sınav kuralı');
          }
        }
        if (examData['showExamTitleOnPdf'] is bool) {
          _showExamTitleOnPdf = examData['showExamTitleOnPdf'] as bool;
        }
      }

      final prevRooms = (examData['rooms'] as List<dynamic>?) ?? [];
      if (pullRooms && prevRooms.isNotEmpty) {
        final existingRoomsSnapshot = List<Map<String, dynamic>>.from(_configuredRooms);
        final List<Map<String, dynamic>> rebuiltRooms = [];

        for (int i = 0; i < prevRooms.length; i++) {
          final rawRoom = prevRooms[i];
          if (rawRoom is! Map) continue;
          final pr = Map<String, dynamic>.from(rawRoom);

          final String pClassroomId = (pr['classroomId'] ?? pr['id'] ?? '').toString();
          final String pClassroomName = (pr['classroomName'] ?? pr['name'] ?? 'Salon ${i + 1}').toString();

          Map<String, dynamic>? matchedClassroom;
          if (pClassroomId.isNotEmpty) {
            matchedClassroom = _availableClassrooms.where((c) => c['id']?.toString() == pClassroomId).firstOrNull;
          }
          matchedClassroom ??= _availableClassrooms
              .where((c) => normName(c['name']?.toString() ?? '') == normName(pClassroomName))
              .firstOrNull;

          final String finalClassroomId =
              matchedClassroom?['id']?.toString() ?? (pClassroomId.isNotEmpty ? pClassroomId : 'salon_${i + 1}');
          final String finalClassroomName = pClassroomName.isNotEmpty
              ? pClassroomName
              : (matchedClassroom?['name']?.toString() ?? 'Salon ${i + 1}');

          final String pLayoutId = (pr['layoutId'] ?? '').toString();
          final String pLayoutName = (pr['layoutName'] ?? '').toString();
          ClassroomLayout? matchedLayout;

          if (pLayoutId.isNotEmpty) {
            matchedLayout = _availableLayouts.where((l) => l.id == pLayoutId).firstOrNull;
          }
          if (matchedLayout == null && pLayoutName.isNotEmpty) {
            matchedLayout = _availableLayouts
                .where((l) => l.name.toLowerCase().trim() == pLayoutName.toLowerCase().trim())
                .firstOrNull;
          }

          ClassroomLayout resolvedLayout;
          if (pr['layoutSnapshot'] is Map && (pr['layoutSnapshot'] as Map).isNotEmpty) {
            final snapMap = Map<String, dynamic>.from(pr['layoutSnapshot'] as Map);
            final effectiveId =
                matchedLayout?.id ?? (pLayoutId.isNotEmpty ? pLayoutId : 'snapshot_${finalClassroomId}_$i');
            final snapLayout = ClassroomLayout.fromMap(snapMap, effectiveId);
            if (!_availableLayouts.any((l) => l.id == snapLayout.id)) {
              _availableLayouts.add(snapLayout);
            }
            resolvedLayout = snapLayout;
          } else {
            resolvedLayout = matchedLayout ?? _findLayoutForClassroom(matchedClassroom?['layoutId']?.toString());
          }

          int resolvedCapacity;
          if (pr['customCapacity'] is num && (pr['customCapacity'] as num).toInt() > 0) {
            resolvedCapacity = (pr['customCapacity'] as num).toInt();
          } else if (pr['seats'] is List && (pr['seats'] as List).isNotEmpty) {
            resolvedCapacity = (pr['seats'] as List).length;
          } else {
            resolvedCapacity = resolvedLayout.totalCapacity;
          }

          String? roomSupId;
          String roomSupName = '';
          List<Map<String, dynamic>> roomSupList = [];

          Map<String, dynamic> roomSessionSplits = {};
          if ((pullSessions || pullSupervisors) && pr['sessionSplits'] is Map) {
            roomSessionSplits = Map<String, dynamic>.from(pr['sessionSplits'] as Map);
          }

          if (pullSupervisors) {
            final sups = extractRoomSupervisors(pr);
            roomSupId = sups.primaryId;
            roomSupName = sups.primaryName;
            roomSupList = sups.list;
          } else {
            final curMatch = existingRoomsSnapshot.where((cr) {
              final cid = cr['classroomId']?.toString() ?? '';
              final cname = normName(cr['classroomName']?.toString() ?? '');
              return (cid.isNotEmpty && cid == finalClassroomId) ||
                  (cname.isNotEmpty && cname == normName(finalClassroomName));
            }).firstOrNull;
            if (curMatch != null) {
              roomSupId = curMatch['supervisorId']?.toString();
              roomSupName = (curMatch['supervisorName'] ?? '').toString();
              if (curMatch['supervisors'] is List) {
                roomSupList = (curMatch['supervisors'] as List)
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();
              }
              if (!pullSessions && curMatch['sessionSplits'] is Map) {
                roomSessionSplits = Map<String, dynamic>.from(curMatch['sessionSplits'] as Map);
              }
            }
          }

          rebuiltRooms.add({
            'classroomId': finalClassroomId,
            'classroomName': finalClassroomName,
            'layoutId': resolvedLayout.id ?? 'preset_default',
            'layout': resolvedLayout,
            'customCapacity': resolvedCapacity,
            'supervisorId': roomSupId,
            'supervisorName': roomSupName,
            'supervisors': roomSupList,
            'sessionSplits': roomSessionSplits,
            'auto': false,
          });
        }

        if (rebuiltRooms.isNotEmpty) {
          _configuredRooms
            ..clear()
            ..addAll(rebuiltRooms);
          for (final r in _configuredRooms) {
            _syncRoomSupervisorsWithEffectiveSlots(r);
          }
          pulledSummary.insert(0, '${_configuredRooms.length} salon');
          if (pullSupervisors) {
            pulledSummary.add('gözetmenler');
          }
        }
      } else if (!pullRooms && pullSupervisors && prevRooms.isNotEmpty) {
        int matchedSupRooms = 0;
        for (int i = 0; i < _configuredRooms.length; i++) {
          final curRoom = _configuredRooms[i];
          final curName = normName(curRoom['classroomName']?.toString() ?? '');
          final curId = curRoom['classroomId']?.toString() ?? '';

          Map<String, dynamic>? matchRoom;
          for (final rawPr in prevRooms) {
            if (rawPr is! Map) continue;
            final pName = normName((rawPr['classroomName'] ?? rawPr['name'] ?? '').toString());
            final pId = (rawPr['classroomId'] ?? rawPr['id'] ?? '').toString();
            if ((pName.isNotEmpty && pName == curName) || (pId.isNotEmpty && pId == curId)) {
              matchRoom = Map<String, dynamic>.from(rawPr);
              break;
            }
          }
          if (matchRoom == null && i < prevRooms.length && prevRooms[i] is Map) {
            matchRoom = Map<String, dynamic>.from(prevRooms[i] as Map);
          }

          if (matchRoom != null) {
            final sups = extractRoomSupervisors(matchRoom);
            curRoom['supervisorId'] = sups.primaryId;
            curRoom['supervisorName'] = sups.primaryName;
            curRoom['supervisors'] = sups.list;
            if (matchRoom['sessionSplits'] is Map) {
              curRoom['sessionSplits'] = Map<String, dynamic>.from(matchRoom['sessionSplits'] as Map);
            }
            _syncRoomSupervisorsWithEffectiveSlots(curRoom);
            if (sups.primaryId != null || sups.list.isNotEmpty) {
              matchedSupRooms++;
            }
          }
        }
        pulledSummary.add('gözetmenler ($matchedSupRooms salon)');
      }
    });

    return pulledSummary;
  }

  /// Oturum Saatleri, Süreleri & Gözetmenlik Devreleri Düzenleme Modalı
  void _showEditSessionTimesModal() {
    TimeOfDay tempStartTime = _examTime;
    final tempConfigs = _sessionConfigs.map((c) => Map<String, dynamic>.from(c)).toList();
    if (tempConfigs.isEmpty) {
      tempConfigs.add({
        'title': '1. Oturum',
        'durationMinutes': 75,
        'breakMinutes': 15,
        'splitCount': 1,
      });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final previewSlots = _computeSlotsFromConfigs(
              startTime: tempStartTime,
              configs: tempConfigs,
            );

            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.more_time_rounded, color: Color(0xFF4F46E5), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Oturum, Süre & Gözetmenlik Ayarları',
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B)),
                              ),
                              Text(
                                'Her oturumun süresini bağımsız belirleyin ve oturum içi gözetmen devrelerine bölün',
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        // Sınav Başlama Saati
                        InkWell(
                          onTap: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: tempStartTime,
                            );
                            if (picked != null) {
                              setModalState(() => tempStartTime = picked);
                            }
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.schedule_rounded, color: Color(0xFF4F46E5), size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'İlk Oturum Başlangıç Saati',
                                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B)),
                                      ),
                                      Text(
                                        'Tüm sınav bu saatten itibaren planlanır',
                                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${tempStartTime.hour.toString().padLeft(2, '0')}:${tempStartTime.minute.toString().padLeft(2, '0')}',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13.5, color: const Color(0xFF4F46E5)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Oturumlar Listesi
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Sınav Oturumları (${tempConfigs.length} Oturum)',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13.5, color: const Color(0xFF1E293B)),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                              icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF4F46E5)),
                              label: Text(
                                'Yeni Oturum Ekle',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF4F46E5)),
                              ),
                              onPressed: () {
                                setModalState(() {
                                  final num = tempConfigs.length + 1;
                                  tempConfigs.add({
                                    'title': '$num. Oturum',
                                    'durationMinutes': 80,
                                    'breakMinutes': 15,
                                    'splitCount': 1,
                                  });
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Her bir oturum için özelleştirme kartı
                        for (int sIdx = 0; sIdx < tempConfigs.length; sIdx++) ...[
                          Builder(builder: (_) {
                            final conf = tempConfigs[sIdx];
                            final duration = (conf['durationMinutes'] as int?) ?? 40;
                            final breakMins = (conf['breakMinutes'] as int?) ?? 15;
                            final splitCount = (conf['splitCount'] as int?) ?? 1;
                            final isLast = sIdx == tempConfigs.length - 1;

                            // Bu oturuma ait slotları bul
                            final sessionSlots = previewSlots.where((s) => s['sessionIndex'] == sIdx).toList();

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.02),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Kart Başlığı (Oturum adı ve silme butonu)
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF4F46E5),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${sIdx + 1}',
                                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 11),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        conf['title']?.toString() ?? '${sIdx + 1}. Oturum',
                                        style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14, color: const Color(0xFF1E293B)),
                                      ),
                                      const Spacer(),
                                      if (sessionSlots.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEEF2FF),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '${sessionSlots.first['startTime']} - ${sessionSlots.last['endTime']}',
                                            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 11.5, color: const Color(0xFF4F46E5)),
                                          ),
                                        ),
                                      if (tempConfigs.length > 1) ...[
                                        const SizedBox(width: 6),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () {
                                            setModalState(() {
                                              tempConfigs.removeAt(sIdx);
                                            });
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  // Oturum Süresi Stepper ve Hızlı Çipler
                                  Row(
                                    children: [
                                      Text('Oturum Süresi:', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5, color: const Color(0xFF334155))),
                                      const Spacer(),
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline_rounded, size: 20, color: Color(0xFF64748B)),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: duration > 15
                                            ? () => setModalState(() {
                                                conf['durationMinutes'] = duration - 5;
                                                conf.remove('customSplitDurations');
                                              })
                                            : null,
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '$duration dk',
                                          style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 13, color: const Color(0xFF4F46E5)),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline_rounded, size: 20, color: Color(0xFF4F46E5)),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: duration < 240
                                            ? () => setModalState(() {
                                                conf['durationMinutes'] = duration + 5;
                                                conf.remove('customSplitDurations');
                                              })
                                            : null,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  // Hızlı Süre Butonları (40, 60, 75, 80, 90)
                                  Wrap(
                                    spacing: 6,
                                    children: [40, 60, 75, 80, 90].map((mins) {
                                      final isSel = duration == mins;
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () => setModalState(() {
                                          conf['durationMinutes'] = mins;
                                          conf.remove('customSplitDurations');
                                        }),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isSel ? const Color(0xFF4F46E5) : const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: isSel ? const Color(0xFF4F46E5) : const Color(0xFFCBD5E1)),
                                          ),
                                          child: Text(
                                            '$mins dk',
                                            style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: isSel ? Colors.white : const Color(0xFF64748B)),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 12),

                                  // Gözetmenlik Dağılımı (Kaç Gözetmene Bölünecek?)
                                  Text(
                                    'Gözetmenlik Görevlendirmesi:',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: const Color(0xFF334155)),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      // 1 Gözetmen
                                      Expanded(
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(8),
                                          onTap: () => setModalState(() {
                                            conf['splitCount'] = 1;
                                            conf.remove('customSplitDurations');
                                          }),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            decoration: BoxDecoration(
                                              color: splitCount == 1 ? const Color(0xFFEEF2FF) : const Color(0xFFF8FAFC),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: splitCount == 1 ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                                                width: splitCount == 1 ? 1.5 : 1,
                                              ),
                                            ),
                                            child: Column(
                                              children: [
                                                Icon(Icons.person_rounded, size: 16, color: splitCount == 1 ? const Color(0xFF4F46E5) : const Color(0xFF64748B)),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '1 Gözetmen',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    fontWeight: splitCount == 1 ? FontWeight.w800 : FontWeight.w600,
                                                    color: splitCount == 1 ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                                                  ),
                                                ),
                                                Text('Tüm Oturum', style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF94A3B8))),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // 2 Gözetmene Böl
                                      Expanded(
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(8),
                                          onTap: () => setModalState(() {
                                            conf['splitCount'] = 2;
                                            conf.remove('customSplitDurations');
                                          }),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            decoration: BoxDecoration(
                                              color: splitCount == 2 ? const Color(0xFFEEF2FF) : const Color(0xFFF8FAFC),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: splitCount == 2 ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                                                width: splitCount == 2 ? 1.5 : 1,
                                              ),
                                            ),
                                            child: Column(
                                              children: [
                                                Icon(Icons.group_rounded, size: 16, color: splitCount == 2 ? const Color(0xFF4F46E5) : const Color(0xFF64748B)),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '2 Gözetmene Böl',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    fontWeight: splitCount == 2 ? FontWeight.w800 : FontWeight.w600,
                                                    color: splitCount == 2 ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                                                  ),
                                                ),
                                                Text('2 Devre / Vardiya', style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF94A3B8))),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // 3 Gözetmene Böl
                                      Expanded(
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(8),
                                          onTap: () => setModalState(() {
                                            conf['splitCount'] = 3;
                                            conf.remove('customSplitDurations');
                                          }),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            decoration: BoxDecoration(
                                              color: splitCount == 3 ? const Color(0xFFEEF2FF) : const Color(0xFFF8FAFC),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: splitCount == 3 ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                                                width: splitCount == 3 ? 1.5 : 1,
                                              ),
                                            ),
                                            child: Column(
                                              children: [
                                                Icon(Icons.groups_rounded, size: 16, color: splitCount == 3 ? const Color(0xFF4F46E5) : const Color(0xFF64748B)),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '3 Gözetmene Böl',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    fontWeight: splitCount == 3 ? FontWeight.w800 : FontWeight.w600,
                                                    color: splitCount == 3 ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                                                  ),
                                                ),
                                                Text('3 Devre / Vardiya', style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF94A3B8))),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  // Eğer oturum bölünmüşse alt devre saatlerini ve süre değiştirme stepper'ını göster
                                  if (splitCount > 1) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFFCBD5E1)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.tune_rounded, size: 14, color: Color(0xFF4F46E5)),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Devre Sürelerini Ayarlayın:',
                                                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
                                              ),
                                              const Spacer(),
                                              InkWell(
                                                borderRadius: BorderRadius.circular(6),
                                                onTap: () {
                                                  setModalState(() {
                                                    conf.remove('customSplitDurations');
                                                  });
                                                },
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.refresh_rounded, size: 13, color: Color(0xFF4F46E5)),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        'Otomatik Eşit Dağıt',
                                                        style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: const Color(0xFF4F46E5)),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          for (int dIdx = 0; dIdx < sessionSlots.length; dIdx++) ...[
                                            Builder(builder: (_) {
                                              final sSlot = sessionSlots[dIdx];
                                              final slotDur = (sSlot['durationMinutes'] as int?) ?? 30;

                                              final rem = slotDur % 5;
                                              final stepDown = (rem == 0) ? 5 : rem;
                                              final stepUp = (rem == 0) ? 5 : (5 - rem);

                                              void adjust(bool isInc) {
                                                setModalState(() {
                                                  final currentDurs = List<int>.from(
                                                    (conf['customSplitDurations'] as List?)?.map((e) => e as int) ??
                                                    sessionSlots.map((s) => s['durationMinutes'] as int),
                                                  );
                                                  if (currentDurs.length != sessionSlots.length) return;

                                                  final cur = currentDurs[dIdx];
                                                  final step = isInc ? stepUp : stepDown;

                                                  int otherIdx = (dIdx + 1 < sessionSlots.length) ? dIdx + 1 : dIdx - 1;
                                                  if (otherIdx < 0 || otherIdx >= sessionSlots.length) return;

                                                  if (isInc) {
                                                    if (currentDurs[otherIdx] - step >= 10) {
                                                      currentDurs[dIdx] += step;
                                                      currentDurs[otherIdx] -= step;
                                                      conf['customSplitDurations'] = currentDurs;
                                                    }
                                                  } else {
                                                    if (cur - step >= 10) {
                                                      currentDurs[dIdx] -= step;
                                                      currentDurs[otherIdx] += step;
                                                      conf['customSplitDurations'] = currentDurs;
                                                    }
                                                  }
                                                });
                                              }

                                              void showDurationPicker() {
                                                showDialog(
                                                  context: context,
                                                  builder: (dCtx) {
                                                    final presetMinutes = [20, 25, 30, 35, 40, 45, 50, 60]
                                                        .where((m) => m >= 10 && m <= duration - 10)
                                                        .toList();

                                                    return AlertDialog(
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                      title: Row(
                                                        children: [
                                                          const Icon(Icons.schedule_rounded, color: Color(0xFF4F46E5), size: 22),
                                                          const SizedBox(width: 8),
                                                          Text(
                                                            '${dIdx + 1}. Devre Süresi',
                                                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                                                          ),
                                                        ],
                                                      ),
                                                      content: Column(
                                                        mainAxisSize: MainAxisSize.min,
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            'Toplam oturum süresi: $duration dk',
                                                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                                          ),
                                                          const SizedBox(height: 12),
                                                          Text('Hızlı Süre Seç:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                                                          const SizedBox(height: 6),
                                                          Wrap(
                                                            spacing: 8,
                                                            runSpacing: 6,
                                                            children: presetMinutes.map((m) {
                                                              final isCur = m == slotDur;
                                                              return InkWell(
                                                                borderRadius: BorderRadius.circular(8),
                                                                onTap: () {
                                                                  Navigator.pop(dCtx);
                                                                  setModalState(() {
                                                                    final currentDurs = List<int>.from(
                                                                      (conf['customSplitDurations'] as List?)?.map((e) => e as int) ??
                                                                      sessionSlots.map((s) => s['durationMinutes'] as int),
                                                                    );
                                                                    final diff = m - currentDurs[dIdx];
                                                                    int otherIdx = (dIdx + 1 < sessionSlots.length) ? dIdx + 1 : dIdx - 1;
                                                                    if (currentDurs[otherIdx] - diff >= 10) {
                                                                      currentDurs[dIdx] = m;
                                                                      currentDurs[otherIdx] -= diff;
                                                                      conf['customSplitDurations'] = currentDurs;
                                                                    }
                                                                  });
                                                                },
                                                                child: Container(
                                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                                  decoration: BoxDecoration(
                                                                    color: isCur ? const Color(0xFF4F46E5) : const Color(0xFFF1F5F9),
                                                                    borderRadius: BorderRadius.circular(8),
                                                                    border: Border.all(color: isCur ? const Color(0xFF4F46E5) : const Color(0xFFCBD5E1)),
                                                                  ),
                                                                  child: Text(
                                                                    '$m dk',
                                                                    style: GoogleFonts.inter(
                                                                      fontSize: 12,
                                                                      fontWeight: FontWeight.bold,
                                                                      color: isCur ? Colors.white : const Color(0xFF334155),
                                                                    ),
                                                                  ),
                                                                ),
                                                              );
                                                            }).toList(),
                                                          ),
                                                        ],
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(dCtx),
                                                          child: Text('Kapat', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                );
                                              }

                                              final canDown = slotDur - stepDown >= 10;
                                              int otherIdx = (dIdx + 1 < sessionSlots.length) ? dIdx + 1 : dIdx - 1;
                                              final canUp = otherIdx >= 0 &&
                                                  otherIdx < sessionSlots.length &&
                                                  (sessionSlots[otherIdx]['durationMinutes'] as int? ?? 0) - stepUp >= 10;

                                              return Container(
                                                margin: const EdgeInsets.only(bottom: 6),
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.subdirectory_arrow_right_rounded, size: 14, color: Color(0xFF4F46E5)),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            '${dIdx + 1}. Devre Gözetmeni:',
                                                            style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
                                                          ),
                                                          Text(
                                                            '${sSlot['startTime']} - ${sSlot['endTime']}',
                                                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF4F46E5)),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.remove_circle_outline_rounded, size: 20, color: Color(0xFF64748B)),
                                                      visualDensity: VisualDensity.compact,
                                                      padding: EdgeInsets.zero,
                                                      constraints: const BoxConstraints(),
                                                      onPressed: canDown ? () => adjust(false) : null,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Tooltip(
                                                      message: 'Farklı süre seçmek için tıklayın',
                                                      child: InkWell(
                                                        onTap: showDurationPicker,
                                                        borderRadius: BorderRadius.circular(6),
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFFEEF2FF),
                                                            borderRadius: BorderRadius.circular(6),
                                                            border: Border.all(color: const Color(0xFFC7D2FE)),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              Text(
                                                                '$slotDur dk',
                                                                style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 12.5, color: const Color(0xFF4F46E5)),
                                                              ),
                                                              const SizedBox(width: 3),
                                                              const Icon(Icons.edit_rounded, size: 11, color: Color(0xFF4F46E5)),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    IconButton(
                                                      icon: const Icon(Icons.add_circle_outline_rounded, size: 20, color: Color(0xFF4F46E5)),
                                                      visualDensity: VisualDensity.compact,
                                                      padding: EdgeInsets.zero,
                                                      constraints: const BoxConstraints(),
                                                      onPressed: canUp ? () => adjust(true) : null,
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],

                                  // Sonraki Oturuma Kadar Mola (Son oturum değilse)
                                  if (!isLast) ...[
                                    const SizedBox(height: 12),
                                    Divider(height: 1, color: Colors.grey.shade200),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        const Icon(Icons.coffee_rounded, size: 16, color: Color(0xFF10B981)),
                                        const SizedBox(width: 6),
                                        Text('Oturum Arası Mola:', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: const Color(0xFF10B981))),
                                        const Spacer(),
                                        IconButton(
                                          icon: const Icon(Icons.remove_circle_outline_rounded, size: 18, color: Color(0xFF64748B)),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: breakMins > 0
                                              ? () => setModalState(() => conf['breakMinutes'] = breakMins - 5)
                                              : null,
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFECFDF5),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '$breakMins dk',
                                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF10B981)),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.add_circle_outline_rounded, size: 18, color: Color(0xFF10B981)),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: breakMins < 60
                                              ? () => setModalState(() => conf['breakMinutes'] = breakMins + 5)
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),
                        ],
                        const SizedBox(height: 10),

                        // Canlı Gözetmenlik Dilimleri Önizlemesi
                        Text(
                          'Oluşacak Gözetmenlik Saatleri & Salon Atama Dilimleri (${previewSlots.length} Görev Dilimi)',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13, color: const Color(0xFF334155)),
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(previewSlots.length, (idx) {
                          final slot = previewSlots[idx];
                          final isBreak = (slot['breakMinutes'] as int? ?? 0) > 0;
                          return Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4F46E5),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${idx + 1}',
                                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 11),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '${slot['label']}:',
                                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF1E293B)),
                                      ),
                                    ),
                                    Text(
                                      '${slot['startTime']} - ${slot['endTime']}',
                                      style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13, color: const Color(0xFF4F46E5)),
                                    ),
                                  ],
                                ),
                              ),
                              if (isBreak && idx < previewSlots.length - 1)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.coffee_rounded, size: 14, color: Color(0xFF10B981)),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Ara: ${slot['breakMinutes']} Dakika Mola',
                                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF10B981)),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 6),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: Text('Vazgeç', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: Text('Saatleri & Devreleri Uygula', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                            onPressed: () {
                              setState(() {
                                _sessionConfigs = tempConfigs;
                                _examTime = tempStartTime;
                                _recalcSessionSlots();
                              });
                              Navigator.pop(ctx);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Sınav Uygulama Yönergesi Yönetimi Modalı
  void _showInstructionManagementModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final newRuleController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.gavel_rounded, color: Color(0xFF4F46E5), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sınav Uygulama Yönergesi & Kuralları',
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B)),
                              ),
                              Text(
                                'Gözetmen öğretmenlerin ve öğrencilerin uyması gereken sınav kuralları',
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Şablon Aksiyon Çubuğu
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.auto_stories_outlined, size: 16, color: Color(0xFF4F46E5)),
                            label: Text('Şablondan Yükle', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF4F46E5))),
                            onPressed: () => _pickInstructionTemplate(setModalState),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.bookmark_add_outlined, size: 16, color: Color(0xFF047857)),
                            label: Text('Şablon Olarak Kaydet', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF047857))),
                            onPressed: () => _saveAsInstructionTemplate(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Yeni Kural Ekleme Girişi
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: newRuleController,
                            decoration: InputDecoration(
                              hintText: 'Yeni bir sınav kuralı maddesi yazın...',
                              hintStyle: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF94A3B8)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
                          icon: const Icon(Icons.add_rounded, color: Colors.white),
                          onPressed: () {
                            final text = newRuleController.text.trim();
                            if (text.isNotEmpty) {
                              setState(() {
                                _instructions.add(text);
                              });
                              setModalState(() {});
                              newRuleController.clear();
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  // Hızlı Öneri Çipleri
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        _buildQuickRuleChip('+ Kitapçıklar toplanacak', 'Sınav bitiminde tüm soru kitapçıkları ve cevap kâğıtları eksiksiz toplanacaktır.', setModalState),
                        const SizedBox(width: 6),
                        _buildQuickRuleChip('+ Kitapçıklar dağıtılacak', 'Sınav bitiminde soru kitapçıkları öğrencilere dağıtılacaktır.', setModalState),
                        const SizedBox(width: 6),
                        _buildQuickRuleChip('+ İlk 15 dk çıkış yok', 'Sınavın ilk 15 dakikası hiçbir öğrencinin salondan çıkışına izin verilmeyecektir.', setModalState),
                        const SizedBox(width: 6),
                        _buildQuickRuleChip('+ Optik form kurşun kalem', 'Cevap kâğıtları yalnızca kurşun kalem ile doldurulmalı ve taşırılmadan kodlanmalıdır.', setModalState),
                        const SizedBox(width: 6),
                        _buildQuickRuleChip('+ Mühürlü poşet kontrolü', 'Sınav evrak poşeti öğrencilerin huzurunda açılarak kontrol edilmelidir.', setModalState),
                      ],
                    ),
                  ),

                  const Divider(height: 14),

                  // Kural Maddeleri Listesi
                  Expanded(
                    child: _instructions.isEmpty
                        ? Center(
                            child: Text(
                              'Henüz sınav kuralı maddesi eklenmedi.',
                              style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 13),
                            ),
                          )
                        : ReorderableListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            buildDefaultDragHandles: false,
                            itemCount: _instructions.length,
                            onReorderItem: (oldIndex, newIndex) {
                              setState(() {
                                final item = _instructions.removeAt(oldIndex);
                                _instructions.insert(newIndex.clamp(0, _instructions.length), item);
                              });
                              setModalState(() {});
                            },
                            itemBuilder: (context, idx) {
                              return Container(
                                key: ValueKey('instruction_${idx}_${_instructions[idx].hashCode}'),
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  children: [
                                    // Sürükleme Tutamacı
                                    ReorderableDragStartListener(
                                      index: idx,
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.grab,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          child: const Icon(Icons.drag_indicator_rounded, size: 20, color: Color(0xFF94A3B8)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    // Sıra Numarası
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEEF2FF),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${idx + 1}',
                                        style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 12, color: const Color(0xFF4F46E5)),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // Madde Metni
                                    Expanded(
                                      child: Text(
                                        _instructions[idx],
                                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B), height: 1.35),
                                      ),
                                    ),
                                    // Tıklamayla Hızlı Sıralama (Yukarı / Aşağı Oklar)
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        InkWell(
                                          onTap: idx > 0
                                              ? () {
                                                  setState(() {
                                                    final item = _instructions.removeAt(idx);
                                                    _instructions.insert(idx - 1, item);
                                                  });
                                                  setModalState(() {});
                                                }
                                              : null,
                                          child: Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: idx > 0 ? const Color(0xFF64748B) : Colors.transparent),
                                        ),
                                        InkWell(
                                          onTap: idx < _instructions.length - 1
                                              ? () {
                                                  setState(() {
                                                    final item = _instructions.removeAt(idx);
                                                    _instructions.insert(idx + 1, item);
                                                  });
                                                  setModalState(() {});
                                                }
                                              : null,
                                          child: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: idx < _instructions.length - 1 ? const Color(0xFF64748B) : Colors.transparent),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 4),
                                    // Silme Butonu
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () {
                                        setState(() {
                                          _instructions.removeAt(idx);
                                        });
                                        setModalState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),

                  // Alt Buton
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Yönergeyi Kaydet & Kapat (${_instructions.length} Madde)', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuickRuleChip(String label, String fullText, StateSetter setModalState) {
    return ActionChip(
      label: Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF475569))),
      backgroundColor: const Color(0xFFF1F5F9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFFE2E8F0))),
      onPressed: () {
        if (!_instructions.contains(fullText)) {
          setState(() {
            _instructions.add(fullText);
          });
          setModalState(() {});
        }
      },
    );
  }

  String get _instructionTemplatesPrefsKey => 'exam_instruction_templates_${widget.institutionId}';

  Future<List<Map<String, dynamic>>> _loadSavedInstructionTemplates() async {
    final List<Map<String, dynamic>> merged = [];
    final Set<String> seenKeys = {};

    void addTemplateItem({
      required String id,
      required String source,
      required String title,
      required List<String> rules,
      required int createdAtMs,
    }) {
      final cleanTitle = title.trim();
      final cleanRules = rules.map((e) => e.trim()).where((s) => s.isNotEmpty).toList();
      if (cleanTitle.isEmpty || cleanRules.isEmpty) return;
      final dedupKey = cleanTitle.toLowerCase();
      if (!seenKeys.add(dedupKey)) return;
      merged.add({
        'id': id,
        'source': source,
        'title': cleanTitle,
        'rules': cleanRules,
        'createdAtMs': createdAtMs,
      });
    }

    int parseCreatedMs(dynamic raw) {
      if (raw is Timestamp) return raw.millisecondsSinceEpoch;
      if (raw is DateTime) return raw.millisecondsSinceEpoch;
      if (raw is num) return raw.toInt();
      return 0;
    }

    // 1. Kurum alt koleksiyonu (institutions/{instId}/exam_instruction_templates)
    try {
      final instSnap = await FirebaseFirestore.instance
          .collection('institutions')
          .doc(widget.institutionId)
          .collection('exam_instruction_templates')
          .get();
      final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(instSnap.docs);
      docs.sort((a, b) => parseCreatedMs(b.data()['createdAt']).compareTo(parseCreatedMs(a.data()['createdAt'])));
      for (final d in docs) {
        final data = d.data();
        final rawList = (data['instructions'] ?? data['rules']) as List<dynamic>? ?? [];
        addTemplateItem(
          id: d.id,
          source: 'institution',
          title: (data['title'] ?? '').toString(),
          rules: rawList.map((e) => e.toString()).toList(),
          createdAtMs: parseCreatedMs(data['createdAt']),
        );
      }
    } catch (e) {
      debugPrint('Kurum yönerge şablonları okunamadı: $e');
    }

    // 2. Üst seviye koleksiyon fallback (exam_instruction_templates)
    try {
      final topSnap = await FirebaseFirestore.instance
          .collection('exam_instruction_templates')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();
      final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(topSnap.docs);
      docs.sort((a, b) => parseCreatedMs(b.data()['createdAt']).compareTo(parseCreatedMs(a.data()['createdAt'])));
      for (final d in docs) {
        final data = d.data();
        final rawList = (data['instructions'] ?? data['rules']) as List<dynamic>? ?? [];
        addTemplateItem(
          id: d.id,
          source: 'top',
          title: (data['title'] ?? '').toString(),
          rules: rawList.map((e) => e.toString()).toList(),
          createdAtMs: parseCreatedMs(data['createdAt']),
        );
      }
    } catch (_) {}

    // 3. Yerel önbellek fallback (SharedPreferences)
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawJson = prefs.getString(_instructionTemplatesPrefsKey);
      if (rawJson != null && rawJson.isNotEmpty) {
        final decoded = jsonDecode(rawJson);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final rawList = (item['rules'] ?? item['instructions']) as List<dynamic>? ?? [];
              addTemplateItem(
                id: (item['id'] ?? '').toString(),
                source: 'local',
                title: (item['title'] ?? '').toString(),
                rules: rawList.map((e) => e.toString()).toList(),
                createdAtMs: parseCreatedMs(item['createdAtMs']),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Yerel yönerge şablonları okunamadı: $e');
    }

    merged.sort((a, b) => ((b['createdAtMs'] as int?) ?? 0).compareTo((a['createdAtMs'] as int?) ?? 0));
    return merged;
  }

  Future<void> _saveTemplateToLocalCache({
    required String id,
    required String title,
    required List<String> rules,
    required int createdAtMs,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> current = [];
      final rawJson = prefs.getString(_instructionTemplatesPrefsKey);
      if (rawJson != null && rawJson.isNotEmpty) {
        final decoded = jsonDecode(rawJson);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final existingTitle = (item['title'] ?? '').toString().trim().toLowerCase();
              if (existingTitle != title.trim().toLowerCase()) {
                current.add(Map<String, dynamic>.from(item));
              }
            }
          }
        }
      }
      current.insert(0, {
        'id': id,
        'title': title.trim(),
        'rules': rules,
        'createdAtMs': createdAtMs,
      });
      await prefs.setString(_instructionTemplatesPrefsKey, jsonEncode(current));
    } catch (e) {
      debugPrint('Yerel şablon önbelleği yazılamadı: $e');
    }
  }

  Future<void> _deleteSavedInstructionTemplate(Map<String, dynamic> tpl) async {
    final String id = (tpl['id'] ?? '').toString();
    final String titleLower = (tpl['title'] ?? '').toString().trim().toLowerCase();

    if (id.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('institutions')
            .doc(widget.institutionId)
            .collection('exam_instruction_templates')
            .doc(id)
            .delete();
      } catch (_) {}
      try {
        await FirebaseFirestore.instance.collection('exam_instruction_templates').doc(id).delete();
      } catch (_) {}
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final rawJson = prefs.getString(_instructionTemplatesPrefsKey);
      if (rawJson != null && rawJson.isNotEmpty) {
        final decoded = jsonDecode(rawJson);
        if (decoded is List) {
          final remaining = decoded.where((item) {
            if (item is! Map) return false;
            final itemId = (item['id'] ?? '').toString();
            final itemTitle = (item['title'] ?? '').toString().trim().toLowerCase();
            return itemId != id && itemTitle != titleLower;
          }).toList();
          await prefs.setString(_instructionTemplatesPrefsKey, jsonEncode(remaining));
        }
      }
    } catch (_) {}
  }

  Future<void> _pickInstructionTemplate(StateSetter setModalState) async {
    final defaultTemplates = [
      {
        'title': 'MEB Standart Ortak Sınav Yönergesi',
        'rules': [
          'Gözetmen öğretmenler sınav başlangıç saatinden 15 dakika önce sınav evraklarını idareden teslim almalıdır.',
          'Öğrenciler sınav salonuna cep telefonu, akıllı saat veya haberleşme araçlarıyla giremez.',
          'Sınav başlamadan önce öğrencilerin kimlik ve salon oturma planı kontrolleri eksiksiz yapılmalıdır.',
          'Sınav evrak poşeti öğrenciler huzurunda açılarak optik form ve kitapçıklar kontrol edilmelidir.',
          'Sınavın ilk 15 dakikası ve son 10 dakikası hiçbir öğrencinin salondan çıkışına izin verilmez.',
          'Sınav bitiminde sınav evrakları eksiksiz toplanarak salon yoklama tutanağı gözetmen tarafından imzalanmalıdır.',
        ],
      },
      {
        'title': 'Kurumsal Deneme Sınavı (Kitapçık Toplamalı)',
        'rules': [
          'Gözetmenler sınav salonunda öğrencilerin kelebek oturma düzenine tam uymalarını sağlar.',
          'Optik formlardaki ad, soyad ve numara kodlamalarının doğruluğu gözetmen tarafından kontrol edilip paraflanır.',
          'Tüm soru kitapçıkları ve optik cevap kâğıtları sınav süresi bitiminde eksiksiz toplanacaktır.',
          'Cevap kâğıdı teslim alınmayan hiçbir öğrenci salondan ayrılamaz.',
        ],
      },
      {
        'title': 'Çoklu Oturum Ara Vermeli Deneme Sınavı',
        'rules': [
          '1. Oturum süresi bitiminde öğrenciler mola alanına çıkarılır, 2. Oturum için zamanında salonda hazır bulunmaları hatırlatılır.',
          '1. Oturum soru kitapçıkları toplanır, 2. Oturum evrakları ara bitiminde dağıtılır.',
          'Her iki oturumda da salon yoklaması gözetmenlerce ayrı ayrı teyit edilir.',
          'Mola esnasında öğrencilerin sınav salonlarında başıboş kalmasına müsaade edilmez.',
        ],
      },
    ];

    List<Map<String, dynamic>> customTemplates = [];
    bool isLoadingCustom = true;
    bool didTriggerLoad = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (!didTriggerLoad) {
              didTriggerLoad = true;
              _loadSavedInstructionTemplates().then((loaded) {
                if (sheetCtx.mounted) {
                  setSheetState(() {
                    customTemplates = loaded;
                    isLoadingCustom = false;
                  });
                }
              });
            }

            Widget buildTemplateCard({
              required String title,
              required List<String> rules,
              required bool isCustom,
              VoidCallback? onDelete,
            }) {
              final String previewText = rules.isNotEmpty ? rules.first : '';
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  setState(() {
                    _instructions = List<String>.from(rules);
                  });
                  setModalState(() {});
                  Navigator.pop(sheetCtx);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text('✅ "$title" şablonu yüklendi (${rules.length} madde)'),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isCustom ? const Color(0xFFF5F3FF) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isCustom ? const Color(0xFFDDD6FE) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isCustom ? const Color(0xFFC4B5FD) : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Icon(
                          isCustom ? Icons.bookmark_added_rounded : Icons.description_outlined,
                          color: isCustom ? const Color(0xFF7C3AED) : const Color(0xFF4F46E5),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                      color: const Color(0xFF1E293B),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isCustom) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEDE9FE),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Kayıtlı',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF6D28D9),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${rules.length} kural maddesi içerir',
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                            ),
                            if (previewText.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                '• $previewText',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (onDelete != null) ...[
                        IconButton(
                          tooltip: 'Şablonu Sil',
                          icon: const Icon(Icons.delete_outline_rounded, size: 19, color: Color(0xFFEF4444)),
                          onPressed: onDelete,
                        ),
                      ] else
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
                    ],
                  ),
                ),
              );
            }

            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetCtx).size.height * 0.82),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.auto_stories_outlined, color: Color(0xFF4F46E5), size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Yönerge Şablonu Seçin',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B)),
                                  ),
                                  Text(
                                    'Kayıtlı özel şablonlarınızı veya hazır sistem şablonlarını yükleyin',
                                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: () => Navigator.pop(sheetCtx),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.bookmark_rounded, size: 15, color: Color(0xFF7C3AED)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Kayıtlı Şablonlarım (${customTemplates.length})',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF6D28D9),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (isLoadingCustom)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2.2),
                                    ),
                                  ),
                                )
                              else if (customTemplates.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Text(
                                    'Henüz kaydettiğiniz özel bir şablon bulunmuyor. "Şablon Olarak Kaydet" butonuyla oluşturduğunuz şablonlar burada listelenir.',
                                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                  ),
                                )
                              else
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: customTemplates.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (context, i) {
                                    final ct = customTemplates[i];
                                    final rList = List<String>.from(ct['rules'] as List);
                                    return buildTemplateCard(
                                      title: ct['title'] as String,
                                      rules: rList,
                                      isCustom: true,
                                      onDelete: () async {
                                        await _deleteSavedInstructionTemplate(ct);
                                        if (sheetCtx.mounted) {
                                          setSheetState(() {
                                            customTemplates.removeAt(i);
                                          });
                                        }
                                        if (mounted) {
                                          ScaffoldMessenger.of(this.context).showSnackBar(
                                            SnackBar(
                                              content: Text('🗑️ "${ct['title']}" şablonu silindi.'),
                                              backgroundColor: const Color(0xFF475569),
                                            ),
                                          );
                                        }
                                      },
                                    );
                                  },
                                ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  const Icon(Icons.verified_outlined, size: 15, color: Color(0xFF4F46E5)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Hazır Sistem Şablonları (${defaultTemplates.length})',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF4338CA),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: defaultTemplates.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, i) {
                                  final t = defaultTemplates[i];
                                  final rList = t['rules'] as List<String>;
                                  return buildTemplateCard(
                                    title: t['title'] as String,
                                    rules: rList,
                                    isCustom: false,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveAsInstructionTemplate() async {
    if (_instructions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Şablon olarak kaydetmek için önce en az 1 sınav kuralı maddesi ekleyin.'),
          backgroundColor: Color(0xFFF59E0B),
        ),
      );
      return;
    }

    final titleController = TextEditingController();
    String? errorText;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submitSave() async {
              final tName = titleController.text.trim();
              if (tName.isEmpty) {
                setDialogState(() {
                  errorText = 'Lütfen şablon için bir ad girin.';
                });
                return;
              }
              setDialogState(() {
                errorText = null;
                isSaving = true;
              });

              final int nowMs = DateTime.now().millisecondsSinceEpoch;
              final rulesSnapshot = List<String>.from(_instructions);
              String savedId = 'local_$nowMs';

              try {
                final colRef = FirebaseFirestore.instance
                    .collection('institutions')
                    .doc(widget.institutionId)
                    .collection('exam_instruction_templates');

                final existingSnap = await colRef.get();
                QueryDocumentSnapshot<Map<String, dynamic>>? sameTitleDoc;
                for (final d in existingSnap.docs) {
                  final dt = (d.data()['title'] ?? '').toString().trim().toLowerCase();
                  if (dt == tName.toLowerCase()) {
                    sameTitleDoc = d;
                    break;
                  }
                }

                final payload = <String, dynamic>{
                  'institutionId': widget.institutionId,
                  'title': tName,
                  'instructions': rulesSnapshot,
                  'createdAt': Timestamp.fromMillisecondsSinceEpoch(nowMs),
                };

                if (sameTitleDoc != null) {
                  await sameTitleDoc.reference.set(payload);
                  savedId = sameTitleDoc.id;
                } else {
                  final added = await colRef.add(payload);
                  savedId = added.id;
                }
              } catch (e) {
                debugPrint('Firestore şablon kaydı uyarısı (yerel önbelleğe kaydedilecek): $e');
              }

              await _saveTemplateToLocalCache(
                id: savedId,
                title: tName,
                rules: rulesSnapshot,
                createdAtMs: nowMs,
              );

              if (dialogCtx.mounted) {
                Navigator.pop(dialogCtx);
              }
              if (mounted) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text('✅ "$tName" şablon olarak kaydedildi! "Şablondan Yükle" bölümünden açabilirsiniz.'),
                    backgroundColor: const Color(0xFF10B981),
                  ),
                );
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                'Yönergeyi Şablon Olarak Kaydet',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Mevcut ${_instructions.length} adet kural maddesini daha sonraki sınavlarınızda "Şablondan Yükle" menüsünden tek tıkla açmak üzere kaydedin.',
                    style: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    onSubmitted: (_) => isSaving ? null : submitSave(),
                    onChanged: (_) {
                      if (errorText != null) {
                        setDialogState(() => errorText = null);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Şablon Adı (Örn: Okul Standart Sınav Yönergesi)',
                      errorText: errorText,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('Vazgeç'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isSaving ? null : submitSave,
                  icon: isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.bookmark_add_outlined, size: 17),
                  label: Text(isSaving ? 'Kaydediliyor...' : 'Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 1. Tanımlanmış Deneme Sınavlarını Yükle
  Future<void> _loadTrialExams() async {
    try {
      final activeTermId = await TermService().getSelectedTermId() ?? await TermService().getActiveTermId();
      final snap = await FirebaseFirestore.instance
          .collection('trial_exams')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      final list = snap.docs
          .map((d) => TrialExam.fromMap(d.data(), d.id))
          .where((e) => activeTermId == null || activeTermId.isEmpty || e.termId == activeTermId)
          .toList();
      list.sort((a, b) => b.date.compareTo(a.date));

      if (mounted) {
        setState(() {
          _availableTrialExams = list;
        });
      }
    } catch (e) {
      debugPrint('Deneme sınavları yüklenirken hata: $e');
    }
  }

  /// 2. Şubeleri Yükle
  Future<void> _loadClasses() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final activeTermId = await TermService().getSelectedTermId() ?? await TermService().getActiveTermId();
      final seen = <String>{};
      final list = <Map<String, dynamic>>[];
      for (final d in snap.docs) {
        final data = d.data();
        if (data['isActive'] == false) continue;
        final tid = data['termId']?.toString() ?? '';
        if (activeTermId != null && activeTermId.isNotEmpty && tid.isNotEmpty && tid != activeTermId) continue;
        final cName = (data['className']?.toString() ??
                data['name']?.toString() ??
                data['shortName']?.toString() ??
                'Şube')
            .trim();
        // Aynı şube adı birden fazla kayıtta olabilir (eski dönem/kopya) -> tekilleştir.
        if (!seen.add(cName.toUpperCase())) continue;
        final gLevel = data['classLevel']?.toString() ??
            data['gradeLevel']?.toString() ??
            (cName.split('-').first.replaceAll(RegExp(r'[^0-9]'), ''));
        list.add({
          'id': d.id,
          'name': cName,
          'gradeLevel': gLevel.isNotEmpty ? '$gLevel. Sınıf' : '',
          'rawLevel': gLevel.replaceAll(RegExp(r'[^0-9]'), ''),
          'studentCount': data['studentCount'] ?? 0,
        });
      }

      list.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      if (mounted) {
        setState(() {
          _availableClasses = list;
          _isLoadingClasses = false;
        });
      }
    } catch (e) {
      debugPrint('Sınıflar yüklenirken hata: $e');
      if (mounted) setState(() => _isLoadingClasses = false);
    }
  }

  /// 3. Masa Şablonlarını Yükle
  Future<void> _loadLayouts() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('seating_layouts')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      List<ClassroomLayout> layouts = snap.docs
          .map((d) => ClassroomLayout.fromMap(d.data(), d.id))
          .toList();

      if (layouts.isEmpty) {
        layouts = [
          ClassroomLayout.createPreset(
            presetType: '3_col_double_with_aisles',
            name: 'Standart 3 Blok (18 Masa / 36 Koltuk)',
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
          ),
          ClassroomLayout.createPreset(
            presetType: '3_col_double',
            name: '2 Geniş Blok (16 Masa / 32 Koltuk)',
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
          ),
          ClassroomLayout.createPreset(
            presetType: '2_col_single',
            name: 'Tekli Sınav Düzeni (20 Masa / 20 Koltuk)',
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
          ),
        ];
      }

      if (mounted) {
        setState(() {
          _availableLayouts = layouts;
          _isLoadingLayouts = false;
        });
      }
    } catch (e) {
      debugPrint('Şablonlar yüklenirken hata: $e');
      if (mounted) {
        setState(() {
          _availableLayouts = [
            ClassroomLayout.createPreset(
              presetType: '3_col_double_with_aisles',
              name: 'Standart 3 Blok (18 Masa / 36 Koltuk)',
              institutionId: widget.institutionId,
              schoolTypeId: widget.schoolTypeId,
            ),
          ];
          _isLoadingLayouts = false;
        });
      }
    }
  }

  /// 4. Derslikleri Yükle (Derslik Adı Temiz & Şifresiz)
  Future<void> _loadClassrooms() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('classrooms')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final list = snap.docs.asMap().entries.map((entry) {
        final idx = entry.key;
        final d = entry.value;
        final data = d.data();
        final cName = data['classroomName']?.toString() ??
            data['name']?.toString() ??
            data['classroomCode']?.toString() ??
            data['code']?.toString() ??
            'Salon ${idx + 1}';

        final cap = (data['capacity'] as num?)?.toInt() ?? 24;

        return {
          'id': d.id,
          'name': cName,
          'capacity': cap,
          'layoutId': data['layoutId']?.toString() ?? data['seatingLayoutId']?.toString(),
        };
      }).toList();

      list.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      if (mounted) {
        setState(() {
          _availableClassrooms = list;
          _isLoadingClassrooms = false;

          // Varsayılan salonları derslik listesinden oluştur
          if (_configuredRooms.isEmpty) {
            final defaultLayout = _availableLayouts.isNotEmpty ? _availableLayouts.first : null;
            final defaultLayoutId = defaultLayout?.id ?? 'preset_default';

            if (list.isNotEmpty) {
              for (int i = 0; i < list.length.clamp(1, 2); i++) {
                final cr = list[i];
                final l = _findLayoutForClassroom(cr['layoutId'] as String?);
                _configuredRooms.add({
                  'classroomId': cr['id'] as String,
                  'classroomName': cr['name'] as String,
                  'layoutId': l.id ?? defaultLayoutId,
                  'layout': l,
                  'customCapacity': (cr['capacity'] as int?) ?? l.totalCapacity,
                  'supervisorId': null,
                  'supervisorName': '',
                  'auto': i > 0,
                });
              }
            } else {
              final l = _findLayoutForClassroom(null);
              _configuredRooms.add({
                'classroomId': 'salon_1',
                'classroomName': 'Salon 1',
                'layoutId': l.id ?? defaultLayoutId,
                'layout': l,
                'customCapacity': l.totalCapacity,
                'supervisorId': null,
                'supervisorName': '',
              });
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Derslikler yüklenirken hata: $e');
      if (mounted) setState(() => _isLoadingClassrooms = false);
    }
  }

  /// 5. Öğretmenleri ve Gerçek İsimlerini Yükle
  Future<void> _loadTeachers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final list = snap.docs.where((d) {
        final data = d.data();
        final role = data['role']?.toString().toLowerCase() ?? '';
        return role == 'teacher' || role == 'ogretmen' || role == 'admin' || role == 'manager' || data['branch'] != null;
      }).map((d) {
        final data = d.data();

        // Tüm olası isim alanlarını tara
        final String fullName = (data['fullName']?.toString() ??
            data['displayName']?.toString() ??
            data['nameSurname']?.toString() ??
            '${data['name'] ?? data['firstName'] ?? ''} ${data['surname'] ?? data['lastName'] ?? ''}').trim();

        final String finalName = fullName.isNotEmpty ? fullName : (data['email']?.toString() ?? 'Öğretmen');
        final branch = data['branch']?.toString() ?? data['department']?.toString() ?? 'Öğretmen';

        return {
          'id': d.id,
          'name': finalName,
          'branch': branch,
          'isAvailable': true,
          'busyInfo': '',
        };
      }).toList();

      list.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      if (mounted) {
        setState(() {
          _availableTeachers = list;
          _isLoadingTeachers = false;
        });
      }
    } catch (e) {
      debugPrint('Öğretmenler yüklenirken hata: $e');
      if (mounted) setState(() => _isLoadingTeachers = false);
    }
  }

  ClassroomLayout _findLayoutForClassroom(String? layoutId) {
    if (layoutId != null && layoutId.isNotEmpty && _availableLayouts.isNotEmpty) {
      final match = _availableLayouts.where((l) => l.id == layoutId);
      if (match.isNotEmpty) return match.first;
    }
    if (_availableLayouts.isNotEmpty) {
      return _availableLayouts.first;
    }
    return ClassroomLayout.createPreset(
      presetType: '3_col_double_with_aisles',
      name: 'Standart 3 Blok (18 Masa / 36 Koltuk)',
      institutionId: widget.institutionId,
      schoolTypeId: widget.schoolTypeId,
    );
  }

  // ===========================================================================
  // MODALLER: DENEME SINAVI, DERSLİK VE GÖZETMEN SEÇİCİLER
  // ===========================================================================
  void _onTrialExamSelected(TrialExam? exam) {
    setState(() {
      _selectedTrialExam = exam;
      if (exam != null) {
        _titleController.text = exam.name;
        _lessonController.text = exam.examTypeName.isNotEmpty ? exam.examTypeName : 'Deneme Sınavı';
        _examDate = exam.date;

        _selectedClassIds.clear();
        final targetLevel = exam.classLevel.replaceAll(RegExp(r'[^0-9]'), '');

        for (final cls in _availableClasses) {
          final clsLevel = (cls['rawLevel'] as String?)?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
          final clsName = cls['name'] as String;

          final matchesLevel = targetLevel.isNotEmpty && clsLevel == targetLevel;
          final matchesBranch = exam.selectedBranches.any((b) => clsName.contains(b));

          if (matchesLevel || matchesBranch) {
            _selectedClassIds.add(cls['id'] as String);
          }
        }
      }
    });
  }

  /// Deneme Sınavı Arama ve Seçim Bottom Sheet Modalı
  void _showTrialExamPickerBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _availableTrialExams.where((e) {
              final q = searchQuery.toLowerCase();
              return e.name.toLowerCase().contains(q) ||
                  e.classLevel.toLowerCase().contains(q) ||
                  e.examTypeName.toLowerCase().contains(q);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.65,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Deneme Sınavı Seçin',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        autofocus: false,
                        decoration: InputDecoration(
                          hintText: 'Deneme sınavı adı veya sınıf ara...',
                          hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onChanged: (val) {
                          setModalState(() => searchQuery = val);
                        },
                      ),
                    ),
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Uygun deneme sınavı bulunamadı.',
                              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, idx) {
                              final exam = filtered[idx];
                              final isSelected = _selectedTrialExam?.id == exam.id;
                              final dStr = DateFormat('dd.MM.yyyy').format(exam.date);

                              return InkWell(
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _onTrialExamSelected(exam);
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          Icons.assignment_rounded,
                                          color: isSelected ? Colors.white : const Color(0xFF4F46E5),
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              exam.name,
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                                color: const Color(0xFF1E293B),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${exam.classLevel} • $dStr • ${exam.examTypeName}',
                                              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected)
                                        const Icon(Icons.check_circle_rounded, color: Color(0xFF4F46E5), size: 20),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Derslik Seçim Modalı (Arama Çubuklu & Kompakt)
  void _showClassroomPickerModal(Map<String, dynamic> room) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _availableClassrooms.where((c) {
              final q = searchQuery.toLowerCase();
              final name = (c['name'] as String).toLowerCase();
              return name.contains(q);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.60,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Sınav Salonu / Derslik Seçin',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        autofocus: false,
                        decoration: InputDecoration(
                          hintText: 'Derslik veya salon adı ara...',
                          hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onChanged: (val) {
                          setModalState(() => searchQuery = val);
                        },
                      ),
                    ),
                  ),
                  const Divider(height: 14),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, idx) {
                        final cr = filtered[idx];
                        final isSelected = room['classroomId'] == cr['id'];

                        return InkWell(
                          onTap: () {
                            setState(() {
                              room['classroomId'] = cr['id'];
                              room['classroomName'] = cr['name'];
                              room['customCapacity'] = (cr['capacity'] as int?) ?? 24;
                              if (cr['layoutId'] != null) {
                                final l = _findLayoutForClassroom(cr['layoutId']);
                                room['layout'] = l;
                                room['layoutId'] = l.id;
                              }
                              // Manuel seçim: bu salon artik otomatik değil; sonrakiler (otomatik olanlar) sıraya girer.
                              room['auto'] = false;
                              _reflowAutoRooms();
                            });
                            Navigator.pop(ctx);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.meeting_room_rounded, color: Color(0xFF4F46E5), size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cr['name'] as String,
                                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5, color: const Color(0xFF1E293B)),
                                      ),
                                      Text(
                                        'Kapasite: ${cr['capacity']} Koltuk',
                                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle_rounded, color: Color(0xFF4F46E5), size: 20),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Gözetmen Öğretmen Seçim Modalı (Öğretmen İsimleri Net, Müsaitler Yeşil Üstte)
  void _showSupervisorPickerModal(Map<String, dynamic> room, [int slotIndex = 0]) {
    final currentSup = _getSupervisorForRoomSlot(room, slotIndex);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _availableTeachers.where((t) {
              final q = searchQuery.toLowerCase();
              final name = (t['name'] as String).toLowerCase();
              final branch = (t['branch'] as String).toLowerCase();
              return name.contains(q) || branch.contains(q);
            }).toList();

            filtered.sort((a, b) {
              final aAv = (a['isAvailable'] as bool?) ?? true;
              final bAv = (b['isAvailable'] as bool?) ?? true;
              if (aAv == bAv) {
                return (a['name'] as String).compareTo(b['name'] as String);
              }
              return aAv ? -1 : 1;
            });

            return Container(
              height: MediaQuery.of(context).size.height * 0.60,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Builder(
                            builder: (_) {
                              final rSlots = _getEffectiveSlotsForRoom(room);
                              final rName = (room['classroomName'] ?? '').toString().trim();
                              if (rSlots.length > 1 && slotIndex >= 0 && slotIndex < rSlots.length) {
                                final sl = rSlots[slotIndex];
                                final lbl = sl['label']?.toString() ?? '${slotIndex + 1}. Oturum';
                                final tm = (sl['startTime'] != null && sl['endTime'] != null)
                                    ? ' (${sl['startTime']} - ${sl['endTime']})'
                                    : '';
                                return Text(
                                  '${rName.isNotEmpty ? 'Derslik $rName • ' : ''}$lbl$tm Gözetmeni',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15, color: const Color(0xFF1E293B)),
                                  overflow: TextOverflow.ellipsis,
                                );
                              }
                              return Text(
                                rName.isNotEmpty ? 'Derslik $rName • Gözetmen Seçin' : 'Gözetmen Öğretmen Seçin',
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B)),
                                overflow: TextOverflow.ellipsis,
                              );
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        autofocus: false,
                        decoration: InputDecoration(
                          hintText: 'Öğretmen adı veya branş ara...',
                          hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onChanged: (val) {
                          setModalState(() => searchQuery = val);
                        },
                      ),
                    ),
                  ),
                  const Divider(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _setSupervisorForRoomSlot(room, slotIndex, null, null);
                        });
                        Navigator.pop(ctx);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person_off_rounded, color: Color(0xFFEF4444), size: 18),
                            const SizedBox(width: 10),
                            Text(
                              'Gözetmen Atanmadı (İsteğe Bağlı)',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5, color: const Color(0xFFDC2626)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, idx) {
                        final t = filtered[idx];
                        final isSelected = currentSup != null && currentSup['supervisorId'] == t['id'];
                        final isAv = (t['isAvailable'] as bool?) ?? true;

                        return InkWell(
                          onTap: () {
                            setState(() {
                              _setSupervisorForRoomSlot(room, slotIndex, t['id'], t['name']);
                            });
                            Navigator.pop(ctx);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isAv ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isAv ? Icons.person_rounded : Icons.schedule_rounded,
                                    color: isAv ? const Color(0xFF10B981) : const Color(0xFFD97706),
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              t['name'] as String,
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                                color: const Color(0xFF1E293B),
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isAv ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              isAv ? 'Müsait' : 'Dersi Var',
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 10.5,
                                                color: isAv ? const Color(0xFF059669) : const Color(0xFFD97706),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${t['branch']}',
                                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle_rounded, color: Color(0xFF4F46E5), size: 20),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // ÖĞRENCİLERİ ÇEKME
  // ===========================================================================
  Future<void> _fetchStudentsForSelectedClasses() async {
    if (_selectedClassIds.isEmpty) return;

    setState(() => _isLoadingStudents = true);

    try {
      final List<ExamStudent> loaded = [];
      final classIdList = _selectedClassIds.toList();

      for (int i = 0; i < classIdList.length; i += 10) {
        final chunk = classIdList.sublist(i, (i + 10).clamp(0, classIdList.length));
        final snap = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('classId', whereIn: chunk)
            .get();

        for (final doc in snap.docs) {
          final data = doc.data();
          final status = (data['status'] ?? '').toString().toLowerCase();
          if (data['isActive'] == false ||
              status == 'passive' ||
              status == 'pasif' ||
              status == 'inactive') {
            continue;
          }
          final classInfo = _availableClasses.firstWhere(
            (c) => c['id'] == data['classId'],
            orElse: () => {'name': data['className'] ?? '', 'gradeLevel': ''},
          );

          loaded.add(ExamStudent(
            id: doc.id,
            name: data['name']?.toString() ?? '',
            surname: data['surname']?.toString() ?? '',
            studentNumber: data['studentNumber']?.toString() ?? '',
            classId: data['classId']?.toString() ?? '',
            className: classInfo['name']?.toString() ?? data['className']?.toString() ?? '',
            gradeLevel: classInfo['gradeLevel']?.toString() ?? '',
            gender: data['gender']?.toString(),
            photoUrl: data['photoUrl']?.toString(),
          ));
        }
      }

      setState(() {
        _selectedStudents.clear();
        _selectedStudents.addAll(loaded);
        _isLoadingStudents = false;
      });
    } catch (e) {
      debugPrint('Öğrenciler çekilirken hata: $e');
      setState(() => _isLoadingStudents = false);
    }
  }

  /// Sıralı mod: her şube kendi derslik adıyla eşleşen salona otomatik atanır (501 -> 501 dersliği).
  void _autoAssignClassroomsForBranches() {
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\-_/.]'), '');
    final branchNames = _selectedStudents.map((s) => s.className).toSet().toList()
      ..sort((a, b) {
        final na = int.tryParse(RegExp(r'\d+').firstMatch(a)?.group(0) ?? '');
        final nb = int.tryParse(RegExp(r'\d+').firstMatch(b)?.group(0) ?? '');
        if (na != null && nb != null && na != nb) return na.compareTo(nb);
        return a.compareTo(b);
      });

    final rooms = <Map<String, dynamic>>[];
    for (final branch in branchNames) {
      final match = _availableClassrooms.where((c) => norm(c['name'] as String) == norm(branch)).toList();
      if (match.isEmpty) continue;
      final cr = match.first;
      final l = _findLayoutForClassroom(cr['layoutId'] as String?);
      rooms.add({
        'classroomId': cr['id'] as String,
        'classroomName': cr['name'] as String,
        'layoutId': l.id ?? 'preset_default',
        'layout': l,
        'customCapacity': (cr['capacity'] as int?) ?? l.totalCapacity,
        'supervisorId': null,
        'supervisorName': '',
      });
    }
    if (rooms.isNotEmpty) {
      setState(() {
        _configuredRooms
          ..clear()
          ..addAll(rooms);
      });
    }
  }
  int get _totalConfiguredCapacity {
    int sum = 0;
    for (final r in _configuredRooms) {
      if (r['customCapacity'] != null) {
        sum += (r['customCapacity'] as int);
      } else {
        final layout = (r['layout'] as ClassroomLayout?) ?? _findLayoutForClassroom(r['layoutId'] as String?);
        sum += layout.totalCapacity;
      }
    }
    return sum;
  }

  // ===========================================================================
  // ARAYÜZ (GÖVDE)
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: widget.existingDistribution != null
            ? 'Sınavı Düzenle (Dağıtım Öncesi)'
            : 'Kelebek Sınav Sihirbazı',
        subtitle: '${widget.schoolTypeName} • Adım ${_currentStep + 1} / 4',
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        subtitleColor: const Color(0xFF64748B),
        backButtonColor: const Color(0xFF4F46E5),
        borderColor: const Color(0xFFE2E8F0),
        onBack: () {
          if (widget.existingDistribution != null) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ButterflyExamDetailScreen(
                  distribution: widget.existingDistribution!,
                  institutionId: widget.institutionId,
                  schoolTypeId: widget.schoolTypeId,
                  schoolTypeName: widget.schoolTypeName,
                  isDraft: widget.existingDistribution!.id == null || widget.existingDistribution!.id!.isEmpty,
                ),
              ),
            );
          } else {
            Navigator.pop(context);
          }
        },
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildCustomStepper(isMobile),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: _buildStepContent(isMobile),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(isMobile),
    );
  }

  Widget _buildCustomStepper(bool isMobile) {
    final steps = ['Sınav Bilgisi', 'Şubeler', 'Salon & Gözetmen', 'Kelebek Dağıtımı'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          for (int idx = 0; idx < steps.length; idx++) ...[
            _buildStepItem(
              idx: idx,
              label: steps[idx],
              isMobile: isMobile,
            ),
            if (idx < steps.length - 1)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  height: 2.5,
                  color: _currentStep > idx ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepItem({required int idx, required String label, required bool isMobile}) {
    final isCompleted = _currentStep > idx;
    final isCurrent = _currentStep == idx;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isCompleted
                ? const Color(0xFF10B981)
                : (isCurrent ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0)),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                : Text(
                    '${idx + 1}',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: isCurrent ? Colors.white : const Color(0xFF64748B),
                    ),
                  ),
          ),
        ),
        if (!isMobile) ...[
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
              fontSize: 12,
              color: isCurrent ? const Color(0xFF1E293B) : const Color(0xFF64748B),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStepContent(bool isMobile) {
    switch (_currentStep) {
      case 0:
        return _buildStep1ExamInfo();
      case 1:
        return _buildStep2ClassesSelection(isMobile);
      case 2:
        return _buildStep3RoomsAndLayouts(isMobile);
      case 3:
        return _buildStep4ReviewAndDistribute(isMobile);
      default:
        return const SizedBox();
    }
  }

  // ===========================================================================
  // 1. ADIM: SINAV BİLGİSİ
  // ===========================================================================
  Widget _buildStep1ExamInfo() {
    final dateStr = DateFormat('dd.MM.yyyy').format(_examDate);
    final timeStr = _examTime.format(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Sınav Oturum Bilgileri', 'Manuel sınav bilgisi girebilir veya Ölçme Değerlendirme modülünden tanımlı deneme sınavı seçebilirsiniz.'),
        const SizedBox(height: 14),

        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _isTrialExamMode = false;
                      _selectedTrialExam = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: !_isTrialExamMode ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: !_isTrialExamMode
                          ? [
                              BoxShadow(
                                color: const Color(0xFF64748B).withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        'Manuel Sınav Tanımla',
                        style: GoogleFonts.inter(
                          fontWeight: !_isTrialExamMode ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 13,
                          color: !_isTrialExamMode ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() => _isTrialExamMode = true);
                    _showTrialExamPickerBottomSheet();
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _isTrialExamMode ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: _isTrialExamMode
                          ? [
                              BoxShadow(
                                color: const Color(0xFF64748B).withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.assignment_outlined, size: 16, color: Color(0xFF4F46E5)),
                        const SizedBox(width: 6),
                        Text(
                          'Deneme Sınavı Seç',
                          style: GoogleFonts.inter(
                            fontWeight: _isTrialExamMode ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 13,
                            color: _isTrialExamMode ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_isTrialExamMode) ...[
          InkWell(
            onTap: _showTrialExamPickerBottomSheet,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFC7D2FE), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF4F46E5), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedTrialExam != null ? _selectedTrialExam!.name : 'Deneme Sınavı Seçmek İçin Dokunun',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: const Color(0xFF1E293B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selectedTrialExam != null
                              ? '${_selectedTrialExam!.classLevel} • ${DateFormat("dd.MM.yyyy").format(_selectedTrialExam!.date)} • ${_selectedTrialExam!.examTypeName}'
                              : 'Ölçme ve Değerlendirme modülündeki sınavlar',
                          style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF4F46E5)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        _buildPremiumTextField(
          controller: _titleController,
          label: 'Sınav Başlığı',
          hint: 'Örn: 1. Dönem 1. Ortak Matematik Sınavı',
          icon: Icons.title_rounded,
        ),
        const SizedBox(height: 14),

        _buildPremiumTextField(
          controller: _lessonController,
          label: 'Ders Adı / Türü',
          hint: 'Örn: Matematik, Fen Bilimleri',
          icon: Icons.book_rounded,
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: Builder(
                builder: (btnCtx) => InkWell(
                  onTap: () => _pickDate(btnCtx),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 18, color: Color(0xFF4F46E5)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            dateStr,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Builder(
                builder: (btnCtx) => InkWell(
                  onTap: () => _pickTime(btnCtx),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 18, color: Color(0xFF4F46E5)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            timeStr,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        _buildPremiumTextField(
          controller: _notesController,
          label: 'Sınav Notları / Talimatlar (Opsiyonel)',
          hint: 'Örn: Optik formlar sınav başlamadan dağıtılacaktır.',
          icon: Icons.notes_rounded,
          maxLines: 2,
        ),
        const SizedBox(height: 14),

        // PDF Başlığında Sınav Adını Gösterme / Gizleme Switch'i
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF4F46E5), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PDF Başlığında Gerçek Sınav Adını Göster',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B)),
                    ),
                    Text(
                      _showExamTitleOnPdf
                          ? 'PDF çıktılarında "${_titleController.text.isNotEmpty ? _titleController.text : 'Sınav Adı'}" görünecek'
                          : 'PDF çıktılarında gizlenecek, sadece "Deneme Sınavı" yazacak',
                      style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _showExamTitleOnPdf,
                activeTrackColor: const Color(0xFFC7D2FE),
                activeThumbColor: const Color(0xFF4F46E5),
                onChanged: (val) => setState(() => _showExamTitleOnPdf = val),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 2. ADIM: ŞUBELER, ÖĞRENCİLER & 3 FARKLI DAĞITIM MODU
  // ===========================================================================
  String _levelOf(Map<String, dynamic> c) {
    var l = (c['rawLevel'] ?? '').toString();
    if (l.length == 3) l = l.substring(0, 1);
    if (l.length == 4) l = l.substring(0, 2);
    return l;
  }

  Widget _classPickerChip(String label, IconData icon, Color color, VoidCallback onTap, {bool filled = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: filled ? Colors.white : color),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700, fontSize: 11.5, color: filled ? Colors.white : color)),
        ]),
      ),
    );
  }

  Widget _buildClassPicker() {
    const indigo = Color(0xFF4F46E5);
    final byLevel = <String, List<Map<String, dynamic>>>{};
    for (final c in _availableClasses) {
      byLevel.putIfAbsent(_levelOf(c), () => []).add(c);
    }
    final levels = byLevel.keys.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 99).compareTo(int.tryParse(b) ?? 99));
    final allIds = _availableClasses.map((c) => c['id'] as String).toSet();
    final allOn = allIds.isNotEmpty && allIds.every(_selectedClassIds.contains);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            _classPickerChip(allOn ? 'Tümü Seçili' : 'Tümünü Seç', Icons.select_all_rounded, indigo,
                () => setState(() => allOn ? _selectedClassIds.clear() : _selectedClassIds.addAll(allIds)),
                filled: allOn),
            for (final l in levels)
              Builder(builder: (_) {
                final ids = byLevel[l]!.map((c) => c['id'] as String).toSet();
                final on = ids.every(_selectedClassIds.contains);
                return _classPickerChip(l.isEmpty ? 'Diğer' : '$l. Sınıflar', Icons.layers_rounded,
                    const Color(0xFF0EA5E9), () {
                  setState(() => on ? _selectedClassIds.removeAll(ids) : _selectedClassIds.addAll(ids));
                }, filled: on);
              }),
            _classPickerChip('Temizle', Icons.clear_all_rounded, const Color(0xFFEF4444),
                () => setState(() => _selectedClassIds.clear())),
          ]),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 10),
          for (final l in levels) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6, top: 2),
              child: Text(l.isEmpty ? 'Diğer' : '$l. Sınıf',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF64748B))),
            ),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in byLevel[l]!)
                Builder(builder: (_) {
                  final id = c['id'] as String;
                  final on = _selectedClassIds.contains(id);
                  return InkWell(
                    onTap: () => setState(() => on ? _selectedClassIds.remove(id) : _selectedClassIds.add(id)),
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: on ? indigo : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: on ? indigo : const Color(0xFFE2E8F0)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (on) ...[
                          const Icon(Icons.check_rounded, size: 13, color: Colors.white),
                          const SizedBox(width: 4),
                        ],
                        Text(c['name'] as String,
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                color: on ? Colors.white : const Color(0xFF1E293B))),
                      ]),
                    ),
                  );
                }),
            ]),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildStep2ClassesSelection(bool isMobile) {
    if (_isLoadingClasses || _isLoadingStudents) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Sınav Dağıtım Modu & Şubeler', 'Öğrencilerin nasıl dağıtılacağını ve sınava girecek şubeleri belirleyin.'),
        const SizedBox(height: 12),

        _buildDistributionModeSelector(),
        const SizedBox(height: 16),

        _buildClassPicker(),
        const SizedBox(height: 18),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFC7D2FE)),
          ),
          child: Row(
            children: [
              const Icon(Icons.people_alt_rounded, color: Color(0xFF4F46E5), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_selectedClassIds.length} Şube Seçildi',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF312E81)),
                    ),
                    Text(
                      _getDistributionDescription(),
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF4338CA)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDistributionModeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          _buildModeRadioTile(
            mode: DistributionMode.fullCross,
            title: '1. Tam Kelebek (Seviyeler & Şubeler Çapraz)',
            subtitle: 'Farklı sınıf seviyeleri (örn. 5 ve 8) ve şubeler tam çapraz karışır.',
            icon: Icons.shuffle_rounded,
            iconColor: const Color(0xFF4F46E5),
          ),
          const Divider(height: 1),
          _buildModeRadioTile(
            mode: DistributionMode.gradeLevelCross,
            title: '2. Seviye İçi Çapraz (Seviyeler Ayrı, Şubeler Çapraz)',
            subtitle: 'Sınıf seviyeleri korunur, şubeler (8-A, 8-B) kendi içinde çapraz karışır.',
            icon: Icons.alt_route_rounded,
            iconColor: const Color(0xFF0284C7),
          ),
          const Divider(height: 1),
          _buildModeRadioTile(
            mode: DistributionMode.sequential,
            title: '3. Mevcut Şubelere Göre Sıralı Dağıtım',
            subtitle: 'Öğrenciler şube ve okul numarası sırasına göre standart ardışık yerleştirilir.',
            icon: Icons.format_list_numbered_rounded,
            iconColor: const Color(0xFF64748B),
          ),
        ],
      ),
    );
  }

  Widget _buildModeRadioTile({
    required DistributionMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    final isSelected = _distributionMode == mode;

    return InkWell(
      onTap: () => setState(() => _distributionMode = mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? iconColor.withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: isSelected ? iconColor : const Color(0xFF64748B), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      fontSize: 13,
                      color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? iconColor : const Color(0xFFCBD5E1),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  String _getDistributionDescription() {
    switch (_distributionMode) {
      case DistributionMode.fullCross:
        return 'Tam Kelebek: Seviyeler ve şubeler yan yana/arka arkaya gelmeyecek şekilde çapraz yerleştirilir.';
      case DistributionMode.gradeLevelCross:
        return 'Seviye İçi Çapraz: Sınıf seviyeleri korunur, aynı seviyedeki şubeler kendi içinde çapraz dağıtılır.';
      case DistributionMode.sequential:
        return 'Sıralı: Öğrenciler şube ve okul numaralarına göre standart sıralı olarak salonlara yerleştirilir.';
    }
  }

  // ===========================================================================
  // 3. ADIM: SALONLAR, MASA DÜZENLERİ & ÖZEL KAPASİTE (PREMIUM MODAL SEÇİCİLER)
  // ===========================================================================
  Widget _buildStep3RoomsAndLayouts(bool isMobile) {
    if (_isLoadingLayouts || _isLoadingClassrooms || _isLoadingTeachers) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)));
    }

    final totalStudents = _selectedStudents.length;
    final totalCapacity = _totalConfiguredCapacity;
    final isCapacitySufficient = totalCapacity >= totalStudents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Sınav Salonları, Oturma Planları & Gözetmenler', 'Derslik belirleyin, kapasiteyi ayarlayın ve gözetmen öğretmen atayın.'),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isCapacitySufficient ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isCapacitySufficient ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA)),
          ),
          child: Row(
            children: [
              Icon(
                isCapacitySufficient ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                color: isCapacitySufficient ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Toplam Kapasite: $totalCapacity Koltuk / $totalStudents Öğrenci',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                        color: isCapacitySufficient ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                      ),
                    ),
                    Text(
                      isCapacitySufficient
                          ? 'Kapasite sınav için yeterli. Tüm öğrenciler oturma planlarına yerleştirilebilir.'
                          : 'Kapasite yetersiz! Lütfen yeni salon ekleyin veya salon kapasitesini artırın.',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: isCapacitySufficient ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Hızlı Aksiyon Butonları (Yönerge & Önceki Sınavdan Gözetmenleri Çek)
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _showInstructionManagementModal,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.gavel_rounded, color: Color(0xFF4F46E5), size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Sınav Yönergesi (${_instructions.length} Madde)',
                          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: _showCopySupervisorsModal,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFC7D2FE)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.copy_all_rounded, color: Color(0xFF4F46E5), size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Önceki Sınavdan Çek',
                          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF4338CA)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Sınav Oturum Sayısı & Saat Çubuğu
        _buildSessionCountStepper(),
        const SizedBox(height: 12),

        // Salon Sayısı Çubuğu
        _buildRoomCountStepper(),
        const SizedBox(height: 14),

        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: _configuredRooms.asMap().entries.map((entry) {
            final idx = entry.key;
            final room = entry.value;
            final selectedLayoutId = (room['layoutId'] as String?) ??
                ((room['layout'] as ClassroomLayout?)?.id ?? (_availableLayouts.isNotEmpty ? _availableLayouts.first.id : 'default'));

            final currentCap = (room['customCapacity'] as int?) ?? 24;

            final cardWidth = isMobile
                ? double.infinity
                : (MediaQuery.of(context).size.width - 64) / 2;

            final sup0 = _getSupervisorForRoomSlot(room, 0);
            final supName0 = sup0?['supervisorName'] ?? room['supervisorName'] ?? '';

            return SizedBox(
              width: cardWidth,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF64748B).withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.meeting_room_rounded, color: Color(0xFF4F46E5), size: 18),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Salon ${idx + 1}',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14.5, color: const Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                        if (_configuredRooms.length > 1)
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                            onPressed: () {
                              setState(() => _configuredRooms.removeAt(idx));
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 1. Derslik Seçici Kartı (Modal Açan Şık Buton)
                    InkWell(
                      onTap: () => _showClassroomPickerModal(room),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.domain_rounded, color: Color(0xFF4F46E5), size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                room['classroomName'] != null && (room['classroomName'] as String).isNotEmpty
                                    ? 'Derslik: ${room['classroomName']}'
                                    : 'Derslik Seçin',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1E293B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF64748B)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 2. Kapasite Değiştirme Stepper Çubuğu
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Text(
                            'Kullanılacak Kapasite:',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5, color: const Color(0xFF475569)),
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: () {
                              if (currentCap > 1) {
                                setState(() => room['customCapacity'] = currentCap - 1);
                              }
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.remove_circle_outline_rounded, color: Color(0xFF64748B), size: 22),
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: Text(
                              '$currentCap Koltuk',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 13, color: const Color(0xFF4F46E5)),
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              setState(() => room['customCapacity'] = currentCap + 1);
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.add_circle_outline_rounded, color: Color(0xFF4F46E5), size: 22),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 3. Masa Düzeni Şablonu Dropdown
                    DropdownButtonFormField<String>(
                      key: ValueKey('room_layout_${idx}_${room['classroomId']}_$selectedLayoutId'),
                      isExpanded: true,
                      initialValue: _availableLayouts.any((l) => l.id == selectedLayoutId)
                          ? selectedLayoutId
                          : (_availableLayouts.isNotEmpty ? _availableLayouts.first.id : null),
                      decoration: _buildPremiumInputDecoration('Masa Şablonu'),
                      items: _availableLayouts.map((l) {
                        return DropdownMenuItem<String>(
                          value: l.id ?? l.name,
                          child: Text(
                            '${l.name} (${l.totalCapacity} Koltuk)',
                            style: GoogleFonts.inter(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (newLayoutId) {
                        if (newLayoutId != null) {
                          final match = _availableLayouts.firstWhere(
                            (l) => l.id == newLayoutId || l.name == newLayoutId,
                            orElse: () => _availableLayouts.first,
                          );
                          setState(() {
                            room['layoutId'] = match.id;
                            room['layout'] = match;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 10),

                    // 4. Gözetmen Öğretmen Seçici Alanı (Uzun basılı tutarak sadece bu salonda 2/3/4 devreye bölünebilir)
                    Builder(
                      builder: (_) {
                        final roomSlots = _getEffectiveSlotsForRoom(room);
                        final bool hasRoomCustomSplit = (room['sessionSplits'] is Map) && (room['sessionSplits'] as Map).isNotEmpty;
                        final String s0Name = supName0.toString();

                        if (roomSlots.length <= 1 && !hasRoomCustomSplit) {
                          return Tooltip(
                            message: 'Tıklayın: Gözetmen seç • Uzun basılı tutun: Bu salonda 2, 3 veya 4 devreye böl',
                            child: InkWell(
                              onTap: () => _showSupervisorPickerModal(room, 0),
                              onLongPress: () => _showRoomSessionSplitModal(room, 0),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      s0Name.isNotEmpty ? Icons.person_rounded : Icons.person_add_alt_1_rounded,
                                      color: const Color(0xFF4F46E5),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        s0Name.isNotEmpty
                                            ? 'Gözetmen: $s0Name'
                                            : 'Gözetmen Öğretmen Seç (İsteğe Bağlı)',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: s0Name.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                                          color: s0Name.isNotEmpty ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF64748B)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: hasRoomCustomSplit ? const Color(0xFFDDD6FE) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.badge_rounded,
                                    color: hasRoomCustomSplit ? const Color(0xFF7C3AED) : const Color(0xFF4F46E5),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Gözetmenler ($_sessionCount Oturum • ${roomSlots.length} Devre)',
                                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12.5, color: const Color(0xFF1E293B)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (hasRoomCustomSplit)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEDE9FE),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Özel Bölünmüş',
                                        style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: const Color(0xFF6D28D9)),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ...List.generate(roomSlots.length, (slotIdx) {
                                final slot = roomSlots[slotIdx];
                                final sSessionIdx = (slot['sessionIndex'] as num?)?.toInt() ?? 0;
                                final bool isCustomSlot = slot['isRoomCustomSplit'] == true;
                                final sup = _getSupervisorForRoomSlot(room, slotIdx);
                                final sName = sup?['supervisorName']?.toString() ?? '';
                                final hasSup = sName.isNotEmpty;
                                final slotLabel = slot['label']?.toString() ?? '${slotIdx + 1}. Oturum';

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Tooltip(
                                    message: 'Tıklayın: Gözetmen seç • Uzun basılı tutun: Bu oturumu sadece bu salonda 2, 3 veya 4 devreye böl',
                                    child: InkWell(
                                      onTap: () => _showSupervisorPickerModal(room, slotIdx),
                                      onLongPress: () => _showRoomSessionSplitModal(room, sSessionIdx),
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: hasSup ? Colors.white : const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: isCustomSlot
                                                ? (hasSup ? const Color(0xFFA78BFA) : const Color(0xFFDDD6FE))
                                                : (hasSup ? const Color(0xFF818CF8) : const Color(0xFFE2E8F0)),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isCustomSlot
                                                    ? const Color(0xFFF3E8FF)
                                                    : (hasSup ? const Color(0xFFEEF2FF) : Colors.grey.shade200),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                slotLabel,
                                                style: GoogleFonts.inter(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 10.5,
                                                  color: isCustomSlot
                                                      ? const Color(0xFF6D28D9)
                                                      : (hasSup ? const Color(0xFF4F46E5) : Colors.grey.shade700),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '(${slot['startTime']} - ${slot['endTime']})',
                                              style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                hasSup ? sName : 'Gözetmen Seç...',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  fontWeight: hasSup ? FontWeight.bold : FontWeight.normal,
                                                  color: hasSup ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Icon(
                                              hasSup ? Icons.edit_outlined : Icons.add_circle_outline_rounded,
                                              size: 16,
                                              color: isCustomSlot
                                                  ? const Color(0xFF7C3AED)
                                                  : (hasSup ? const Color(0xFF4F46E5) : const Color(0xFF64748B)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// Sınav Oturum Sayısı & Saat Çubuğu (+/- ile oturum artırılır, Saatleri & Molayı Düzenle modalı açılır)
  Widget _buildSessionCountStepper() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.more_time_rounded, color: Color(0xFF4F46E5), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sınav Oturum Sayısı',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13.5, color: const Color(0xFF1E293B)),
                    ),
                    Text(
                      _sessionCount > 1
                          ? '$_sessionCount oturum · Her salona oturum bazlı gözetmen atanabilir'
                          : 'Tek oturum · Sınav boyunca tek gözetmen',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: _sessionConfigs.length > 1
                    ? () {
                        setState(() {
                          _sessionConfigs.removeLast();
                          _recalcSessionSlots();
                        });
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.remove_circle_outline_rounded,
                    size: 26,
                    color: _sessionConfigs.length > 1 ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFC7D2FE)),
                ),
                child: Text(
                  '${_sessionConfigs.length} Oturum',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 13.5, color: const Color(0xFF4F46E5)),
                ),
              ),
              InkWell(
                onTap: _sessionConfigs.length < 6
                    ? () {
                        setState(() {
                          final num = _sessionConfigs.length + 1;
                          final last = _sessionConfigs.isNotEmpty ? _sessionConfigs.last : null;
                          _sessionConfigs.add({
                            'title': '$num. Oturum',
                            'durationMinutes': (last?['durationMinutes'] as int?) ?? 40,
                            'breakMinutes': 15,
                            'splitCount': 1,
                          });
                          _recalcSessionSlots();
                        });
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.add_circle_outline_rounded,
                    size: 26,
                    color: _sessionConfigs.length < 6 ? const Color(0xFF4F46E5) : const Color(0xFFCBD5E1),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: const Color(0xFFE2E8F0)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...List.generate(_sessionSlots.length, (idx) {
                        final s = _sessionSlots[idx];
                        return Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${s['label']}: ${s['startTime']} - ${s['endTime']}',
                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
                              ),
                            ),
                            if (idx < _sessionSlots.length - 1 && _breakMinutes > 0)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  'Ara: $_breakMinutes dk',
                                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
                                ),
                              ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                icon: const Icon(Icons.edit_calendar_rounded, size: 15, color: Color(0xFF4F46E5)),
                label: Text(
                  'Saatleri & Molayı Düzenle',
                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF4F46E5)),
                ),
                onPressed: _showEditSessionTimesModal,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Salon sayısını +/- ile belirleyen çubuk.
  Widget _buildRoomCountStepper() {
    final count = _configuredRooms.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.meeting_room_rounded, color: Color(0xFF4F46E5), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sınav Salonu Sayısı',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13.5, color: const Color(0xFF1E293B)),
            ),
          ),
          InkWell(
            onTap: count > 1 ? _removeLastRoom : null,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.remove_circle_outline_rounded,
                size: 26,
                color: count > 1 ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFC7D2FE)),
            ),
            child: Text(
              '$count Salon',
              style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 13.5, color: const Color(0xFF4F46E5)),
            ),
          ),
          InkWell(
            onTap: _addRoom,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.add_circle_outline_rounded, size: 26, color: Color(0xFF4F46E5)),
            ),
          ),
        ],
      ),
    );
  }

  void _addRoom() {
    final nextIdx = _configuredRooms.length + 1;
    final classroom = _availableClassrooms.length >= nextIdx
        ? _availableClassrooms[nextIdx - 1]
        : null;
    final l = classroom?['layoutId'] != null
        ? _findLayoutForClassroom(classroom!['layoutId'] as String?)
        : _findLayoutForClassroom(null);

    setState(() {
      _configuredRooms.add({
        'classroomId': classroom?['id'] ?? 'salon_$nextIdx',
        'classroomName': classroom?['name'] ?? 'Salon $nextIdx',
        'layoutId': l.id ?? 'preset_$nextIdx',
        'layout': l,
        'customCapacity': (classroom?['capacity'] as int?) ?? l.totalCapacity,
        'supervisorId': null,
        'supervisorName': '',
        'auto': true,
      });
      _reflowAutoRooms();
    });
  }

  void _removeLastRoom() {
    if (_configuredRooms.length <= 1) return;
    setState(() => _configuredRooms.removeLast());
  }

  // ===========================================================================
  // 4. ADIM: KELEBEK DAĞITIMI ÖZETİ & BOŞLUK DAĞITIM SWITCH'İ
  // ===========================================================================
  Widget _buildStep4ReviewAndDistribute(bool isMobile) {
    final totalStudents = _selectedStudents.length;
    final totalCapacity = _totalConfiguredCapacity;

    if (_isDistributing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: Color(0xFF4F46E5)),
            const SizedBox(height: 20),
            Text(
              'Dağıtım Algoritması Çalıştırılıyor...',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14.5, color: const Color(0xFF1E293B)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _getDistributionDescription(),
              style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Kelebek Dağıtımı Özeti', 'Dağıtım motorunu çalıştırmadan önce salon ve boşluk ayarlarını kontrol edin.'),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF64748B).withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildSummaryRow('Sınav Başlığı:', _titleController.text),
              _buildSummaryRow('Ders / Türü:', _lessonController.text),
              _buildSummaryRow('Tarih & Saat:', '${DateFormat("dd.MM.yyyy").format(_examDate)} • ${_examTime.format(context)}'),
              _buildSummaryRow('Seçilen Mod:', _getModeTitle(_distributionMode)),
              const Divider(height: 20),
              _buildSummaryRow('Dahil Edilen Şubeler:', '${_selectedClassIds.length} Şube'),
              _buildSummaryRow('Sınava Girecek Öğrenci:', '$totalStudents Öğrenci'),
              _buildSummaryRow('Açılan Salon Sayısı:', '${_configuredRooms.length} Salon'),
              _buildSummaryRow('Toplam Koltuk Kapasitesi:', '$totalCapacity Koltuk'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Boşluk Dağıtım Stratejisi Switch Butonu
        if (totalCapacity > totalStudents) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF64748B).withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.tune_rounded, color: Color(0xFF4F46E5), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Boş Koltuk Dağıtım Stratejisi',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B)),
                      ),
                      Text(
                        _balanceEmptySeats
                            ? 'Boşlukları tüm salonlara eşit/dengeli paylaştır'
                            : 'Salonları sırayla doldur, boşluğu son sınıfa ver',
                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _balanceEmptySeats,
                  activeTrackColor: const Color(0xFFC7D2FE),
                  activeThumbColor: const Color(0xFF4F46E5),
                  onChanged: (val) => setState(() => _balanceEmptySeats = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _runDistributionAndPreview,
            icon: const Icon(Icons.auto_awesome_rounded, size: 22),
            label: Text(
              'DAĞITIMI YAP VE ÖNİZLE / DÜZENLE',
              style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 13.5, letterSpacing: 0.5),
            ),
          ),
        ),
      ],
    );
  }

  String _getModeTitle(DistributionMode mode) {
    switch (mode) {
      case DistributionMode.fullCross:
        return 'Tam Kelebek (Çapraz)';
      case DistributionMode.gradeLevelCross:
        return 'Seviye İçi Çapraz';
      case DistributionMode.sequential:
        return 'Mevcut Şubelere Göre Sıralı';
    }
  }

  // ===========================================================================
  // DAĞITIMI ÇALIŞTIRMA VE ÖNİZLEME / DÜZENLEME EKRANINA GEÇİŞ
  // ===========================================================================
  Future<void> _runDistributionAndPreview() async {
    final formattedTime = _examTime.format(context);
    setState(() => _isDistributing = true);

    try {
      for (final r in _configuredRooms) {
        _syncRoomSupervisorsWithEffectiveSlots(r);
      }
      final selectedClassNames = _availableClasses
          .where((c) => _selectedClassIds.contains(c['id']))
          .map((c) => c['name'] as String)
          .toList();

      final gradeLevels = _selectedStudents.map((s) => s.gradeLevel).toSet().toList();

      final params = ButterflyDistributionParams(
        title: _titleController.text.trim(),
        lessonName: _lessonController.text.trim(),
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        examDate: _examDate,
        examTime: formattedTime,
        selectedClassIds: _selectedClassIds.toList(),
        selectedClassNames: selectedClassNames,
        gradeLevels: gradeLevels,
        students: _selectedStudents,
        roomConfigs: _configuredRooms,
        notes: _notesController.text.trim(),
        distributionMode: _distributionMode,
        balanceEmptySeats: _balanceEmptySeats,
        showExamTitleOnPdf: _showExamTitleOnPdf,
        sessionSlots: _sessionSlots,
        instructions: _instructions,
      );

      final generated = await ButterflyDistributionService.distributeExam(params);

      final distribution = ExamDistribution(
        id: widget.existingDistribution?.id,
        title: generated.title,
        lessonName: generated.lessonName,
        institutionId: generated.institutionId,
        schoolTypeId: generated.schoolTypeId,
        schoolTypeName: generated.schoolTypeName,
        examDate: generated.examDate,
        examTime: generated.examTime,
        selectedClassIds: generated.selectedClassIds,
        selectedClassNames: generated.selectedClassNames,
        gradeLevels: generated.gradeLevels,
        rooms: generated.rooms,
        totalStudents: generated.totalStudents,
        seatedStudents: generated.seatedStudents,
        createdAt: widget.existingDistribution?.createdAt ?? generated.createdAt,
        updatedAt: DateTime.now(),
        notes: generated.notes,
        showExamTitleOnPdf: generated.showExamTitleOnPdf,
        isCompleted: widget.existingDistribution?.isCompleted ?? false,
        sessionSlots: generated.sessionSlots,
        instructions: generated.instructions,
        isProctoringPublished: widget.existingDistribution?.isProctoringPublished ?? false,
        instructionApprovals: widget.existingDistribution?.instructionApprovals ?? const {},
        distributionMode: _distributionMode.name,
      );

      setState(() {
        _isDistributing = false;
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ButterflyExamDetailScreen(
              distribution: distribution,
              institutionId: widget.institutionId,
              schoolTypeId: widget.schoolTypeId,
              schoolTypeName: widget.schoolTypeName,
              isDraft: widget.existingDistribution == null,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Dağıtım hatası: $e');
      setState(() => _isDistributing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dağıtım sırasında hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ===========================================================================
  // ALT NAVİGASYON
  // ===========================================================================
  Widget _buildBottomNav(bool isMobile) {
    if (_currentStep == 3 && _isDistributing) return const SizedBox();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1.2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64748B).withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_currentStep > 0) ...[
              Expanded(
                flex: 1,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    foregroundColor: const Color(0xFF64748B),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => setState(() => _currentStep--),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Geri'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _onNextStepPressed,
                icon: Icon(_currentStep == 3 ? Icons.auto_awesome_rounded : Icons.arrow_forward_rounded, size: 18),
                label: Text(
                  _currentStep == 3 ? 'Dağıtımı Yap' : 'Sonraki Adım',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onNextStepPressed() async {
    if (_currentStep == 0) {
      if (_titleController.text.trim().isEmpty || _lessonController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen sınav başlığı ve ders adını doldurun.')),
        );
        return;
      }
      setState(() => _currentStep++);
    } else if (_currentStep == 1) {
      if (_selectedClassIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen sınava dahil edilecek en az bir şube seçin.')),
        );
        return;
      }
      await _fetchStudentsForSelectedClasses();
      if (_distributionMode == DistributionMode.sequential && _configuredRooms.isEmpty) _autoAssignClassroomsForBranches();
      setState(() => _currentStep++);
    } else if (_currentStep == 2) {
      if (_configuredRooms.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen en az bir sınav salonu tanımlayın.')),
        );
        return;
      }
      setState(() => _currentStep++);
    } else if (_currentStep == 3) {
      _runDistributionAndPreview();
    }
  }

  // ===========================================================================
  // YARDIMCI GÖRSEL BİLEŞENLER
  // ===========================================================================
  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15.5, color: const Color(0xFF1E293B)),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B)),
        ),
      ],
    );
  }

  InputDecoration _buildPremiumInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Widget _buildPremiumTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B)),
          hintText: hint,
          hintStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
          prefixIcon: Icon(icon, color: const Color(0xFF4F46E5), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B))),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B)),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate([BuildContext? btnContext]) async {
    final picked = await CustomDateRangePicker.showSingle(
      context,
      sourceContext: btnContext,
      initialDate: _examDate,
    );
    if (picked != null) setState(() => _examDate = picked);
  }

  Future<void> _pickTime([BuildContext? btnContext]) async {
    final picked = await CustomTimePicker.show(
      context,
      sourceContext: btnContext,
      initialTime: _examTime,
    );
    if (picked != null) setState(() => _examTime = picked);
  }
}
