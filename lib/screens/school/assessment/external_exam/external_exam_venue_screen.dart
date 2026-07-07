import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../../models/assessment/external_exam_model.dart';
import '../../../../models/assessment/external_exam_registration_model.dart';
import '../../../../services/external_exam_service.dart';
import 'external_exam_seating_list_screen.dart';

class ExternalExamVenueScreen extends StatefulWidget {
  final ExternalExam exam;
  final String institutionId;

  const ExternalExamVenueScreen({
    Key? key,
    required this.exam,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<ExternalExamVenueScreen> createState() =>
      _ExternalExamVenueScreenState();
}

class _ExternalExamVenueScreenState extends State<ExternalExamVenueScreen> {
  final ExternalExamService _service = ExternalExamService();
  bool _isAssigning = false;
  bool _isSaving = false;
  Timer? _debounceTimer;

  void _autoSaveDebounced() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1000), () {
      _saveAssignments();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  // Local editable copy of classroom assignments
  late List<GradeClassroomAssignment> _assignments;
  List<ExternalExamRegistration> _registrations = [];
  Stream<List<ExternalExamRegistration>>? _registrationsStream;

  // Kurumun salonları
  List<Map<String, dynamic>> _institutionClassrooms = [];
  bool _loadingClassrooms = true;

  // Dış sınav için özel şablonlar (Firestore: external_exam_room_templates)
  List<Map<String, dynamic>> _templates = [];

  static const _primaryColor = Color(0xFFF57C00);

  @override
  void initState() {
    super.initState();
    _assignments = List.from(widget.exam.venueConfig.classroomAssignments);
    _registrationsStream = _service.getRegistrations(widget.exam.id ?? '');
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // Kurumun salonlarını çek (schoolTypeIds'e göre)
      final schoolTypeIds = widget.exam.venueConfig.schoolTypeIds;
      QuerySnapshot snap;
      if (schoolTypeIds.isNotEmpty) {
        snap = await FirebaseFirestore.instance
            .collection('classrooms')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('schoolTypeId', whereIn: schoolTypeIds)
            .where('isActive', isEqualTo: true)
            .get();
      } else {
        snap = await FirebaseFirestore.instance
            .collection('classrooms')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('isActive', isEqualTo: true)
            .get();
      }

      // Özel şablonları çek
      final templSnap = await FirebaseFirestore.instance
          .collection('external_exam_room_templates')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      if (mounted) {
        setState(() {
          _institutionClassrooms = snap.docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            return {
              'id': d.id,
              'name': data['classroomName'] ?? data['name'] ?? '',
              'capacity': (data['capacity'] as num?)?.toInt() ?? 30,
              'code': data['classroomCode'] ?? '',
              'building': data['building'] ?? '',
            };
          }).toList()
            ..sort((a, b) => _naturalCompare(a['name'], b['name']));

          _templates = templSnap.docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            return {
              'id': d.id,
              'name': data['name'] ?? '',
              'capacity': (data['capacity'] as num?)?.toInt() ?? 30,
              'code': data['code'] ?? '',
              'isTemplate': true,
            };
          }).toList()
            ..sort((a, b) => _naturalCompare(a['name'], b['name']));

          _loadingClassrooms = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingClassrooms = false);
    }
  }

  int _naturalCompare(String a, String b) {
    final regExp = RegExp(r'\d+');
    final aMatch = regExp.firstMatch(a);
    final bMatch = regExp.firstMatch(b);
    if (aMatch != null && bMatch != null) {
      final aNum = int.tryParse(aMatch.group(0)!) ?? 0;
      final bNum = int.tryParse(bMatch.group(0)!) ?? 0;
      if (aNum != bNum) return aNum.compareTo(bNum);
    }
    return a.compareTo(b);
  }

  List<Map<String, dynamic>> get _allAvailableRooms => [
        ..._institutionClassrooms,
        ..._templates,
      ];

  @override
  Widget build(BuildContext context) {
    final venueConfig = widget.exam.venueConfig;
    final seatingModeName = venueConfig.seatingMode == SeatingMode.noSeating
        ? 'Salon Hazırlanmayacak'
        : venueConfig.seatingMode == SeatingMode.butterfly
            ? 'Kelebek Sistemi'
            : 'Rastgele Dağılım';

    return StreamBuilder<List<ExternalExamRegistration>>(
      stream: _registrationsStream,
      builder: (context, snapshot) {
        final regs = snapshot.data ?? [];
        _registrations = regs;

        // Calculate occupancy counts
        final occupancyMap = <String, int>{};
        for (final r in regs) {
          if (r.assignedRoomId != null && r.status != RegistrationStatus.cancelled) {
            occupancyMap[r.assignedRoomId!] = (occupancyMap[r.assignedRoomId!] ?? 0) + 1;
          }
        }

        final showDistributionCard = regs.any((r) => r.assignedRoomId != null);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Seating mode chip
              _buildInfoCard(seatingModeName, venueConfig.seatingMode),

              const SizedBox(height: 20),

              if (venueConfig.seatingMode == SeatingMode.noSeating)
                _buildNoSeatingNote()
              else ...[
                // Each session
                ...widget.exam.applicationSessions.map((session) =>
                    _buildSessionCard(session)),

                // Seating distribution list card (IF distributed)
                if (showDistributionCard) ...[
                  const SizedBox(height: 16),
                  _buildDistributionListCard(regs),
                ],

                const SizedBox(height: 24),

                // Classroom assignment editor
                _buildAssignmentEditor(occupancyMap),

                const SizedBox(height: 16),

                // Save + Distribute
                _buildActionBar(),
              ],
            ],
          ),
        );
      }
    );
  }

  Widget _buildDistributionListCard(List<ExternalExamRegistration> regs) {
    final assignedCount = regs.where((r) => r.assignedRoomId != null).length;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade600, Colors.teal.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ExternalExamSeatingListScreen(
                  exam: widget.exam,
                  registrations: regs,
                  institutionId: widget.institutionId,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.people_alt_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Öğrenci Dağıtım Listesi & İşlemleri',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Toplam $assignedCount öğrenci salonlara yerleştirildi. Taşımak, çıkarmak veya listeleri basmak için tıklayın.',
                        style: GoogleFonts.inter(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(String modeName, SeatingMode mode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
            child: Icon(
              mode == SeatingMode.butterfly ? Icons.scatter_plot_rounded
                  : mode == SeatingMode.simpleRandom ? Icons.shuffle_rounded
                  : Icons.no_accounts_rounded,
              color: _primaryColor, size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Text(modeName, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildNoSeatingNote() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, color: Colors.grey.shade400),
        const SizedBox(width: 12),
        Expanded(child: Text('Bu sınav için salon planı oluşturulmayacak.', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500))),
      ]),
    );
  }

  Widget _buildSessionCard(ApplicationSession session) {
    final dateStr = '${session.sessionDate.day.toString().padLeft(2, '0')}.${session.sessionDate.month.toString().padLeft(2, '0')}.${session.sessionDate.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst satır: tarih + saat bilgisi
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text(dateStr, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: _primaryColor, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Text(session.displayTime, style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 10),
          // Butonlar – Wrap ile sığır, mobilden taşmaz
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _isAssigning ? null : () => _showDistributionDialog(session),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor, foregroundColor: Colors.white,
                  elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isAssigning
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.scatter_plot_rounded, size: 15),
                label: Text('Dağıt', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              if (_registrations.any((r) => r.sessionId == session.id && r.assignedRoomId != null))
                TextButton.icon(
                  onPressed: _isAssigning ? null : () => _resetDistribution(session),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.red.shade100)),
                  ),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                  label: Text('Dağıtımı Sıfırla', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Sınıf seviyeleri
          Wrap(
            spacing: 8, runSpacing: 6,
            children: session.gradeLevels.map((g) {
              final quota = session.gradeLevelQuotas[g] ?? 0;
              return Chip(
                label: Text(g == 'Mezun' ? 'Mezun – $quota kota' : '$g. Sınıf – $quota kota', style: const TextStyle(fontSize: 12)),
                backgroundColor: Colors.blue.shade50, side: BorderSide.none,
                labelStyle: TextStyle(color: Colors.blue.shade700),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentEditor(Map<String, int> occupancyMap) {
    final allGrades = widget.exam.gradeLevels;

    // Calculate stats
    int totalCapacity = 0;
    int totalRooms = 0;
    int emptyRoomsCount = 0;
    List<String> emptyRoomNames = [];

    for (final assignment in _assignments) {
      for (final room in assignment.rooms) {
        totalRooms++;
        final cap = room.effectiveCapacity;
        totalCapacity += cap;
        final assigned = occupancyMap[room.classroomId] ?? 0;
        if (assigned == 0) {
          emptyRoomsCount++;
          emptyRoomNames.add(room.classroomName);
        }
      }
    }

    final totalRegistered = _registrations.length;
    final assignedCount = _registrations.where((r) => r.assignedRoomId != null && r.status != RegistrationStatus.cancelled).length;
    final unassignedCount = totalRegistered - assignedCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Premium distribution summary card
        _buildDistributionSummaryCard(
          totalRooms: totalRooms,
          emptyRoomsCount: emptyRoomsCount,
          emptyRoomNames: emptyRoomNames,
          totalCapacity: totalCapacity,
          totalRegistered: totalRegistered,
          assignedCount: assignedCount,
          unassignedCount: unassignedCount,
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Sınıf → Salon Atamaları', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _downloadExcelTemplate,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Excel Şablonu'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _pickAndParseExcelRooms,
                  icon: const Icon(Icons.upload_file_rounded, size: 16),
                  label: const Text('Excel\'den Yükle'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green.shade700,
                    side: BorderSide(color: Colors.green.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _showAddTemplateDialog,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Yeni Salon Şablonu'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryColor,
                    side: const BorderSide(color: _primaryColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loadingClassrooms)
          const Center(child: CircularProgressIndicator(color: _primaryColor))
        else if (allGrades.isEmpty)
          Text('Sınav için sınıf seviyesi tanımlanmamış.', style: GoogleFonts.inter(color: Colors.grey.shade500))
        else
          ...allGrades.map((grade) => _buildGradeAssignmentCard(grade, occupancyMap)),
      ],
    );
  }

  Widget _buildGradeAssignmentCard(String grade, Map<String, int> occupancyMap) {
    final existing = _assignments.firstWhere(
      (a) => a.gradeLevel == grade,
      orElse: () => GradeClassroomAssignment(gradeLevel: grade, rooms: []),
    );

    final rooms = existing.rooms;
    final totalCap = rooms.fold(0, (sum, r) => sum + r.effectiveCapacity);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
                child: Center(child: Text(grade == 'Mezun' ? 'M' : '$grade.', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: _primaryColor, fontSize: 13))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(grade == 'Mezun' ? 'Mezun' : '$grade. Sınıf', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text('${rooms.length} salon · Toplam $totalCap kişilik kapasite', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
                ]),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Existing rooms
                  ...rooms.map((room) => _buildRoomChip(grade, room, occupancyMap)),
                  const SizedBox(height: 8),
                  // Add room button
                  GestureDetector(
                    onTap: () => _showRoomPickerDialog(grade),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200, style: BorderStyle.solid),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add_rounded, size: 16, color: Colors.orange.shade700),
                        const SizedBox(width: 6),
                        Text('Salon Ekle', style: GoogleFonts.inter(fontSize: 13, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomChip(String grade, RoomSlot room, Map<String, int> occupancyMap) {
    final assignedCount = occupancyMap[room.classroomId] ?? 0;
    final cap = room.effectiveCapacity;
    final occupancyRate = cap > 0 ? (assignedCount / cap) : 0.0;

    Color occupancyColor = Colors.green;
    if (occupancyRate >= 0.9) {
      occupancyColor = Colors.red;
    } else if (occupancyRate >= 0.5) {
      occupancyColor = Colors.orange;
    } else if (assignedCount == 0) {
      occupancyColor = Colors.grey.shade400;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.meeting_room_outlined, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(
            child: TextFormField(
              key: ValueKey('${room.classroomId}_name'),
              initialValue: room.classroomName,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                border: InputBorder.none,
                hintText: 'Salon Adı',
              ),
              onChanged: (val) {
                _updateRoomName(grade, room, val.trim());
              },
            ),
          ),
          // Doluluk göstergesi
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: occupancyColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: occupancyColor.withOpacity(0.3)),
            ),
            child: Text(
              '$assignedCount/$cap',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: occupancyColor,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Kapasite ovverride
          SizedBox(
            width: 52,
            child: TextFormField(
              initialValue: room.effectiveCapacity.toString(),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12),
              decoration: InputDecoration(
                isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                hintText: 'kap',
                hintStyle: GoogleFonts.inter(fontSize: 9, color: Colors.grey),
              ),
              onChanged: (val) {
                final cap = int.tryParse(val);
                if (cap != null && cap > 0) {
                  _updateRoomCapacity(grade, room, cap);
                }
              },
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 16, color: Colors.red),
            onPressed: () => _confirmRemoveRoom(grade, room),
            padding: EdgeInsets.zero, constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  void _updateRoomCapacity(String grade, RoomSlot room, int newCap) {
    setState(() {
      final idx = _assignments.indexWhere((a) => a.gradeLevel == grade);
      if (idx >= 0) {
        final rooms = List<RoomSlot>.from(_assignments[idx].rooms);
        final rIdx = rooms.indexWhere((r) => r.classroomId == room.classroomId);
        if (rIdx >= 0) {
          rooms[rIdx] = room.copyWith(overrideCapacity: newCap);
          _assignments[idx] = GradeClassroomAssignment(gradeLevel: grade, rooms: rooms);
        }
      }
    });
    _autoSaveDebounced();
  }

  void _updateRoomName(String grade, RoomSlot room, String newName) {
    setState(() {
      final idx = _assignments.indexWhere((a) => a.gradeLevel == grade);
      if (idx >= 0) {
        final rooms = List<RoomSlot>.from(_assignments[idx].rooms);
        final rIdx = rooms.indexWhere((r) => r.classroomId == room.classroomId);
        if (rIdx >= 0) {
          rooms[rIdx] = RoomSlot(
            classroomId: room.classroomId,
            classroomName: newName,
            classroomCode: room.classroomCode,
            originalCapacity: room.originalCapacity,
            overrideCapacity: room.overrideCapacity,
            building: room.building,
          );
          _assignments[idx] = GradeClassroomAssignment(gradeLevel: grade, rooms: rooms);
        }
      }
    });
    _autoSaveDebounced();
  }

  void _removeRoom(String grade, RoomSlot room) {
    setState(() {
      final idx = _assignments.indexWhere((a) => a.gradeLevel == grade);
      if (idx >= 0) {
        final rooms = List<RoomSlot>.from(_assignments[idx].rooms)
          ..removeWhere((r) => r.classroomId == room.classroomId);
        _assignments[idx] = GradeClassroomAssignment(gradeLevel: grade, rooms: rooms);
      }
    });
  }

  Future<void> _confirmRemoveRoom(String grade, RoomSlot room) async {
    // Count students currently assigned to this room
    final roomStudents = _registrations.where((r) =>
        r.assignedRoomId == room.classroomId &&
        r.gradeLevel == grade &&
        r.status != RegistrationStatus.cancelled).toList();

    if (roomStudents.isEmpty) {
      // No students, delete directly
      _removeRoom(grade, room);
      await _saveAssignments();
      return;
    }

    // Show confirmation dialog with options
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red),
            const SizedBox(width: 10),
            Text('Salonda Öğrenciler Atanmış', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          '"${room.classroomName}" salonuna atanmış ${roomStudents.length} öğrenci bulunmaktadır. Salonu kapatmadan önce bu öğrencilere ne yapmak istersiniz?',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade700),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('İptal', style: GoogleFonts.inter(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() {
                _loadingClassrooms = true;
              });
              try {
                // Option 1: Unassign students (boşa çıkar)
                final batch = FirebaseFirestore.instance.batch();
                for (final reg in roomStudents) {
                  final docRef = FirebaseFirestore.instance
                      .collection('external_exam_registrations')
                      .doc(reg.id);
                  batch.update(docRef, {
                    'assignedRoomId': null,
                    'assignedRoomName': null,
                    'assignedRoomCode': null,
                    'seatNumber': null,
                  });
                }
                await batch.commit();
                
                // Remove the room and auto-save assignments
                _removeRoom(grade, room);
                await _saveAssignments();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Hata oluştu: $e'), backgroundColor: Colors.red),
                  );
                }
              } finally {
                if (mounted) {
                  setState(() {
                    _loadingClassrooms = false;
                  });
                }
              }
            },
            child: const Text('Öğrencileri Boşa Çıkar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() {
                _loadingClassrooms = true;
              });
              try {
                // Option 2: Distribute to other active rooms of this grade level
                final assignmentIdx = _assignments.indexWhere((a) => a.gradeLevel == grade);
                if (assignmentIdx < 0) {
                  throw 'Sınıf seviyesi ataması bulunamadı.';
                }
                final otherRooms = _assignments[assignmentIdx].rooms
                    .where((r) => r.classroomId != room.classroomId)
                    .toList();

                if (otherRooms.isEmpty) {
                  throw 'Öğrencilerin aktarılabileceği başka salon bulunamadı.';
                }

                // Count current occupancy in other rooms
                final occupancyMap = <String, int>{};
                for (final otherRoom in otherRooms) {
                  final currentOcc = _registrations.where((r) =>
                      r.assignedRoomId == otherRoom.classroomId &&
                      r.status != RegistrationStatus.cancelled).length;
                  occupancyMap[otherRoom.classroomId] = currentOcc;
                }

                final batch = FirebaseFirestore.instance.batch();
                int currentRoomIdx = 0;

                for (final reg in roomStudents) {
                  // Find a room with remaining capacity
                  while (currentRoomIdx < otherRooms.length) {
                    final targetRoom = otherRooms[currentRoomIdx];
                    final currentOcc = occupancyMap[targetRoom.classroomId] ?? 0;
                    final cap = targetRoom.effectiveCapacity;
                    if (currentOcc < cap) {
                      final newSeat = currentOcc + 1;
                      occupancyMap[targetRoom.classroomId] = newSeat;

                      final docRef = FirebaseFirestore.instance
                          .collection('external_exam_registrations')
                          .doc(reg.id);
                      batch.update(docRef, {
                        'assignedRoomId': targetRoom.classroomId,
                        'assignedRoomName': targetRoom.classroomName,
                        'assignedRoomCode': targetRoom.classroomCode,
                        'seatNumber': newSeat,
                      });
                      break;
                    } else {
                      currentRoomIdx++;
                    }
                  }

                  if (currentRoomIdx >= otherRooms.length) {
                    throw 'Diğer salonlarda yeterli boş kontenjan kalmadı! Lütfen yeni salon ekleyin veya kapasiteleri artırın.';
                  }
                }

                await batch.commit();

                // Remove the room and auto-save assignments
                _removeRoom(grade, room);
                await _saveAssignments();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Dağıtım Hatası: $e'), backgroundColor: Colors.red),
                  );
                }
              } finally {
                if (mounted) {
                  setState(() {
                    _loadingClassrooms = false;
                  });
                }
              }
            },
            child: const Text('Diğer Salonlara Dağıt'),
          ),
        ],
      ),
    );
  }

  void _showRoomPickerDialog(String grade) {
    final existing = _assignments.firstWhere(
      (a) => a.gradeLevel == grade,
      orElse: () => GradeClassroomAssignment(gradeLevel: grade, rooms: []),
    );
    final alreadyAdded = existing.rooms.map((r) => r.classroomId).toSet();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.meeting_room_outlined, color: _primaryColor),
          const SizedBox(width: 10),
          Text('Salon Seç – ${grade == 'Mezun' ? 'Mezun' : '$grade. Sınıf'}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15)),
        ]),
        content: SizedBox(
          width: 380,
          height: 400,
          child: _allAvailableRooms.isEmpty
              ? Center(child: Text('Kullanılabilir salon bulunamadı.\nYeni şablon ekleyebilirsiniz.', textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.grey.shade500)))
              : ListView.builder(
                  itemCount: _allAvailableRooms.length,
                  itemBuilder: (ctx, i) {
                    final room = _allAvailableRooms[i];
                    final id = room['id'] as String;
                    final isAdded = alreadyAdded.contains(id);
                    final isTemplate = room['isTemplate'] == true;
                    return ListTile(
                      leading: Icon(
                        isTemplate ? Icons.bookmark_outline_rounded : Icons.meeting_room_outlined,
                        color: isAdded ? Colors.green : _primaryColor,
                      ),
                      title: Text(room['name'], style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text('${room['capacity']} kişi${isTemplate ? ' · Şablon' : ''}', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
                      trailing: isAdded
                          ? const Icon(Icons.check_circle_rounded, color: Colors.green)
                          : const Icon(Icons.add_circle_outline_rounded, color: _primaryColor),
                      onTap: isAdded ? null : () {
                        Navigator.pop(ctx);
                        _addRoom(grade, RoomSlot(
                          classroomId: id,
                          classroomName: room['name'],
                          classroomCode: room['code'] ?? '',
                          originalCapacity: room['capacity'] as int,
                        ));
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
        ],
      ),
    );
  }

  void _addRoom(String grade, RoomSlot room) {
    setState(() {
      final idx = _assignments.indexWhere((a) => a.gradeLevel == grade);
      if (idx >= 0) {
        final rooms = List<RoomSlot>.from(_assignments[idx].rooms)..add(room);
        _assignments[idx] = GradeClassroomAssignment(gradeLevel: grade, rooms: rooms);
      } else {
        _assignments.add(GradeClassroomAssignment(gradeLevel: grade, rooms: [room]));
      }
    });
  }

  void _showAddTemplateDialog() {
    final nameCtrl = TextEditingController();
    final capCtrl = TextEditingController(text: '30');
    final codeCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.bookmark_add_outlined, color: _primaryColor),
          const SizedBox(width: 10),
          Text('Yeni Salon Şablonu', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(labelText: 'Salon Adı (örn: A-101)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeCtrl,
              decoration: InputDecoration(labelText: 'Kod (isteğe bağlı)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: capCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Kapasite', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final cap = int.tryParse(capCtrl.text) ?? 30;
              String docId;
              try {
                final docRef = await FirebaseFirestore.instance
                    .collection('external_exam_room_templates')
                    .add({
                  'institutionId': widget.institutionId,
                  'name': nameCtrl.text.trim(),
                  'code': codeCtrl.text.trim(),
                  'capacity': cap,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                docId = docRef.id;
              } catch (e) {
                // Fallback to local temporary ID
                docId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
              }
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() {
                _templates.add({
                  'id': docId,
                  'name': nameCtrl.text.trim(),
                  'code': codeCtrl.text.trim(),
                  'capacity': cap,
                  'isTemplate': true,
                });
                _templates.sort((a, b) => _naturalCompare(a['name'], b['name']));
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveAssignments,
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded, size: 18),
            label: Text('Salon Planını Kaydet', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveAssignments() async {
    setState(() => _isSaving = true);
    try {
      final updatedConfig = VenueConfig(
        seatingMode: widget.exam.venueConfig.seatingMode,
        schoolTypeIds: widget.exam.venueConfig.schoolTypeIds,
        classroomAssignments: _assignments,
      );
      // Build updated exam
      final updatedExam = ExternalExam(
        id: widget.exam.id,
        institutionId: widget.exam.institutionId,
        schoolId: widget.exam.schoolId,
        title: widget.exam.title,
        examType: widget.exam.examType,
        gradeLevels: widget.exam.gradeLevels,
        trialExamIds: widget.exam.trialExamIds,
        applicationSessions: widget.exam.applicationSessions,
        venueConfig: updatedConfig,
        scholarshipEnabled: widget.exam.scholarshipEnabled,
        scholarshipConfig: widget.exam.scholarshipConfig,
        regulationUrl: widget.exam.regulationUrl,
        regulationPublishDate: widget.exam.regulationPublishDate,
        isActive: widget.exam.isActive,
        createdAt: widget.exam.createdAt,
        updatedAt: DateTime.now(),
        showRegister: widget.exam.showRegister,
        showEdit: widget.exam.showEdit,
        showTicket: widget.exam.showTicket,
        showResults: widget.exam.showResults,
        showRegulation: widget.exam.showRegulation,
      );
      await _service.updateExternalExam(updatedExam);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Salon planı kaydedildi.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydetme hatası: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showDistributionDialog(ApplicationSession session) {
    String? selectedMode;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.scatter_plot_rounded, color: _primaryColor),
            const SizedBox(width: 10),
            Text('Dağıtım Modu', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Öğrenciler salonlara nasıl dağıtılsın?', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              _distOption(ctx, setDlg, selectedMode, 'equal', Icons.balance_rounded, 'Sınıfları Eşit Dağıt', 'Her sınıf yaklaşık eşit öğrenci sayısıyla salonlara bölünür', (v) => selectedMode = v),
              const SizedBox(height: 10),
              _distOption(ctx, setDlg, selectedMode, 'fill', Icons.format_list_numbered_rounded, 'Salonları Doldurarak Dağıt', 'Bir salon dolmadan diğerine geçilmez', (v) => selectedMode = v),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
            ElevatedButton(
              onPressed: selectedMode == null ? null : () {
                Navigator.pop(ctx);
                _distributeSeats(session, selectedMode!);
              },
              style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white),
              child: const Text('Dağıt'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _distOption(BuildContext ctx, StateSetter setDlg, String? current, String value, IconData icon, String title, String subtitle, Function(String) onSelect) {
    final selected = current == value;
    return GestureDetector(
      onTap: () => setDlg(() => onSelect(value)),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? Colors.orange.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? _primaryColor : Colors.grey.shade200, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? _primaryColor : Colors.grey.shade500, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: selected ? _primaryColor : Colors.grey.shade800)),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
              ]),
            ),
            if (selected) const Icon(Icons.check_circle_rounded, color: _primaryColor),
          ],
        ),
      ),
    );
  }

  Future<void> _distributeSeats(ApplicationSession session, String mode) async {
    if (_assignments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce salonları atayın.'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _isAssigning = true);
    try {
      // First save assignments so service can use them
      await _saveAssignments();

      // Get registrations for this session
      final regs = await _service.getRegistrations(widget.exam.id ?? '').first;
      final sessionRegs = regs.where((r) =>
          r.sessionId == session.id && r.status != RegistrationStatus.cancelled).toList();

      if (sessionRegs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bu seans için başvuru bulunamadı.'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      // Build ordered registrations based on seating mode
      List<ExternalExamRegistration> ordered;
      if (widget.exam.venueConfig.seatingMode == SeatingMode.butterfly) {
        ordered = _applyButterflyAlgorithm(sessionRegs);
      } else {
        ordered = List.from(sessionRegs)..shuffle();
      }

      // Get all rooms from assignments
      final allRooms = _assignments.expand((a) => a.rooms).toList();

      if (allRooms.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Salon atanmamış.'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      // Apply distribution mode
      final Map<String, Map<String, dynamic>> seatMap = {}; // regId -> {room, seatNo}

      if (mode == 'equal') {
        // Equal: distribute students evenly across all rooms
        final perRoom = (ordered.length / allRooms.length).ceil();
        int roomIdx = 0, seatInRoom = 0;
        for (final reg in ordered) {
          if (seatInRoom >= perRoom && roomIdx < allRooms.length - 1) {
            roomIdx++;
            seatInRoom = 0;
          }
          seatInRoom++;
          seatMap[reg.id!] = {'room': allRooms[roomIdx], 'seat': seatInRoom};
        }
      } else {
        // Fill: fill each room to its capacity before moving to next
        int roomIdx = 0, seatInRoom = 0;
        for (final reg in ordered) {
          while (roomIdx < allRooms.length && seatInRoom >= allRooms[roomIdx].effectiveCapacity) {
            roomIdx++;
            seatInRoom = 0;
          }
          if (roomIdx >= allRooms.length) break;
          seatInRoom++;
          seatMap[reg.id!] = {'room': allRooms[roomIdx], 'seat': seatInRoom};
        }
      }

      // Batch write seat assignments
      const batchLimit = 500;
      final entries = seatMap.entries.toList();
      for (int i = 0; i < entries.length; i += batchLimit) {
        final batch = FirebaseFirestore.instance.batch();
        final chunk = entries.sublist(i, (i + batchLimit).clamp(0, entries.length));
        for (final entry in chunk) {
          final room = entry.value['room'] as RoomSlot;
          final seat = entry.value['seat'] as int;
          final docRef = FirebaseFirestore.instance
              .collection('external_exam_registrations')
              .doc(entry.key);
          batch.update(docRef, {
            'assignedRoomId': room.classroomId,
            'assignedRoomName': room.classroomName,
            'assignedRoomCode': room.classroomCode,
            'seatNumber': seat,
          });
        }
        await batch.commit();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${seatMap.length} öğrenci salonlara dağıtıldı.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dağıtım hatası: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isAssigning = false);
    }
  }

  Future<void> _resetDistribution(ApplicationSession session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red),
            const SizedBox(width: 10),
            Text('Dağıtımı Sıfırla', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Bu seanstaki tüm öğrencilerin salon ve sıra numarası dağıtımını sıfırlamak istediğinize emin misiniz?',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal', style: GoogleFonts.inter(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sıfırla'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isAssigning = true);
    try {
      final regs = await _service.getRegistrations(widget.exam.id ?? '').first;
      final sessionRegs = regs.where((r) =>
          r.sessionId == session.id && r.assignedRoomId != null).toList();

      if (sessionRegs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bu seans için dağıtılmış öğrenci bulunamadı.'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      for (final reg in sessionRegs) {
        final docRef = FirebaseFirestore.instance
            .collection('external_exam_registrations')
            .doc(reg.id);
        batch.update(docRef, {
          'assignedRoomId': null,
          'assignedRoomName': null,
          'assignedRoomCode': null,
          'seatNumber': null,
        });
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seans dağıtımı sıfırlandı.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sıfırlama hatası: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isAssigning = false);
    }
  }

  Future<void> _downloadExcelTemplate() async {
    try {
      var excel = Excel.createExcel();
      Sheet sheet = excel['Salon Sablonu'];
      excel.delete('Sheet1');

      CellStyle headerStyle = CellStyle(
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );

      final headers = [
        'Blok (İsteğe Bağlı)',
        'Bulunduğu Kat',
        'Salon Adı',
        'Kapasite',
      ];

      for (int i = 0; i < headers.length; i++) {
        var cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
        );
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
        sheet.setColumnWidth(i, 20.0);
      }

      final sampleRows = [
        ['A Blok', '1. Kat', '101', '30'],
        ['B Blok', 'Zemin Kat', 'Z-02', '24'],
        ['', '2. Kat', '204', '35'],
      ];

      for (int r = 0; r < sampleRows.length; r++) {
        for (int c = 0; c < sampleRows[r].length; c++) {
          var cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1),
          );
          cell.value = TextCellValue(sampleRows[r][c]);
        }
      }

      List<int>? fileBytes = excel.save();
      if (fileBytes != null) {
        await FileSaver.instance.saveFile(
          name: 'Salon_Yukleme_Sablonu',
          bytes: Uint8List.fromList(fileBytes),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Şablon indirildi.'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Şablon indirme hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickAndParseExcelRooms() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        Uint8List? fileBytes = result.files.first.bytes;
        if (fileBytes == null) return;

        setState(() {
          _loadingClassrooms = true;
        });

        var excel = Excel.decodeBytes(fileBytes);
        final table = excel.tables[excel.tables.keys.first];

        if (table == null || table.rows.isEmpty) {
          setState(() {
            _loadingClassrooms = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Excel tablosu boş veya okunamadı.'), backgroundColor: Colors.red),
            );
          }
          return;
        }

        // Başlık satırını bul
        List<Data?>? headerRow;
        int headerIndex = 0;

        for (int i = 0; i < table.rows.length && i < 10; i++) {
          final row = table.rows[i];
          bool isHeader = row.any((cell) {
            String v = cell?.value.toString().toLowerCase() ?? '';
            return v.contains('blok') || v.contains('kat') || v.contains('salon') || v.contains('kapasite') || v.contains('kontenjan');
          });

          if (isHeader) {
            headerRow = row;
            headerIndex = i;
            break;
          }
        }

        if (headerRow == null) {
          headerRow = table.rows[0];
        }

        Map<String, int> colMap = {};
        for (int i = 0; i < headerRow.length; i++) {
          String h = headerRow[i]?.value.toString().trim().toLowerCase() ?? '';
          if (h.contains('blok')) {
            colMap['blok'] = i;
          } else if (h.contains('kat')) {
            colMap['kat'] = i;
          } else if (h.contains('salon') || h.contains('ad')) {
            colMap['salon'] = i;
          } else if (h.contains('kapasite') || h.contains('kontenjan')) {
            colMap['kapasite'] = i;
          }
        }

        // Fallbacks
        if (!colMap.containsKey('blok')) colMap['blok'] = 0;
        if (!colMap.containsKey('kat')) colMap['kat'] = 1;
        if (!colMap.containsKey('salon')) colMap['salon'] = 2;
        if (!colMap.containsKey('kapasite')) colMap['kapasite'] = 3;

        List<Map<String, dynamic>> parsedRooms = [];

        for (int i = headerIndex + 1; i < table.rows.length; i++) {
          final row = table.rows[i];
          if (row.isEmpty) continue;

          String getVal(int index) {
            if (index >= row.length) return '';
            var val = row[index]?.value;
            if (val == null) return '';
            String str = val.toString().trim();
            if (val is double && str.endsWith('.0')) {
              str = str.substring(0, str.length - 2);
            }
            if (str.endsWith('.0')) str = str.substring(0, str.length - 2);
            return str;
          }

          String blok = getVal(colMap['blok']!);
          String kat = getVal(colMap['kat']!);
          String salon = getVal(colMap['salon']!);
          String kapasiteStr = getVal(colMap['kapasite']!);

          if (salon.isEmpty) continue; // Adı boş olan satırı atla

          int capacity = int.tryParse(kapasiteStr) ?? 30;

          // Salon Adı Formatlama:
          String formattedName = '';
          if (blok.isNotEmpty && kat.isNotEmpty) {
            formattedName = '$blok - $kat - $salon';
          } else if (blok.isNotEmpty) {
            formattedName = '$blok - $salon';
          } else if (kat.isNotEmpty) {
            formattedName = '$kat - $salon';
          } else {
            formattedName = salon;
          }

          parsedRooms.add({
            'name': formattedName,
            'code': (blok.isNotEmpty && kat.isNotEmpty) ? '$blok-$kat' : (blok.isNotEmpty ? blok : kat),
            'capacity': capacity,
            'block': blok,
            'floor': kat,
            'originalName': salon,
          });
        }

        setState(() {
          _loadingClassrooms = false;
        });

        if (parsedRooms.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Yüklenecek salon bulunamadı. Lütfen Excel içeriğini kontrol edin.'), backgroundColor: Colors.orange),
            );
          }
          return;
        }

        // Parsed salonları onaylama ve atama dialogunu göster
        if (mounted) {
          _showExcelRoomsConfirmDialog(parsedRooms);
        }
      }
    } catch (e) {
      setState(() {
        _loadingClassrooms = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel okuma hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showExcelRoomsConfirmDialog(List<Map<String, dynamic>> rooms) {
    // Sınavın sınıf seviyeleri
    final examGrades = widget.exam.gradeLevels;
    
    // Hangi sınıflara atanacağı (Default hepsi seçili olsun)
    final Map<String, bool> selectedGrades = {
      for (var grade in examGrades) grade: true
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.table_view_rounded, color: Colors.green.shade700, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Excel\'den Salon Yükle', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey.shade900)),
                    Text('${rooms.length} salon yüklenecek', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Excel dosyasından çözümlenen salon listesi:',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 10),
                  // Salon Listesi Önizleme
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: rooms.length,
                        separatorBuilder: (context, index) => Divider(color: Colors.grey.shade100, height: 1),
                        itemBuilder: (context, idx) {
                          final room = rooms[idx];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.meeting_room_outlined, color: _primaryColor, size: 16),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(room['name'], style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade800)),
                                      Text(
                                        '${room['block'].isNotEmpty ? "${room['block']} • " : ""}${room['floor'].isNotEmpty ? "${room['floor']} • " : ""}Kapasite: ${room['capacity']} kişi',
                                        style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Sınıf Seviyesi Seçimi
                  if (examGrades.isNotEmpty) ...[
                    Text(
                      'Bu salonları hangi sınıf seviyelerine atamak istersiniz?',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade800),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: examGrades.map((grade) {
                        final isSelected = selectedGrades[grade] ?? false;
                        return FilterChip(
                          selected: isSelected,
                          label: Text(grade == 'Mezun' ? 'Mezun' : '$grade. Sınıf'),
                          labelStyle: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.orange.shade800 : Colors.grey.shade700,
                          ),
                          backgroundColor: Colors.white,
                          selectedColor: Colors.orange.shade50,
                          checkmarkColor: Colors.orange.shade800,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isSelected ? Colors.orange.shade300 : Colors.grey.shade300,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          onSelected: (val) {
                            setDlgState(() {
                              selectedGrades[grade] = val;
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('İptal', style: GoogleFonts.inter(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                
                setState(() {
                  _loadingClassrooms = true;
                });

                try {
                  List<Map<String, dynamic>> newTemplates = [];
                  
                  for (final room in rooms) {
                    // Generate local unique ID instantly!
                    final docId = 'room_${DateTime.now().microsecondsSinceEpoch}_${rooms.indexOf(room)}';

                    final newRoomItem = {
                      'id': docId,
                      'name': room['name'],
                      'code': room['code'],
                      'capacity': room['capacity'],
                      'isTemplate': true,
                    };
                    newTemplates.add(newRoomItem);
                  }

                  setState(() {
                    _templates.addAll(newTemplates);
                    _templates.sort((a, b) => _naturalCompare(a['name'], b['name']));
                    
                    // Seçilen sınıflara ata
                    for (final grade in examGrades) {
                      if (selectedGrades[grade] == true) {
                        for (final templ in newTemplates) {
                          // Bu sınıf seviyesinde zaten bu salon ekli mi kontrol et
                          final idx = _assignments.indexWhere((a) => a.gradeLevel == grade);
                          bool alreadyAssigned = false;
                          if (idx >= 0) {
                            alreadyAssigned = _assignments[idx].rooms.any((r) => r.classroomId == templ['id']);
                          }
                          
                          if (!alreadyAssigned) {
                            _addRoom(grade, RoomSlot(
                              classroomId: templ['id'] as String,
                              classroomName: templ['name'] as String,
                              classroomCode: templ['code'] as String,
                              originalCapacity: templ['capacity'] as int,
                            ));
                          }
                        }
                      }
                    }
                  });

                  // Auto Save immediately! No need to press save button manually!
                  await _saveAssignments();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✅ ${rooms.length} salon başarıyla yüklendi ve atandı.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Yükleme hatası: $e'), backgroundColor: Colors.red),
                    );
                  }
                } finally {
                  if (mounted) {
                    setState(() {
                      _loadingClassrooms = false;
                    });
                  }
                }
              },
              child: Text('Yükle ve Ata', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  List<ExternalExamRegistration> _applyButterflyAlgorithm(List<ExternalExamRegistration> registrations) {
    final Map<String, List<ExternalExamRegistration>> schoolGroups = {};
    for (final reg in registrations) {
      schoolGroups.putIfAbsent(reg.currentSchool.trim(), () => []).add(reg);
    }
    for (final group in schoolGroups.values) {
      group.sort((a, b) => a.studentSurname.compareTo(b.studentSurname));
    }
    final groups = schoolGroups.values.toList();
    final result = <ExternalExamRegistration>[];
    int maxLen = groups.fold(0, (max, g) => g.length > max ? g.length : max);
    for (int i = 0; i < maxLen; i++) {
      for (final group in groups) {
        if (i < group.length) result.add(group[i]);
      }
    }
    return result;
  }

  Widget _buildDistributionSummaryCard({
    required int totalRooms,
    required int emptyRoomsCount,
    required List<String> emptyRoomNames,
    required int totalCapacity,
    required int totalRegistered,
    required int assignedCount,
    required int unassignedCount,
  }) {
    final occupancyRate = totalCapacity > 0 ? (assignedCount / totalCapacity) * 100 : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.01),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.analytics_rounded, color: _primaryColor, size: 18),
              ),
              const SizedBox(width: 8),
              Text(
                'Salon Dağılım Özeti & Analizi',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 600;
              return GridView.count(
                crossAxisCount: isWide ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: isWide ? 1.7 : 1.4,
                children: [
                  _buildSummaryItem(
                    title: 'Atanan Öğrenciler',
                    value: '$assignedCount / $totalRegistered',
                    subtext: 'Doluluk Oranı: %${occupancyRate.toStringAsFixed(1)}',
                    icon: Icons.people_outline_rounded,
                    color: Colors.blue,
                  ),
                  _buildSummaryItem(
                    title: 'Salonsuz Öğrenciler',
                    value: '$unassignedCount',
                    subtext: unassignedCount > 0 ? 'Dağıtılması Gerekiyor' : 'Tümü Yerleştirildi',
                    icon: Icons.warning_amber_rounded,
                    color: unassignedCount > 0 ? Colors.amber.shade700 : Colors.green,
                  ),
                  _buildSummaryItem(
                    title: 'Tanımlı Salonlar',
                    value: '$totalRooms',
                    subtext: 'Toplam Kapasite: $totalCapacity',
                    icon: Icons.meeting_room_outlined,
                    color: Colors.indigo,
                  ),
                  _buildSummaryItem(
                    title: 'Boş Salonlar',
                    value: '$emptyRoomsCount',
                    subtext: emptyRoomsCount > 0 
                        ? 'Kullanılmayan salon var'
                        : 'Tüm salonlarda öğrenci var',
                    icon: Icons.door_sliding_outlined,
                    color: emptyRoomsCount > 0 ? Colors.teal : Colors.grey.shade600,
                    tooltipText: emptyRoomNames.isNotEmpty 
                        ? 'Boş Salonlar:\n${emptyRoomNames.join(", ")}'
                        : null,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required String title,
    required String value,
    required String subtext,
    required IconData icon,
    required Color color,
    String? tooltipText,
  }) {
    final cardContent = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, size: 14, color: color),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 1),
              Text(
                subtext,
                style: GoogleFonts.inter(fontSize: 8, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );

    if (tooltipText != null) {
      return Tooltip(
        message: tooltipText,
        textStyle: GoogleFonts.inter(fontSize: 10, color: Colors.white),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(6),
        ),
        child: cardContent,
      );
    }
    return cardContent;
  }
}
