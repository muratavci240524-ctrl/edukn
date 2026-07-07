import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/assessment/external_exam_model.dart';
import '../../models/assessment/external_exam_registration_model.dart';
import '../../services/external_exam_service.dart';

/// Public yoklama ekranı — login gerektirmez
/// URL: /yoklama-al-{examId}
class ExternalExamAttendanceScreen extends StatefulWidget {
  final String examId;

  const ExternalExamAttendanceScreen({Key? key, required this.examId})
      : super(key: key);

  @override
  State<ExternalExamAttendanceScreen> createState() =>
      _ExternalExamAttendanceScreenState();
}

class _ExternalExamAttendanceScreenState
    extends State<ExternalExamAttendanceScreen> {
  final ExternalExamService _service = ExternalExamService();

  static const _primaryColor = Color(0xFFF57C00);
  static const _darkColor = Color(0xFF1E293B);

  // Loading & data states
  bool _isLoading = true;
  String? _errorMessage;
  ExternalExam? _exam;

  // Step control: 0 = salon seç, 1 = yoklama al
  int _step = 0;

  // Seçili salon
  RoomSlot? _selectedRoom;
  String? _selectedRoomGrade;

  // Öğrenci listesi ve yoklama state
  List<ExternalExamRegistration> _students = [];
  Map<String, bool> _attendanceMap = {}; // registrationId -> attended
  bool _isLoadingStudents = false;

  // Mevcut yoklama kaydı
  Map<String, dynamic>? _existingAttendance;
  String? _existingAttendanceId;

  // Kaydetme
  bool _isSaving = false;
  bool _savedSuccessfully = false;

  // Gözetmen adı
  final _proctorController = TextEditingController();
  bool _proctorError = false;

  @override
  void initState() {
    super.initState();
    _loadExam();
  }

  @override
  void dispose() {
    _proctorController.dispose();
    super.dispose();
  }

  Future<void> _loadExam() async {
    try {
      final exam = await _service.getExternalExamById(widget.examId);
      if (exam == null) {
        setState(() {
          _errorMessage = 'Sınav bulunamadı.';
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _exam = exam;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Sınav bilgileri yüklenemedi: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectRoom(RoomSlot room, String grade) async {
    setState(() {
      _selectedRoom = room;
      _selectedRoomGrade = grade;
      _isLoadingStudents = true;
      _step = 1;
      _attendanceMap = {};
      _existingAttendance = null;
      _existingAttendanceId = null;
      _savedSuccessfully = false;
      _proctorController.clear();
    });

    try {
      // Öğrencileri çek
      final snap = await FirebaseFirestore.instance
          .collection('external_exam_registrations')
          .where('examId', isEqualTo: widget.examId)
          .where('assignedRoomId', isEqualTo: room.classroomId)
          .get();

      final students = snap.docs
          .map((d) => ExternalExamRegistration.fromMap(d.data(), d.id))
          .where((r) => r.status != RegistrationStatus.cancelled)
          .toList();

      students.sort((a, b) => (a.seatNumber ?? 0).compareTo(b.seatNumber ?? 0));

      // Mevcut yoklama kaydını çek (composite index gerektirmemesi için orderBy kullanmıyoruz)
      final attendSnap = await FirebaseFirestore.instance
          .collection('external_exam_attendance')
          .where('examId', isEqualTo: widget.examId)
          .where('roomId', isEqualTo: room.classroomId)
          .get();

      Map<String, bool> initialMap = {};
      for (final s in students) {
        initialMap[s.id!] = false;
      }

      if (attendSnap.docs.isNotEmpty) {
        // En güncel kaydı Dart'ta bul
        final sortedDocs = attendSnap.docs.toList()
          ..sort((a, b) {
            final aTs = a.data()['savedAt'];
            final bTs = b.data()['savedAt'];
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return (bTs as Timestamp).compareTo(aTs as Timestamp);
          });

        final doc = sortedDocs.first;
        final data = doc.data();
        _existingAttendance = data;
        _existingAttendanceId = doc.id;

        // Mevcut yoklama verilerini yükle
        final List<dynamic> attendances = data['attendances'] ?? [];
        for (final a in attendances) {
          final regId = a['registrationId'] as String?;
          final attended = a['attended'] as bool? ?? false;
          if (regId != null && initialMap.containsKey(regId)) {
            initialMap[regId] = attended;
          }
        }
        // Gözetmen adını prefill et
        _proctorController.text = data['proctorName'] ?? '';
      }

      setState(() {
        _students = students;
        _attendanceMap = initialMap;
        _isLoadingStudents = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingStudents = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Öğrenciler yüklenemedi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveAttendance() async {
    // Gözetmen adı zorunlu
    if (_proctorController.text.trim().isEmpty) {
      setState(() => _proctorError = true);
      return;
    }
    setState(() {
      _proctorError = false;
      _isSaving = true;
    });

    try {
      final attendances = _students.map((s) => {
        'registrationId': s.id,
        'studentName': s.fullName,
        'studentTcNo': s.studentTcNo,
        'gradeLevel': s.gradeLevel,
        'seatNumber': s.seatNumber,
        'attended': _attendanceMap[s.id!] ?? false,
      }).toList();

      final data = {
        'examId': widget.examId,
        'examTitle': _exam?.title ?? '',
        'roomId': _selectedRoom!.classroomId,
        'roomName': _selectedRoom!.classroomName,
        'gradeLevel': _selectedRoomGrade,
        'proctorName': _proctorController.text.trim(),
        'savedAt': FieldValue.serverTimestamp(),
        'attendedCount': _attendanceMap.values.where((v) => v).length,
        'totalCount': _students.length,
        'attendances': attendances,
      };

      final batch = FirebaseFirestore.instance.batch();

      if (_existingAttendanceId != null) {
        // Güncelle
        final attendRef = FirebaseFirestore.instance
            .collection('external_exam_attendance')
            .doc(_existingAttendanceId);
        batch.update(attendRef, data);
      } else {
        // Yeni kayıt
        final attendRef = FirebaseFirestore.instance
            .collection('external_exam_attendance')
            .doc();
        batch.set(attendRef, data);
        _existingAttendanceId = attendRef.id;
      }

      // Her öğrencinin isScanned bilgisini external_exam_registrations koleksiyonunda güncelle
      for (final s in _students) {
        if (s.id != null) {
          final regRef = FirebaseFirestore.instance
              .collection('external_exam_registrations')
              .doc(s.id);
          final bool attended = _attendanceMap[s.id!] ?? false;
          batch.update(regRef, {'isScanned': attended});
        }
      }

      await batch.commit();

      setState(() {
        _isSaving = false;
        _savedSuccessfully = true;
      });
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kayıt hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: _AnimatedLoadingView(),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorMessage!, style: GoogleFonts.inter(color: Colors.red, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    final exam = _exam!;
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          _buildHeader(exam, isMobile),
          Expanded(
            child: _step == 0
                ? _buildRoomSelectionStep(exam, isMobile)
                : _buildAttendanceStep(isMobile),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ExternalExam exam, bool isMobile) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE65100), Color(0xFFF57C00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 32,
        vertical: 20,
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (_step == 1)
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                onPressed: () => setState(() {
                  _step = 0;
                  _selectedRoom = null;
                  _savedSuccessfully = false;
                }),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.fact_check_rounded, color: Colors.white70, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'SINAV YOKLAMA SİSTEMİ',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    exam.title,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: isMobile ? 16 : 20,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_step == 1 && _selectedRoom != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Salon: ${_selectedRoom!.classroomName}',
                      style: GoogleFonts.inter(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Step indicator
            _buildStepChip(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _step == 0 ? 'Salon Seç' : 'Yoklama Al',
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ─────────────── ADIM 1: SALON SEÇİMİ ───────────────────────────────────

  Widget _buildRoomSelectionStep(ExternalExam exam, bool isMobile) {
    final assignments = exam.venueConfig.classroomAssignments;
    final allRooms = <_RoomItem>[];
    for (final a in assignments) {
      for (final r in a.rooms) {
        allRooms.add(_RoomItem(room: r, grade: a.gradeLevel));
      }
    }

    if (allRooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.meeting_room_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Henüz salon ataması yapılmamış.',
              style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // Info banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Aşağıdaki listeden yoklama almak istediğiniz salonun üzerine tıklayarak ilgili salonun yoklama ekranına geçiş yapabilirsiniz. Her salon için ayrı yoklama alınır.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Salon Listesi',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _darkColor,
                ),
              ),
              const SizedBox(height: 12),
              // Group by grade
              ...exam.venueConfig.classroomAssignments.map((assignment) {
                if (assignment.rooms.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8, top: 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: _primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              assignment.gradeLevel == 'Mezun'
                                  ? 'Mezun'
                                  : '${assignment.gradeLevel}. Sınıf',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _primaryColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...assignment.rooms.map((room) => _buildRoomCard(room, assignment.gradeLevel)),
                    const SizedBox(height: 8),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoomCard(RoomSlot room, String grade) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        elevation: 0,
        child: InkWell(
          onTap: () => _selectRoom(room, grade),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.meeting_room_rounded, color: _primaryColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.classroomName,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: _darkColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                        softWrap: true,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Kapasite: ${room.effectiveCapacity} kişi',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey.shade400, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────── ADIM 2: YOKLAMA ─────────────────────────────────────────

  Widget _buildAttendanceStep(bool isMobile) {
    if (_isLoadingStudents) {
      return const Center(child: CircularProgressIndicator(color: _primaryColor));
    }

    if (_savedSuccessfully) {
      return _buildSuccessView(isMobile);
    }

    final attendedCount = _attendanceMap.values.where((v) => v).length;

    return Column(
      children: [
        // Existing attendance banner
        if (_existingAttendance != null)
          Container(
            color: Colors.blue.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.edit_note_rounded, color: Colors.blue.shade700, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Bu salon için daha önce yoklama alınmış. Düzenleyip tekrar kaydedebilirsiniz.',
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.blue.shade700),
                  ),
                ),
              ],
            ),
          ),

        // Stats bar
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStatPill('Toplam', '${_students.length}', Colors.grey.shade700, Colors.grey.shade100),
                  const SizedBox(width: 6),
                  _buildStatPill('Geldi', '$attendedCount', Colors.green.shade700, Colors.green.shade50),
                  const SizedBox(width: 6),
                  _buildStatPill('Gelmedi', '${_students.length - attendedCount}', Colors.red.shade700, Colors.red.shade50),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Toplu seç butonları
                  TextButton.icon(
                    onPressed: () => setState(() {
                      for (final k in _attendanceMap.keys) {
                        _attendanceMap[k] = true;
                      }
                    }),
                    icon: const Icon(Icons.select_all_rounded, size: 14),
                    label: const Text('Tümü Geldi'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green.shade700,
                      textStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      for (final k in _attendanceMap.keys) {
                        _attendanceMap[k] = false;
                      }
                    }),
                    icon: const Icon(Icons.deselect_rounded, size: 14),
                    label: const Text('Temizle'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      textStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Öğrenci listesi
        Expanded(
          child: _students.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline_rounded, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        'Bu salona atanmış öğrenci bulunamadı.',
                        style: GoogleFonts.inter(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _students.length,
                  itemBuilder: (context, index) {
                    final s = _students[index];
                    final attended = _attendanceMap[s.id!] ?? false;
                    return _buildStudentRow(s, attended, index);
                  },
                ),
        ),

        // Bottom save panel
        _buildSavePanel(isMobile),
      ],
    );
  }

  Widget _buildStatPill(String label, String value, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11, color: textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentRow(ExternalExamRegistration s, bool attended, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: attended ? Colors.green.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: attended ? Colors.green.shade200 : Colors.grey.shade200,
          width: attended ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _attendanceMap[s.id!] = !attended;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Sıra numarası
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: attended ? Colors.green.shade100 : Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${s.seatNumber ?? (index + 1)}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: attended ? Colors.green.shade700 : Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Öğrenci bilgileri
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.fullName,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: attended ? Colors.green.shade800 : _darkColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'TC: ${s.studentTcNo}  •  ${s.gradeLevel == 'Mezun' ? 'Mezun' : '${s.gradeLevel}. Sınıf'}  •  ${s.currentSchool}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Checkbox benzeri indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: attended ? Colors.green : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: attended ? Colors.green : Colors.grey.shade300,
                    width: 2,
                  ),
                ),
                child: attended
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSavePanel(bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16, 16, 16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Gözetmen adı
          TextField(
            controller: _proctorController,
            onChanged: (_) {
              if (_proctorError) setState(() => _proctorError = false);
            },
            style: GoogleFonts.inter(fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Gözetmen Adı Soyadı *',
              labelStyle: GoogleFonts.inter(
                fontSize: 13,
                color: _proctorError ? Colors.red : Colors.grey.shade600,
              ),
              hintText: 'Adınızı ve soyadınızı yazınız',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400),
              prefixIcon: Icon(
                Icons.person_outline_rounded,
                color: _proctorError ? Colors.red : Colors.grey.shade400,
              ),
              filled: true,
              fillColor: _proctorError ? Colors.red.shade50 : const Color(0xFFF8FAFC),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _proctorError ? Colors.red : Colors.grey.shade200,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _proctorError ? Colors.red : _primaryColor,
                  width: 2,
                ),
              ),
              errorText: _proctorError ? 'Gözetmen adı zorunludur' : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
          // Kaydet butonu
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveAttendance,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(
                _isSaving
                    ? 'Kaydediliyor...'
                    : (_existingAttendanceId != null ? 'Yoklamayı Güncelle' : 'Yoklamayı Kaydet'),
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView(bool isMobile) {
    final attendedCount = _attendanceMap.values.where((v) => v).length;
    final absentCount = _students.length - attendedCount;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 48),
            ),
            const SizedBox(height: 24),
            Text(
              'Yoklama Kaydedildi!',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _darkColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedRoom?.classroomName ?? '',
              style: GoogleFonts.inter(fontSize: 15, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildResultCard('$attendedCount', 'Geldi', Colors.green),
                const SizedBox(width: 16),
                _buildResultCard('$absentCount', 'Gelmedi', Colors.red),
                const SizedBox(width: 16),
                _buildResultCard('${_students.length}', 'Toplam', Colors.blue),
              ],
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _savedSuccessfully = false;
              }),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Yoklamayı Düzenle'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryColor,
                side: const BorderSide(color: _primaryColor),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => setState(() {
                _step = 0;
                _selectedRoom = null;
                _savedSuccessfully = false;
              }),
              icon: const Icon(Icons.meeting_room_rounded),
              label: const Text('Başka Salon Seç'),
              style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _RoomItem {
  final RoomSlot room;
  final String grade;
  _RoomItem({required this.room, required this.grade});
}

class _AnimatedLoadingView extends StatefulWidget {
  const _AnimatedLoadingView({Key? key}) : super(key: key);

  @override
  State<_AnimatedLoadingView> createState() => _AnimatedLoadingViewState();
}

class _AnimatedLoadingViewState extends State<_AnimatedLoadingView> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  int _textIndex = 0;
  final List<String> _texts = [
    'Sınav bilgileri kontrol ediliyor...',
    'Güvenlik doğrulaması yapılıyor...',
    'Yoklama sistemi hazırlanıyor...',
    'Lütfen bekleyin...'
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _cycleText();
  }

  void _cycleText() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) break;
      setState(() {
        _textIndex = (_textIndex + 1) % _texts.length;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF57C00).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.fact_check_rounded, size: 64, color: Color(0xFFF57C00)),
            ),
          ),
          const SizedBox(height: 32),
          const CircularProgressIndicator(color: Color(0xFFF57C00)),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: Text(
              _texts[_textIndex],
              key: ValueKey<int>(_textIndex),
              style: GoogleFonts.inter(
                color: Colors.grey.shade700,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
