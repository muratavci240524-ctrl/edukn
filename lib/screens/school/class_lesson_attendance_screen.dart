import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/school/dynamic_course_group_model.dart';
import '../../models/school/student_movement_model.dart';
import '../../services/dynamic_group_service.dart';
import '../../services/student_movement_service.dart';
import '../../services/term_service.dart';

enum AttendanceStatus {
  present,
  absent,
  late,
  excused,
  onDuty,
  reported,
}

class ClassLessonAttendanceScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String? periodId;

  final String classId;
  final String lessonId;

  final String className;
  final String lessonName;

  final DateTime? initialDate;
  final int? initialLessonHour;
  final List<int>? availableLessonHours;

  final List<String>? combinedClassIds;
  final List<String>? combinedClassNames;

  final String? courseGroupId;
  final String? subGroupId;
  final String? subGroupName;

  const ClassLessonAttendanceScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    this.periodId,
    required this.classId,
    required this.lessonId,
    required this.className,
    required this.lessonName,
    this.initialDate,
    this.initialLessonHour,
    this.availableLessonHours,
    this.combinedClassIds,
    this.combinedClassNames,
    this.courseGroupId,
    this.subGroupId,
    this.subGroupName,
  });

  @override
  State<ClassLessonAttendanceScreen> createState() =>
      _ClassLessonAttendanceScreenState();
}

