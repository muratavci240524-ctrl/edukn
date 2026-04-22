import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../services/leave_service.dart';
import '../../../services/leave_conflict_service.dart';

class SchoolTypeLeaveApprovalScreen extends StatefulWidget {
  final Map<String, dynamic> request;
  final String institutionId;

  const SchoolTypeLeaveApprovalScreen({
    Key? key,
    required this.request,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<SchoolTypeLeaveApprovalScreen> createState() => _SchoolTypeLeaveApprovalScreenState();
}

class _SchoolTypeLeaveApprovalScreenState extends State<SchoolTypeLeaveApprovalScreen> {
  final LeaveService _service = LeaveService();
  final LeaveConflictService _conflictService = LeaveConflictService();

  List<Map<String, dynamic>> _lessonConflicts = [];
  List<Map<String, dynamic>> _dutyConflicts = [];
  bool _isLoading = true;
  bool _isProcessing = false;

  // Pending assignments: key = unique conflict identifier, value = assigned teacher info
  // Format: "date_hourIndex_classId" -> { 'id': teacherId, 'name': teacherName }
  final Map<String, Map<String, dynamic>> _pendingAssignments = {};

  @override
  void initState() {
    super.initState();
    _loadConflicts();
  }

  Future<void> _loadConflicts() async {
    setState(() => _isLoading = true);
    try {
      final req = widget.request;
      final startDate = _toDate(req['startDate']);
      final endDate = _toDate(req['endDate']);
      final isFullDay = req['isFullDay'] ?? true;
      final startTime = req['startTime'];
      final endTime = req['endTime'];

      final lessons = await _conflictService.checkLessonConflicts(
        institutionId: widget.institutionId,
        teacherId: req['userId'],
        startDate: startDate,
        endDate: endDate,
        isFullDay: isFullDay,
        startTime: startTime,
        endTime: endTime,
      );

      final duties = await _conflictService.checkDutyConflicts(
        institutionId: widget.institutionId,
        teacherId: req['userId'],
        startDate: startDate,
        endDate: endDate,
        isFullDay: isFullDay,
        startTime: startTime,
        endTime: endTime,
      );

      if (mounted) {
        setState(() {
          _lessonConflicts = lessons;
          _dutyConflicts = duties;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Çakışmalar yüklenirken hata: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final startDate = _toDate(req['startDate']);
    final endDate = _toDate(req['endDate']);
    final isFullDay = req['isFullDay'] ?? true;
    final dateStr = startDate.day == endDate.day
        ? DateFormat('d MMMM yyyy (EEEE)', 'tr_TR').format(startDate)
        : '${DateFormat('d MMM', 'tr_TR').format(startDate)} - ${DateFormat('d MMM yyyy', 'tr_TR').format(endDate)}';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'İzin Onay Süreci',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: const Color(0xFFEEF2FF),
                            child: Text(
                              (req['staffName'] ?? '?')[0].toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFF4F46E5),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  req['staffName'] ?? 'Bilinmeyen Personel',
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${req['type']} • $dateStr',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (!isFullDay) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.access_time,
                                size: 16,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Saatlik İzin: ${req['startTime']} - ${req['endTime']}',
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _buildConflictSection(
                        icon: Icons.school_outlined,
                        title: 'Ders Çakışmaları (${_lessonConflicts.length})',
                        subtitle:
                            'Bu saatlerdeki derslere geçici öğretmen atayın.',
                        conflicts: _lessonConflicts,
                      ),
                      const SizedBox(height: 24),
                      _buildConflictSection(
                        icon: Icons.assignment_outlined,
                        title: 'Nöbet Çakışmaları (${_dutyConflicts.length})',
                        subtitle: 'Nöbet görevleri için çözüm üretin.',
                        conflicts: _dutyConflicts,
                        isDuty: true,
                      ),
                    ],
                  ),
                ),

                // Actions
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isProcessing
                              ? null
                              : () => _showRejectDialog(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Reddet'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isProcessing
                              ? null
                              : () => _approveLeave(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isProcessing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Onayla'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildConflictSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> conflicts,
    bool isDuty = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFF4F46E5)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            // Otomatik Ata Button
            if (!isDuty && conflicts.isNotEmpty)
              ElevatedButton.icon(
                onPressed: _isProcessing ? null : () => _autoAssignAll(),
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('Otomatik Ata'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (conflicts.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade100),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 12),
                Text(
                  'Herhangi bir çakışma tespit edilmedi.',
                  style: TextStyle(color: Colors.green.shade700),
                ),
              ],
            ),
          )
        else
          ...conflicts.map((c) => _buildConflictItem(c, isDuty)).toList(),
        if (!isDuty && _pendingAssignments.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF10B981)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_pendingAssignments.length} öğretmen atandı. Onay verdiğinizde kaydedilecek.',
                  style: const TextStyle(
                    color: Color(0xFF047857),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // Generate unique key for a conflict
  String _getConflictKey(Map<String, dynamic> conflict) {
    final date = conflict['date'] as DateTime;
    final hourIndex = conflict['hourIndex'];
    final classId = conflict['classId'] ?? '';
    return '${date.year}-${date.month}-${date.day}_${hourIndex}_$classId';
  }

  Widget _buildConflictItem(Map<String, dynamic> conflict, bool isDuty) {
    final date = conflict['date'] as DateTime;
    final dateStr = DateFormat('dd.MM.yyyy', 'tr_TR').format(date);

    final conflictKey = _getConflictKey(conflict);
    final pendingAssignment = _pendingAssignments[conflictKey];
    final hasPending = pendingAssignment != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasPending ? const Color(0xFF10B981) : Colors.grey.shade200,
          width: hasPending ? 2 : 1,
        ),
      ),
      color: hasPending ? const Color(0xFFECFDF5) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (hasPending)
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 18),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isDuty
                        ? (conflict['locationName'] ?? 'Nöbet')
                        : (conflict['courseName'] ?? 'Ders'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: hasPending ? const Color(0xFF047857) : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isDuty
                        ? dateStr
                        : '$dateStr - ${conflict['hourIndex'] + 1}. Saat (${conflict['className'] ?? 'Sınıf'})',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  if (hasPending) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.person_outline,
                          size: 16,
                          color: Color(0xFF10B981),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Atanan: ${pendingAssignment['name']}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (!isDuty)
              hasPending
                  ? IconButton(
                      onPressed: () {
                        setState(() {
                          _pendingAssignments.remove(conflictKey);
                        });
                      },
                      icon: const Icon(Icons.close, color: Color(0xFFEF4444)),
                      tooltip: 'Atamayı Kaldır',
                    )
                  : ElevatedButton(
                      onPressed: () => _pickSubstitute(conflict),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        elevation: 0,
                      ),
                      child: const Text('Ata', style: TextStyle(fontSize: 13)),
                    ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSubstitute(Map<String, dynamic> conflict) async {
    String? absentBranch;
    try {
      final absentTeacherDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.request['userId'])
          .get();
      if (absentTeacherDoc.exists) {
        final data = absentTeacherDoc.data()!;
        if (data['branch'] is String) {
          absentBranch = data['branch'];
        } else if (data['branches'] is List &&
            (data['branches'] as List).isNotEmpty) {
          absentBranch = (data['branches'] as List).first.toString();
        }
      }
    } catch (_) {}

    final teachers = await _conflictService.findFreeTeachers(
      institutionId: widget.institutionId,
      schoolTypeId: conflict['schoolTypeId'],
      periodId: conflict['periodId'],
      dayOfWeek: conflict['date'].weekday,
      hourIndex: conflict['hourIndex'],
      date: conflict['date'],
      absentTeacherBranch: absentBranch,
    );

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Geçici Öğretmen Seçin',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: teachers.isEmpty
                    ? const Center(child: Text('Uygun öğretmen bulunamadı.'))
                    : ListView.builder(
                        itemCount: teachers.length,
                        itemBuilder: (context, index) {
                          final t = teachers[index];
                          final branchMatch = t['branchMatch'] == true;
                          final assignCount = t['assignmentCount'] ?? 0;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: branchMatch
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFF4F46E5),
                              child: Text(
                                (t['name'] ?? '?')[0],
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Row(
                              children: [
                                Text(t['name'] ?? 'İsimsiz'),
                                if (branchMatch) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Branş',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.green.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              '${t['branch'] ?? 'Genel'} • Bu ay: $assignCount atama',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            onTap: () {
                              final conflictKey = _getConflictKey(conflict);
                              setState(() {
                                _pendingAssignments[conflictKey] = {
                                  'id': t['id'],
                                  'name':
                                      t['name'] ?? t['fullName'] ?? 'Öğretmen',
                                  'conflict': conflict,
                                };
                              });
                              Navigator.pop(context);
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
  }

  Future<void> _autoAssignAll() async {
    if (_lessonConflicts.isEmpty) return;

    setState(() => _isProcessing = true);
    int success = 0;
    int failed = 0;

    String? absentBranch;
    try {
      final absentTeacherDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.request['userId'])
          .get();
      if (absentTeacherDoc.exists) {
        final data = absentTeacherDoc.data()!;
        if (data['branch'] is String) {
          absentBranch = data['branch'];
        } else if (data['branches'] is List &&
            (data['branches'] as List).isNotEmpty) {
          absentBranch = (data['branches'] as List).first.toString();
        }
      }
    } catch (_) {}

    final Map<String, Set<int>> assignedThisBatch = {};
    final Map<String, int> sessionAssignmentCounts = {};

        for (var conflict in _lessonConflicts) {
          final conflictKey = _getConflictKey(conflict);

          if (_pendingAssignments.containsKey(conflictKey)) {
            success++;
            continue;
          }

          try {
            final teachers = await _conflictService.findFreeTeachers(
              institutionId: widget.institutionId,
              schoolTypeId: conflict['schoolTypeId'],
              periodId: conflict['periodId'],
              dayOfWeek: conflict['date'].weekday,
              hourIndex: conflict['hourIndex'],
              date: conflict['date'],
              absentTeacherBranch: absentBranch,
            );

            final dateKey =
                '${conflict['date'].year}-${conflict['date'].month}-${conflict['date'].day}';
            final hourIdx = conflict['hourIndex'] as int;

            // 1. Filter out teachers already assigned to THIS specific hour during this batch
            final availableTeachers = teachers.where((t) {
              final tid = t['id'] as String;
              final batchKey = '$dateKey-$tid';
              return !(assignedThisBatch[batchKey]?.contains(hourIdx) ?? false);
            }).toList();

            if (availableTeachers.isEmpty) {
              failed++;
              continue;
            }

            // 2. Re-sort for fairness: Primary = Branch Match, Secondary = Total workload (DB + Session)
            availableTeachers.sort((a, b) {
              // Primary: Branch match match priority
              if (a['branchMatch'] == true && b['branchMatch'] != true)
                return -1;
              if (b['branchMatch'] == true && a['branchMatch'] != true) return 1;

              // Secondary: Effective workload (Monthly Count from DB + Assignments in this Auto-Assign session)
              final countA = (a['assignmentCount'] ?? 0) +
                  (sessionAssignmentCounts[a['id']] ?? 0);
              final countB = (b['assignmentCount'] ?? 0) +
                  (sessionAssignmentCounts[b['id']] ?? 0);
              return countA.compareTo(countB);
            });

            final bestTeacher = availableTeachers.first;
            final tid = bestTeacher['id'] as String;
            final batchKey = '$dateKey-$tid';

            // 3. Mark as busy for this hour
            assignedThisBatch.putIfAbsent(batchKey, () => {});
            assignedThisBatch[batchKey]!.add(hourIdx);

            // 4. Increment session counter for fairness in next iterations
            sessionAssignmentCounts[tid] =
                (sessionAssignmentCounts[tid] ?? 0) + 1;

            _pendingAssignments[conflictKey] = {
              'id': tid,
              'name':
                  bestTeacher['name'] ?? bestTeacher['fullName'] ?? 'Öğretmen',
              'conflict': conflict,
            };
            success++;
          } catch (e) {
            failed++;
          }
        }

    if (mounted) {
      setState(() => _isProcessing = false);

      if (failed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠ $failed ders için uygun öğretmen bulunamadı'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ $success ders için öğretmen seçildi. Onaylamak için "Onayla" butonuna tıklayın.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _approveLeave() async {
    int unassignedCount = 0;
    for (var conflict in _lessonConflicts) {
      final conflictKey = _getConflictKey(conflict);
      if (!_pendingAssignments.containsKey(conflictKey)) {
        unassignedCount++;
      }
    }

    if (unassignedCount > 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Text('Dikkat'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$unassignedCount ders için öğretmen ataması yapılmadı.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Bu dersler boş kalacaktır. Yine de izni onaylamak istiyor musunuz?',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
              ),
              child: const Text('Yine de Onayla'),
            ),
          ],
        ),
      );

      if (proceed != true) return;
    }

    setState(() => _isProcessing = true);

    try {
      if (_pendingAssignments.isNotEmpty) {
        for (var entry in _pendingAssignments.entries) {
          final assignment = entry.value;
          // Note: detailed assignment tracking not available in current API
          // Using simplified temporaryTeacherId assignment
          await _service.assignTemporaryTeacher(
            leaveId: widget.request['id'],
            temporaryTeacherId: assignment['id'],
          );
        }
      }

      await _service.updateLeaveStatus(
        leaveId: widget.request['id'],
        status: 'approved',
        managerNote: '',
      );
      await _service.sendInternalNotification(
        userId: widget.request['userId'] ?? widget.request['staffId'] ?? '',
        title: 'İzniniz Onaylandı',
        body:
            '${DateFormat('dd.MM.yyyy').format(_toDate(widget.request['startDate']))} tarihli izniniz onaylanmıştır.',
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _showRejectDialog() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İzin Talebini Reddet'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'Red Gerekçesi',
            hintText: 'Neden reddedildiğini açıklayın...',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reddet'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isProcessing = true);
      try {
        await _service.updateLeaveStatus(
          leaveId: widget.request['id'],
          status: 'rejected',
          managerNote: reasonController.text,
        );
        await _service.sendInternalNotification(
          userId: widget.request['userId'] ?? widget.request['staffId'] ?? '',
          title: 'İzniniz Reddedildi',
          body:
              'İzin talebiniz reddedilmiştir. Gerekçe: ${reasonController.text}',
        );
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      } finally {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// Robust date converter for different Firestore formats (String/Timestamp)
  DateTime _toDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }
}
