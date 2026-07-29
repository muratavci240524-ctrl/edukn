import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
  });

  @override
  State<ClassLessonAttendanceScreen> createState() => _ClassLessonAttendanceScreenState();
}

class _ClassLessonAttendanceScreenState extends State<ClassLessonAttendanceScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _students = [];
  bool _saving = false;
  String? _activeWorkPeriodId;
  bool _loadedExisting = false;

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
      _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    }

    _allowedLessonHours = (widget.availableLessonHours ?? const [1, 2, 3, 4, 5, 6, 7, 8])
        .where((e) => e >= 1)
        .toSet()
        .toList()
      ..sort();

    final initHour = widget.initialLessonHour;
    if (initHour != null && _allowedLessonHours.contains(initHour)) {
      _selectedLessonHour = initHour;
    } else {
      _selectedLessonHour = _allowedLessonHours.isNotEmpty ? _allowedLessonHours.first : 1;
    }

    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() => _loading = true);

    try {
      final selectedTermId = await TermService().getSelectedTermId();
      final activeTermId = await TermService().getActiveTermId();
      final effectiveTermId = selectedTermId ?? activeTermId;

      List<Map<String, dynamic>> students = [];

      if (widget.combinedClassIds != null && widget.combinedClassIds!.isNotEmpty) {
        final fetches = widget.combinedClassIds!.map((cId) async {
          final snapById = await FirebaseFirestore.instance
              .collection('students')
              .where('classId', isEqualTo: cId)
              .get();

          final classDoc = await FirebaseFirestore.instance.collection('classes').doc(cId).get();
          final className = classDoc.exists ? (classDoc.data()?['className'] ?? classDoc.data()?['name'])?.toString() : null;
          
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
        return effectiveTermId == null || studentTermId == effectiveTermId || studentTermId == null;
      }).toList();

      filteredStudents.sort((a, b) {
        final classA = (a['className'] ?? '').toString();
        final classB = (b['className'] ?? '').toString();
        final classComp = classA.compareTo(classB);
        if (classComp != 0) return classComp;
        return (a['fullName']?.toString() ?? '').compareTo(b['fullName']?.toString() ?? '');
      });

      if (!mounted) return;
      setState(() {
        _students = filteredStudents;
        for (final s in students) {
          final id = (s['id'] ?? '').toString();
          if (id.isNotEmpty) {
            _statusByStudentId.putIfAbsent(id, () => AttendanceStatus.present);
          }
        }
        _loading = false;
      });

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

      final List<String> targetClassIds = widget.combinedClassIds != null && widget.combinedClassIds!.isNotEmpty
          ? widget.combinedClassIds!
          : [widget.classId];

      final Map<String, AttendanceStatus> loadedStatuses = {};

      for (var cId in targetClassIds) {
        final docId = '${periodId!}_${cId}_${widget.lessonId}_${dateStr}_${_selectedLessonHour}';
        final doc = await FirebaseFirestore.instance.collection('lessonAttendance').doc(docId).get();
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

      if (loadedStatuses.isNotEmpty && mounted) {
        setState(() {
          _statusByStudentId.addAll(loadedStatuses);
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
    });
  }

  void _markAllPresent() {
    setState(() {
      for (final s in _students) {
        final id = (s['id'] ?? '').toString();
        if (id.isEmpty) continue;
        _statusByStudentId[id] = AttendanceStatus.present;
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Öğrenci bulunamadı')));
      return;
    }

    setState(() => _saving = true);
    try {
      final dateStr = _formatDateYmd(_selectedDate);
      final periodId = await _resolveWorkPeriodId();
      if ((periodId ?? '').isEmpty) {
        throw Exception('Aktif dönem bulunamadı. Yoklama sadece aktif dönemde kaydedilebilir.');
      }

      final List<String> targetClassIds = widget.combinedClassIds != null && widget.combinedClassIds!.isNotEmpty
          ? widget.combinedClassIds!
          : [widget.classId];

      final Map<String, String> classNameMap = {};
      if (widget.combinedClassIds != null && widget.combinedClassIds!.isNotEmpty) {
        for (var cId in targetClassIds) {
          final classDoc = await FirebaseFirestore.instance.collection('classes').doc(cId).get();
          final className = classDoc.exists ? (classDoc.data()?['className'] ?? classDoc.data()?['name'] ?? 'Sınıf').toString() : 'Sınıf';
          classNameMap[cId] = className;
        }
      } else {
        classNameMap[widget.classId] = widget.className;
      }

      final List<Future<void>> saveTasks = [];

      for (var cId in targetClassIds) {
        final docId = '${periodId!}_${cId}_${widget.lessonId}_${dateStr}_${_selectedLessonHour}';
        
        final Map<String, String> classStatuses = {};
        for (final s in _students) {
          if ((s['classId']?.toString() ?? '') == cId) {
            final id = (s['id'] ?? '').toString();
            if (id.isEmpty) continue;
            final st = _statusByStudentId[id] ?? AttendanceStatus.present;
            classStatuses[id] = _statusToString(st);
          }
        }

        saveTasks.add(FirebaseFirestore.instance.collection('lessonAttendance').doc(docId).set({
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
        }, SetOptions(merge: true)));
      }

      await Future.wait(saveTasks);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Yoklama kaydedildi')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydetme hatası: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bodyContent = _loading
        ? Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _TopControls(
                  date: _selectedDate,
                  lessonHour: _selectedLessonHour,
                  allowedLessonHours: _allowedLessonHours,
                  onPickDate: _pickDate,
                  onLessonHourChanged: (v) => setState(() => _selectedLessonHour = v),
                  onAllPresent: _markAllPresent,
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
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 90),
                        itemCount: _students.length,
                        itemBuilder: (context, index) {
                          final s = _students[index];
                          final id = (s['id'] ?? '').toString();
                          final name = (s['fullName'] ?? s['name'] ?? 'İsimsiz').toString();
                          final no = (s['studentNo'] ?? s['studentNumber'] ?? '').toString();
                          String subtitleText = '';
                          if (no.isNotEmpty) {
                            subtitleText += 'No: $no';
                          }
                          final studentClassName = (s['className'] ?? s['class'] ?? '').toString();
                          if (studentClassName.isNotEmpty) {
                            if (subtitleText.isNotEmpty) subtitleText += ' • ';
                            subtitleText += 'Sınıf: $studentClassName';
                          }

                          final status = _statusByStudentId[id] ?? AttendanceStatus.present;

                          return _StudentAttendanceCard(
                            title: name,
                            subtitle: subtitleText.isEmpty ? null : subtitleText,
                            status: status,
                            onPickStatus: () async {
                              final selected = await showModalBottomSheet<AttendanceStatus>(
                                context: context,
                                backgroundColor: Colors.transparent,
                                builder: (_) => _StatusPickerSheet(current: status),
                              );

                              if (selected == null) return;
                              setState(() {
                                _statusByStudentId[id] = selected;
                              });
                            },
                            onStatusChanged: (st) {
                              setState(() {
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
              constraints: BoxConstraints(maxWidth: 900),
              child: bodyContent,
            ),
          )
        : bodyContent;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Yoklama Al', style: TextStyle(color: Colors.grey.shade900, fontSize: 18, fontWeight: FontWeight.w800)),
            Text('${widget.className} • ${widget.lessonName}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
        actions: kIsWeb
            ? null
            : [
                IconButton(
                  tooltip: 'Kaydet',
                  onPressed: _saving ? null : _saveAttendance,
                  icon: _saving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.save_outlined),
                ),
              ],
      ),
      body: constrainedBody,
      floatingActionButton: kIsWeb
          ? Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: FloatingActionButton.extended(
                onPressed: (_saving || _loading) ? null : _saveAttendance,
                label: Text('Kaydet', style: TextStyle(fontWeight: FontWeight.w900)),
                icon: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(Icons.save_outlined),
              ),
            )
          : null,
      floatingActionButtonLocation: kIsWeb ? FloatingActionButtonLocation.centerFloat : null,
    );
  }
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
    final dateText = '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: Offset(0, 6)),
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
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.date_range, color: Colors.blue.shade700),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            dateText,
                            style: TextStyle(fontWeight: FontWeight.w800, color: Colors.grey.shade900),
                          ),
                        ),
                        Icon(Icons.edit, size: 18, color: Colors.blue.shade700),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule, color: Colors.purple.shade700, size: 20),
                    SizedBox(width: 6),
                    DropdownButton<int>(
                      value: lessonHour,
                      underline: SizedBox.shrink(),
                      borderRadius: BorderRadius.circular(14),
                      icon: Icon(Icons.expand_more, color: Colors.purple.shade700),
                      items: allowedLessonHours
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text('$e. Ders', style: TextStyle(fontWeight: FontWeight.w800)),
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
          SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: onAllPresent,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: Icon(Icons.done_all),
              label: Flexible(
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
  final VoidCallback onPickStatus;
  final ValueChanged<AttendanceStatus> onStatusChanged;

  const _StudentAttendanceCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.onPickStatus,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _statusColor(status).withOpacity(0.12),
                child: Icon(Icons.person, color: _statusColor(status)),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey.shade900)),
                    if (subtitle != null)
                      Text(subtitle!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              InkWell(
                onTap: onPickStatus,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _statusColor(status),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _statusLabel(status),
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.expand_more, size: 16, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
        margin: EdgeInsets.all(12),
        padding: EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 18, offset: Offset(0, 8)),
          ],
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 6),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(8)),
              ),
              SizedBox(height: 10),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Yoklama Durumu Seç',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.grey.shade900),
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
              Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: AttendanceStatus.values.map((st) {
                    final selected = st == current;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _statusColor(st).withOpacity(0.15),
                        child: Icon(Icons.check_circle, color: _statusColor(st)),
                      ),
                      title: Text(_statusLabel(st), style: TextStyle(fontWeight: FontWeight.w900)),
                      trailing: selected ? Icon(Icons.check, color: Colors.green.shade700) : null,
                      onTap: () => Navigator.pop(context, st),
                    );
                  }).toList(),
                ),
              ),
              SizedBox(height: 8),
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