class _ClassLessonAttendanceScreenState
    extends State<ClassLessonAttendanceScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _students = [];
  bool _saving = false;
  String? _activeWorkPeriodId;
  bool _loadedExisting = false;

  String? _schoolDocId;
  StreamSubscription<List<StudentMovementRecord>>? _movementsSub;
  List<StudentMovementRecord> _dayMovements = [];
  final Set<String> _manuallyEditedStudentIds = {};

  DynamicCourseGroup? _detectedGroup;
  String? _activeSubGroupId;
  List<DynamicSubGroup> _availableSubGroups = [];

  DateTime _selectedDate = DateTime.now();
  int _selectedLessonHour = 1;

  List<int> _allowedLessonHours = const [1];

  final Map<String, AttendanceStatus> _statusByStudentId = {};

  @override
  void initState() {
    super.initState();

    final initDate = widget.initialDate;
    if (initDate != null) {
      _selectedDate = DateTime(initDate.year, initDate.month, initDate.day);
    } else {
      _selectedDate = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
    }

    _allowedLessonHours =
        (widget.availableLessonHours ?? const [1, 2, 3, 4, 5, 6, 7, 8])
            .where((e) => e >= 1)
            .toSet()
            .toList()
          ..sort();

    final initHour = widget.initialLessonHour;
    if (initHour != null && _allowedLessonHours.contains(initHour)) {
      _selectedLessonHour = initHour;
    } else {
      _selectedLessonHour =
          _allowedLessonHours.isNotEmpty ? _allowedLessonHours.first : 1;
    }

    _initMovementsAndStudents();
  }

  @override
  void dispose() {
    _movementsSub?.cancel();
    super.dispose();
  }

  Future<void> _initMovementsAndStudents() async {
    _schoolDocId =
        await StudentMovementService().resolveSchoolDocId(widget.institutionId);
    _subscribeMovementsForSelectedDate();
    await _loadStudents();
  }

  void _subscribeMovementsForSelectedDate() {
    _movementsSub?.cancel();
    final sDocId = _schoolDocId;
    if (sDocId == null || sDocId.isEmpty) return;

    final dateStr = _formatDateYmd(_selectedDate);
    _movementsSub = StudentMovementService()
        .watchMovementsForDate(
          schoolDocId: sDocId,
          dateStr: dateStr,
          schoolTypeId: widget.schoolTypeId,
        )
        .listen((records) {
          if (!mounted) return;
          setState(() {
            _dayMovements = records
                .where((r) => r.status != StudentMovementStatus.cancelled)
                .toList();
            _applyMovementProtections();
          });
        });
  }

  void _applyMovementProtections() {
    for (final s in _students) {
      final id = (s['id'] ?? '').toString();
      if (id.isEmpty || _manuallyEditedStudentIds.contains(id)) continue;
      final protectedStatus = _protectedAttendanceStatusFor(id);
      if (protectedStatus != null) {
        final current = _statusByStudentId[id];
        if (current == null ||
            current == AttendanceStatus.present ||
            current == AttendanceStatus.absent) {
          _statusByStudentId[id] = protectedStatus;
        }
      }
    }
  }

  AttendanceStatus? _protectedAttendanceStatusFor(String studentId) {
    final relevant = _movementsForStudentAndHour(studentId, _selectedLessonHour);
    for (final m in relevant) {
      if ((m.type == StudentMovementType.exitPermission ||
              m.type == StudentMovementType.earlyPickup) &&
          m.status == StudentMovementStatus.exitedSchool) {
        return AttendanceStatus.excused;
      }
      if (m.type == StudentMovementType.interview &&
          (m.status == StudentMovementStatus.inMeeting ||
              m.coveredLessonHours.contains(_selectedLessonHour))) {
        return AttendanceStatus.excused;
      }
      if (m.type == StudentMovementType.infirmary &&
          m.status == StudentMovementStatus.inInfirmary) {
        return AttendanceStatus.excused;
      }
      if (m.type == StudentMovementType.lateSlip) {
        return AttendanceStatus.late;
      }
    }
    return null;
  }

  List<StudentMovementRecord> _movementsForStudentAndHour(
    String studentId,
    int lessonHour,
  ) {
    final matches = <StudentMovementRecord>[];
    for (final m in _dayMovements) {
      if (m.studentId != studentId) continue;
      switch (m.type) {
        case StudentMovementType.lateSlip:
          if (m.lessonHour == lessonHour ||
              m.coveredLessonHours.contains(lessonHour)) {
            matches.add(m);
          }
          break;
        case StudentMovementType.exitPermission:
        case StudentMovementType.earlyPickup:
          if (m.status == StudentMovementStatus.exitedSchool) {
            if (m.autoExcusedHours.contains(lessonHour) ||
                m.coveredLessonHours.contains(lessonHour) ||
                lessonHour >= m.lessonHour) {
              matches.add(m);
            }
          } else if (m.status == StudentMovementStatus.pendingGate ||
              m.status == StudentMovementStatus.parentArrived ||
              (m.status == StudentMovementStatus.earlyPickupNotified &&
                  m.lessonHour == lessonHour)) {
            matches.add(m);
          }
          break;
        case StudentMovementType.infirmary:
          if (m.status == StudentMovementStatus.inInfirmary ||
              m.lessonHour == lessonHour) {
            matches.add(m);
          }
          break;
        case StudentMovementType.interview:
          if (m.status == StudentMovementStatus.inMeeting ||
              m.coveredLessonHours.contains(lessonHour) ||
              m.lessonHour == lessonHour) {
            matches.add(m);
          }
          break;
      }
    }
    return matches;
  }

  _MovementBannerData? _movementBannerForStudent(String studentId) {
    final list = _movementsForStudentAndHour(studentId, _selectedLessonHour);
    if (list.isEmpty) return null;
    final m = list.first;
    final timeStr = DateFormat('HH:mm').format(m.createdAt);

    switch (m.type) {
      case StudentMovementType.interview:
        final unit = m.interviewUnit.trim().isNotEmpty
            ? m.interviewUnit.trim()
            : 'Rehberlik / İdare';
        final who = m.interviewerName.trim();
        final activeText = m.status == StudentMovementStatus.inMeeting
            ? 'Görüşmede — Yok Yazmayınız ($unit${who.isNotEmpty ? ' • $who' : ''} • $timeStr)'
            : 'Görüşme Kaydı Mevcut ($unit • $timeStr)';
        return _MovementBannerData(
          text: activeText,
          icon: Icons.record_voice_over_rounded,
          color: const Color(0xFF7C3AED),
        );
      case StudentMovementType.earlyPickup:
        if (m.status == StudentMovementStatus.exitedSchool) {
          final exitT = m.gateApprovedAt != null
              ? DateFormat('HH:mm').format(m.gateApprovedAt!)
              : timeStr;
          return _MovementBannerData(
            text:
                'Velisine Erken Teslim Edildi ($exitT • Güvenlik Onaylı) — Otomatik İzinli',
            icon: Icons.directions_car_filled_rounded,
            color: const Color(0xFF0D9488),
          );
        }
        if (m.status == StudentMovementStatus.parentArrived) {
          final arrT = m.parentArrivedAt != null
              ? DateFormat('HH:mm').format(m.parentArrivedAt!)
              : timeStr;
          return _MovementBannerData(
            text:
                '📍 Veli Okula Geldi ($arrT) — Öğrenciyi Çıkışa Yönlendiriniz',
            icon: Icons.where_to_vote_rounded,
            color: const Color(0xFF059669),
          );
        }
        if (m.status == StudentMovementStatus.pendingGate) {
          return _MovementBannerData(
            text:
                'Erken Alma — Öğrenci Çıkış Kapısında ($timeStr • Teslim Bekleniyor)',
            icon: Icons.directions_walk_rounded,
            color: const Color(0xFF0284C7),
          );
        }
        return _MovementBannerData(
          text:
              'Planlı Erken Alma Bildirimi (Alış Saati: ${m.plannedExitTime.isNotEmpty ? m.plannedExitTime : timeStr})',
          icon: Icons.event_available_rounded,
          color: const Color(0xFF0D9488),
        );
      case StudentMovementType.exitPermission:
        if (m.status == StudentMovementStatus.exitedSchool) {
          final exitT = m.gateApprovedAt != null
              ? DateFormat('HH:mm').format(m.gateApprovedAt!)
              : timeStr;
          return _MovementBannerData(
            text:
                'Okuldan Çıkış Yaptı ($exitT • Güvenlik Onaylı) — Otomatik İzinli',
            icon: Icons.exit_to_app_rounded,
            color: const Color(0xFF0284C7),
          );
        }
        return _MovementBannerData(
          text: 'Çıkış İzni Verildi ($timeStr • Kapı Çıkış Onayı Bekleniyor)',
          icon: Icons.door_front_door_outlined,
          color: Colors.amber.shade800,
        );
      case StudentMovementType.infirmary:
        if (m.status == StudentMovementStatus.inInfirmary) {
          return _MovementBannerData(
            text:
                'Şu An Revirde ($timeStr\'den beri • Sevk: ${m.createdByName})',
            icon: Icons.local_hospital_rounded,
            color: Colors.red.shade700,
          );
        }
        final out = m.infirmaryOutcome.trim();
        return _MovementBannerData(
          text:
              'Revir İşlemi Tamamlandı${out.isNotEmpty ? ': $out' : ''}',
          icon: Icons.check_circle_outline_rounded,
          color: const Color(0xFF059669),
        );
      case StudentMovementType.lateSlip:
        return _MovementBannerData(
          text: 'Geç Kağıdı Verildi ($timeStr • Derse Alınabilir)',
          icon: Icons.schedule_rounded,
          color: Colors.orange.shade800,
        );
    }
  }

  Future<void> _loadStudents() async {
    setState(() => _loading = true);

    try {
      final selectedTermId = await TermService().getSelectedTermId();
      final activeTermId = await TermService().getActiveTermId();
      final effectiveTermId = selectedTermId ?? activeTermId;

      List<Map<String, dynamic>> students = [];

      DynamicCourseGroup? dynamicGroup;
      if (widget.courseGroupId != null && widget.courseGroupId!.isNotEmpty) {
        dynamicGroup =
            await DynamicGroupService().getGroupById(widget.courseGroupId!);
      } else {
        dynamicGroup = await DynamicGroupService().findGroupForClassAndLesson(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          classId: widget.classId,
          lessonId: widget.lessonId,
          termId: effectiveTermId,
        );
      }

      if (dynamicGroup != null && dynamicGroup.subGroups.isNotEmpty) {
        _detectedGroup = dynamicGroup;
        _availableSubGroups = dynamicGroup.subGroups;

        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        if (_activeSubGroupId == null) {
          if (widget.subGroupId != null && widget.subGroupId!.isNotEmpty) {
            _activeSubGroupId = widget.subGroupId;
          } else {
            final teacherSub = dynamicGroup.subGroups.firstWhere(
              (s) => s.teacherIds.contains(currentUid),
              orElse: () => dynamicGroup!.subGroups.first,
            );
            _activeSubGroupId = teacherSub.id;
          }
        }

        final selectedSub = dynamicGroup.subGroups.firstWhere(
          (s) => s.id == _activeSubGroupId,
          orElse: () => dynamicGroup!.subGroups.first,
        );

        students = await DynamicGroupService().loadStudentsForSubGroup(
          subGroup: selectedSub,
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
        );
      } else if (widget.combinedClassIds != null &&
          widget.combinedClassIds!.isNotEmpty) {
        final fetches = widget.combinedClassIds!.map((cId) async {
          final snapById = await FirebaseFirestore.instance
              .collection('students')
              .where('classId', isEqualTo: cId)
              .get();

          final classDoc = await FirebaseFirestore.instance
              .collection('classes')
              .doc(cId)
              .get();
          final className = classDoc.exists
              ? (classDoc.data()?['className'] ?? classDoc.data()?['name'])
                  ?.toString()
              : null;

          final localDocs = <String, Map<String, dynamic>>{};
          for (final doc in snapById.docs) {
            final data = doc.data();
            data['id'] = doc.id;
            localDocs[doc.id] = data;
          }
          if (className != null) {
            final snapByName = await FirebaseFirestore.instance
                .collection('students')
                .where('className', isEqualTo: className)
                .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
                .get();
            for (final doc in snapByName.docs) {
              final data = doc.data();
              data['id'] = doc.id;
              localDocs[doc.id] = data;
            }
          }
          return localDocs.values.toList();
        });

        final results = await Future.wait(fetches);
        for (var list in results) {
          students.addAll(list);
        }
      } else {
        final snapshotById = await FirebaseFirestore.instance
            .collection('students')
            .where('classId', isEqualTo: widget.classId)
            .get();

        final snapshotByName = await FirebaseFirestore.instance
            .collection('students')
            .where('className', isEqualTo: widget.className)
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .get();

        final allDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
        for (final doc in snapshotById.docs) {
          allDocs[doc.id] = doc;
        }
        for (final doc in snapshotByName.docs) {
          allDocs[doc.id] = doc;
        }
        students = allDocs.values.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
      }

      final Map<String, Map<String, dynamic>> uniqueStudentsMap = {};
      for (final s in students) {
        final id = s['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          uniqueStudentsMap[id] = s;
        }
      }

      final filteredStudents = uniqueStudentsMap.values.where((s) {
        final studentTermId = s['termId'] as String?;
        return effectiveTermId == null ||
            studentTermId == effectiveTermId ||
            studentTermId == null;
      }).toList();

      filteredStudents.sort((a, b) {
        final classA = (a['className'] ?? '').toString();
        final classB = (b['className'] ?? '').toString();
        final classComp = classA.compareTo(classB);
        if (classComp != 0) return classComp;
        return (a['fullName']?.toString() ?? '')
            .compareTo(b['fullName']?.toString() ?? '');
      });

      if (!mounted) return;
      setState(() {
        _students = filteredStudents;
        for (final s in filteredStudents) {
          final id = (s['id'] ?? '').toString();
          if (id.isNotEmpty) {
            _statusByStudentId.putIfAbsent(id, () => AttendanceStatus.present);
          }
        }
        _applyMovementProtections();
        _loading = false;
      });

      _loadedExisting = false;
      await _loadExistingAttendanceIfAny();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _students = [];
        _loading = false;
      });
    }
  }

  AttendanceStatus? _stringToStatus(String s) {
    switch (s) {
      case 'present':
        return AttendanceStatus.present;
      case 'absent':
        return AttendanceStatus.absent;
      case 'late':
        return AttendanceStatus.late;
      case 'excused':
        return AttendanceStatus.excused;
      case 'onDuty':
        return AttendanceStatus.onDuty;
      case 'reported':
        return AttendanceStatus.reported;
      default:
        return null;
    }
  }

  Future<void> _loadExistingAttendanceIfAny() async {
    if (_loadedExisting) return;
    if (!mounted) return;

    try {
      final dateStr = _formatDateYmd(_selectedDate);
      final periodId = await _resolveWorkPeriodId();
      if ((periodId ?? '').isEmpty) {
        _loadedExisting = true;
        return;
      }

      final List<String> targetClassIds =
          widget.combinedClassIds != null && widget.combinedClassIds!.isNotEmpty
              ? widget.combinedClassIds!
              : [widget.classId];

      final Map<String, AttendanceStatus> loadedStatuses = {};

      for (var cId in targetClassIds) {
        final docId =
            '${periodId!}_${cId}_${widget.lessonId}_${dateStr}_$_selectedLessonHour';
        final doc = await FirebaseFirestore.instance
            .collection('lessonAttendance')
            .doc(docId)
            .get();
        if (doc.exists) {
          final data = doc.data();
          if (data != null) {
            final raw = data['studentStatuses'];
            if (raw is Map) {
              final map = Map<String, dynamic>.from(raw);
              map.forEach((k, v) {
                final id = k.toString();
                final st = _stringToStatus((v ?? '').toString());
                if (id.isNotEmpty && st != null) {
                  loadedStatuses[id] = st;
                }
              });
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          for (final s in _students) {
            final id = (s['id'] ?? '').toString();
            if (id.isNotEmpty) {
              _statusByStudentId[id] =
                  loadedStatuses[id] ?? AttendanceStatus.present;
            }
          }
          _applyMovementProtections();
        });
      }
    } catch (_) {
      // no-op
    } finally {
      _loadedExisting = true;
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;
    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
      _manuallyEditedStudentIds.clear();
      _loadedExisting = false;
    });
    _subscribeMovementsForSelectedDate();
    await _loadExistingAttendanceIfAny();
  }

  Future<void> _onLessonHourChanged(int newHour) async {
    setState(() {
      _selectedLessonHour = newHour;
      _manuallyEditedStudentIds.clear();
      _loadedExisting = false;
    });
    await _loadExistingAttendanceIfAny();
  }

  void _markAllPresent() {
    setState(() {
      for (final s in _students) {
        final id = (s['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final protectedSt = _protectedAttendanceStatusFor(id);
        _statusByStudentId[id] = protectedSt ?? AttendanceStatus.present;
      }
    });
  }

  String _formatDateYmd(DateTime d) {
    final dd = DateTime(d.year, d.month, d.day);
    return '${dd.year}-${dd.month.toString().padLeft(2, '0')}-${dd.day.toString().padLeft(2, '0')}';
  }

  String _statusToString(AttendanceStatus s) {
    switch (s) {
      case AttendanceStatus.present:
        return 'present';
      case AttendanceStatus.absent:
        return 'absent';
      case AttendanceStatus.late:
        return 'late';
      case AttendanceStatus.excused:
        return 'excused';
      case AttendanceStatus.onDuty:
        return 'onDuty';
      case AttendanceStatus.reported:
        return 'reported';
    }
  }

  Future<String?> _resolveWorkPeriodId() async {
    if ((widget.periodId ?? '').toString().isNotEmpty) {
      return widget.periodId;
    }
    if ((_activeWorkPeriodId ?? '').isNotEmpty) {
      return _activeWorkPeriodId;
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('workPeriods')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    _activeWorkPeriodId = snapshot.docs.first.id;
    return _activeWorkPeriodId;
  }

  Future<void> _saveAttendance() async {
    if (_saving) return;
    if (_students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Öğrenci bulunamadı')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final dateStr = _formatDateYmd(_selectedDate);
      final periodId = await _resolveWorkPeriodId();
      if ((periodId ?? '').isEmpty) {
        throw Exception(
          'Aktif dönem bulunamadı. Yoklama sadece aktif dönemde kaydedilebilir.',
        );
      }

      final List<String> targetClassIds;
      if (_detectedGroup != null && _detectedGroup!.targetClassIds.isNotEmpty) {
        targetClassIds = _detectedGroup!.targetClassIds;
      } else if (widget.combinedClassIds != null &&
          widget.combinedClassIds!.isNotEmpty) {
        targetClassIds = widget.combinedClassIds!;
      } else {
        targetClassIds = [widget.classId];
      }

      final Map<String, String> classNameMap = {};
      for (var cId in targetClassIds) {
        if (cId == widget.classId) {
          classNameMap[cId] = widget.className;
        } else {
          final classDoc = await FirebaseFirestore.instance
              .collection('classes')
              .doc(cId)
              .get();
          final className = classDoc.exists
              ? (classDoc.data()?['className'] ??
                      classDoc.data()?['name'] ??
                      'Sınıf')
                  .toString()
              : 'Sınıf';
          classNameMap[cId] = className;
        }
      }

      final List<Future<void>> saveTasks = [];

      for (var cId in targetClassIds) {
        final docId =
            '${periodId!}_${cId}_${widget.lessonId}_${dateStr}_$_selectedLessonHour';

        final Map<String, String> classStatuses = {};
        for (final s in _students) {
          if ((s['classId']?.toString() ?? '') == cId) {
            final id = (s['id'] ?? '').toString();
            if (id.isEmpty) continue;
            final st = _statusByStudentId[id] ?? AttendanceStatus.present;
            classStatuses[id] = _statusToString(st);
          }
        }

        saveTasks.add(
          FirebaseFirestore.instance
              .collection('lessonAttendance')
              .doc(docId)
              .set({
            'id': docId,
            'institutionId': widget.institutionId,
            'schoolTypeId': widget.schoolTypeId,
            'periodId': periodId,
            'classId': cId,
            'className': classNameMap[cId] ?? widget.className,
            'lessonId': widget.lessonId,
            'lessonName': widget.lessonName,
            'date': dateStr,
            'lessonHour': _selectedLessonHour,
            'allowedLessonHours': _allowedLessonHours,
            'studentStatuses': classStatuses,
            'method': kIsWeb ? 'web' : 'mobile',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)),
        );
      }

      await Future.wait(saveTasks);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yoklama kaydedildi')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydetme hatası: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeMovementStudentCount = _students.where((s) {
      final id = (s['id'] ?? '').toString();
      return id.isNotEmpty && _movementBannerForStudent(id) != null;
    }).length;

    final bodyContent = _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              if (_availableSubGroups.isNotEmpty)
                Container(
                  height: 44,
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _availableSubGroups.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      final sub = _availableSubGroups[idx];
                      final isSelected = sub.id == _activeSubGroupId;
                      return ChoiceChip(
                        label: Text(
                          '${sub.name} (${sub.studentIds.length})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: Colors.indigo.shade100,
                        onSelected: (val) {
                          if (val && _activeSubGroupId != sub.id) {
                            setState(() {
                              _activeSubGroupId = sub.id;
                            });
                            _loadStudents();
                          }
                        },
                      );
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: _TopControls(
                  date: _selectedDate,
                  lessonHour: _selectedLessonHour,
                  allowedLessonHours: _allowedLessonHours,
                  onPickDate: _pickDate,
                  onLessonHourChanged: _onLessonHourChanged,
                  onAllPresent: _markAllPresent,
                ),
              ),
              if (activeMovementStudentCount > 0)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDDD6FE)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.radar_rounded,
                        size: 18,
                        color: Color(0xFF7C3AED),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bu ders saatinde $activeMovementStudentCount öğrenci için Geç / İzin / Revir / Görüşme kaydı otomatik işlendi.',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF5B21B6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _students.isEmpty
                    ? Center(
                        child: Text(
                          'Bu sınıfta öğrenci bulunamadı',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                        itemCount: _students.length,
                        itemBuilder: (context, index) {
                          final s = _students[index];
                          final id = (s['id'] ?? '').toString();
                          final name =
                              (s['fullName'] ?? s['name'] ?? 'İsimsiz')
                                  .toString();
                          final no =
                              (s['studentNo'] ?? s['studentNumber'] ?? '')
                                  .toString();
                          String subtitleText = '';
                          if (no.isNotEmpty) {
                            subtitleText += 'No: $no';
                          }
                          final studentClassName =
                              (s['className'] ?? s['class'] ?? '').toString();
                          if (studentClassName.isNotEmpty) {
                            if (subtitleText.isNotEmpty) subtitleText += ' • ';
                            subtitleText += 'Sınıf: $studentClassName';
                          }

                          final status =
                              _statusByStudentId[id] ?? AttendanceStatus.present;
                          final banner = _movementBannerForStudent(id);

                          return _StudentAttendanceCard(
                            title: name,
                            subtitle:
                                subtitleText.isEmpty ? null : subtitleText,
                            status: status,
                            movementBanner: banner,
                            onPickStatus: () async {
                              final selected =
                                  await showModalBottomSheet<AttendanceStatus>(
                                context: context,
                                backgroundColor: Colors.transparent,
                                builder: (_) =>
                                    _StatusPickerSheet(current: status),
                              );

                              if (selected == null) return;
                              setState(() {
                                _manuallyEditedStudentIds.add(id);
                                _statusByStudentId[id] = selected;
                              });
                            },
                            onStatusChanged: (st) {
                              setState(() {
                                _manuallyEditedStudentIds.add(id);
                                _statusByStudentId[id] = st;
                              });
                            },
                          );
                        },
                      ),
              ),
            ],
          );

    final constrainedBody = kIsWeb
        ? Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: bodyContent,
            ),
          )
        : bodyContent;

    return Scaffold(
      appBar: EduknAppBar(
        title: 'Yoklama Al',
        subtitle: '${widget.className} • ${widget.lessonName}',
        actions: kIsWeb
            ? null
            : [
                IconButton(
                  tooltip: 'Kaydet',
                  onPressed: _saving ? null : _saveAttendance,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, color: Colors.indigo),
                ),
              ],
      ),
      body: constrainedBody,
      floatingActionButton: kIsWeb
          ? Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FloatingActionButton.extended(
                onPressed: (_saving || _loading) ? null : _saveAttendance,
                label: const Text(
                  'Kaydet',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
              ),
            )
          : null,
      floatingActionButtonLocation:
          kIsWeb ? FloatingActionButtonLocation.centerFloat : null,
    );
  }
}

class _MovementBannerData {
  final String text;
  final IconData icon;
  final Color color;

  const _MovementBannerData({
    required this.text,
    required this.icon,
    required this.color,
  });
}

class _TopControls extends StatelessWidget {
  final DateTime date;
  final int lessonHour;
  final List<int> allowedLessonHours;
  final VoidCallback onPickDate;
  final ValueChanged<int> onLessonHourChanged;
  final VoidCallback onAllPresent;

  const _TopControls({
    required this.date,
    required this.lessonHour,
    required this.allowedLessonHours,
    required this.onPickDate,
    required this.onLessonHourChanged,
    required this.onAllPresent,
  });

  @override
  Widget build(BuildContext context) {
    final dateText =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onPickDate,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.date_range, color: Colors.blue.shade700),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            dateText,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade900,
                            ),
                          ),
                        ),
                        Icon(Icons.edit, size: 18, color: Colors.blue.shade700),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      color: Colors.purple.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    DropdownButton<int>(
                      value: lessonHour,
                      underline: const SizedBox.shrink(),
                      borderRadius: BorderRadius.circular(14),
                      icon: Icon(
                        Icons.expand_more,
                        color: Colors.purple.shade700,
                      ),
                      items: allowedLessonHours
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text(
                                '$e. Ders',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        onLessonHourChanged(v);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: onAllPresent,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.done_all),
              label: const Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    'Hepsi Geldi',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentAttendanceCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final AttendanceStatus status;
  final _MovementBannerData? movementBanner;
  final VoidCallback onPickStatus;
  final ValueChanged<AttendanceStatus> onStatusChanged;

  const _StudentAttendanceCard({
    required this.title,
    required this.subtitle,
    required this.status,
    this.movementBanner,
    required this.onPickStatus,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: movementBanner != null
              ? movementBanner!.color.withValues(alpha: 0.35)
              : Colors.grey.shade200,
          width: movementBanner != null ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _statusColor(status).withValues(alpha: 0.12),
                child: Icon(Icons.person, color: _statusColor(status)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.grey.shade900,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
              InkWell(
                onTap: onPickStatus,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(status),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _statusLabel(status),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.expand_more,
                        size: 16,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (movementBanner != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: movementBanner!.color.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    movementBanner!.icon,
                    size: 15,
                    color: movementBanner!.color,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      movementBanner!.text,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: movementBanner!.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPickerSheet extends StatelessWidget {
  final AttendanceStatus current;
  const _StatusPickerSheet({required this.current});

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.65;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Yoklama Durumu Seç',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: Colors.grey.shade700),
                      tooltip: 'Kapat',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: AttendanceStatus.values.map((st) {
                    final selected = st == current;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            _statusColor(st).withValues(alpha: 0.15),
                        child: Icon(Icons.check_circle, color: _statusColor(st)),
                      ),
                      title: Text(
                        _statusLabel(st),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      trailing: selected
                          ? Icon(Icons.check, color: Colors.green.shade700)
                          : null,
                      onTap: () => Navigator.pop(context, st),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

String _statusLabel(AttendanceStatus s) {
  switch (s) {
    case AttendanceStatus.present:
      return 'Geldi';
    case AttendanceStatus.absent:
      return 'Gelmedi';
    case AttendanceStatus.late:
      return 'Geç';
    case AttendanceStatus.excused:
      return 'İzinli';
    case AttendanceStatus.onDuty:
      return 'Görevli';
    case AttendanceStatus.reported:
      return 'Raporlu';
  }
}

Color _statusColor(AttendanceStatus s) {
  switch (s) {
    case AttendanceStatus.present:
      return Colors.green.shade600;
    case AttendanceStatus.absent:
      return Colors.red.shade600;
    case AttendanceStatus.late:
      return Colors.orange.shade700;
    case AttendanceStatus.excused:
      return Colors.blueGrey.shade600;
    case AttendanceStatus.onDuty:
      return Colors.indigo.shade600;
    case AttendanceStatus.reported:
      return Colors.purple.shade600;
  }
}
