import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../../models/class_model.dart';
import '../../../../models/school/quick_performance_tracker_model.dart';
import '../../../../widgets/edukn_app_bar.dart';

class QuickPerformanceTrackerHubScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final String? initialClassId;

  const QuickPerformanceTrackerHubScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.initialClassId,
  });

  @override
  State<QuickPerformanceTrackerHubScreen> createState() => _QuickPerformanceTrackerHubScreenState();
}

class _QuickPerformanceTrackerHubScreenState extends State<QuickPerformanceTrackerHubScreen> {
  // Sınıf & Öğrenci Yönetimi
  List<ClassModel> _classes = [];
  int? _selectedClassLevel;
  String _selectedBranchId = 'all';
  List<QuickPerformanceStudent> _students = [];
  bool _isLoadingClasses = true;
  bool _isLoadingStudents = false;

  // Tarih Filtresi
  DateTime _selectedDate = DateTime.now();

  // Arama & Filtreleme
  String _searchQuery = '';
  String _activeFilter = 'all'; // 'all', 'positive', 'negative', 'neutral'
  bool _isSearchOpen = false;
  final TextEditingController _searchController = TextEditingController();

  List<int> get _availableClassLevels => _classes.map((c) => c.classLevel).toSet().toList()..sort();
  List<ClassModel> get _branchesForSelectedLevel => _selectedClassLevel == null
      ? []
      : (_classes.where((c) => c.classLevel == _selectedClassLevel).toList()
        ..sort((a, b) => a.className.compareTo(b.className)));

  String get _dateKey => DateFormat('yyyy-MM-dd').format(_selectedDate);

  // Günlük İstatistikler
  int get _totalPlusCount => _students.fold(0, (acc, s) => acc + s.plusCount);
  int get _totalMinusCount => _students.fold(0, (acc, s) => acc + s.minusCount);

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // VERİ YÜKLEME METOTLARI
  // ===========================================================================
  Future<void> _loadClasses() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      final list = snap.docs.map((d) => ClassModel.fromMap(d.data(), d.id)).toList();
      list.sort((a, b) => a.className.compareTo(b.className));

      if (mounted) {
        setState(() {
          _classes = list;
          _isLoadingClasses = false;

          final levels = list.map((c) => c.classLevel).toSet().toList()..sort();
          if (levels.isNotEmpty) {
            if (_selectedClassLevel == null || !levels.contains(_selectedClassLevel)) {
              _selectedClassLevel = levels.first;
            }
            _selectedBranchId = 'all';
          }
        });

        if (_selectedClassLevel != null) {
          _loadStudentsAndRecords();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingClasses = false);
    }
  }

  Future<void> _loadStudentsAndRecords() async {
    if (_selectedClassLevel == null) return;
    setState(() => _isLoadingStudents = true);

    try {
      final List<QuickPerformanceStudent> studentList = [];

      List<ClassModel> targetClasses = [];
      if (_selectedBranchId == 'all') {
        targetClasses = _branchesForSelectedLevel;
      } else {
        targetClasses = _classes.where((c) => c.id == _selectedBranchId).toList();
      }

      // 1. Öğrencileri Yükle
      for (var cls in targetClasses) {
        QuerySnapshot snap = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('classId', isEqualTo: cls.id)
            .get();

        if (snap.docs.isEmpty) {
          snap = await FirebaseFirestore.instance
              .collection('students')
              .where('institutionId', isEqualTo: widget.institutionId)
              .where('className', isEqualTo: cls.className)
              .get();
        }

        for (var doc in snap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final firstName = data['firstName'] ?? data['name'] ?? '';
          final lastName = data['lastName'] ?? data['surname'] ?? '';
          String fullName = '$firstName $lastName'.trim();
          if (fullName.isEmpty) fullName = 'Öğrenci';

          final genderStr = (data['gender'] ?? '').toString().toLowerCase().trim();
          final isGirl = genderStr.startsWith('k') || genderStr.startsWith('f') || genderStr == 'kadın' || genderStr == 'kız';
          final isBoy = genderStr.startsWith('e') || genderStr.startsWith('m') || genderStr == 'erkek';
          final gender = isGirl ? 'K' : (isBoy ? 'E' : 'unspecified');

          studentList.add(QuickPerformanceStudent(
            id: doc.id,
            name: fullName,
            studentNumber: data['studentNumber']?.toString() ?? data['schoolNumber']?.toString(),
            className: cls.className,
            gender: gender,
            avatarUrl: data['photoUrl'] ?? data['avatarUrl'],
            plusCount: 0,
            minusCount: 0,
            records: [],
          ));
        }
      }

      studentList.sort((a, b) => a.name.compareTo(b.name));

      // 2. Seçilen Günün Performans Kayıtlarını Yükle
      final recordsSnap = await FirebaseFirestore.instance
          .collection('student_performance_records')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('dateKey', isEqualTo: _dateKey)
          .get();

      final records = recordsSnap.docs
          .map((d) => PerformanceRecord.fromMap(d.data(), d.id))
          .toList();

      for (var student in studentList) {
        final sRecords = records.where((r) => r.studentId == student.id).toList();
        sRecords.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        student.records = sRecords;
        student.plusCount = sRecords.where((r) => r.isPlus).length;
        student.minusCount = sRecords.where((r) => r.isMinus).length;
      }

      if (mounted) {
        setState(() {
          _students = studentList;
          _isLoadingStudents = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingStudents = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veriler yüklenirken hata oluştu: $e')),
        );
      }
    }
  }

  // ===========================================================================
  // ARTI / EKSİ EKLEME VE GERİ ALMA (OPTIMISTIC UI & UNDO)
  // ===========================================================================
  Future<void> _addRecord(QuickPerformanceStudent student, String type) async {
    HapticFeedback.lightImpact();

    final isPlus = type == 'plus';
    final now = DateTime.now();

    // 1. İyimser Arayüz Güncellemesi (Optimistic UI - Sıfır Gecikme)
    setState(() {
      if (isPlus) {
        student.plusCount++;
      } else {
        student.minusCount++;
      }
    });

    final record = PerformanceRecord(
      id: '', // Firestore oluşturacak
      institutionId: widget.institutionId,
      classId: _selectedBranchId,
      className: student.className ?? '',
      studentId: student.id,
      studentName: student.name,
      type: type,
      scoreChange: isPlus ? 1 : -1,
      createdAt: now,
      dateKey: _dateKey,
    );

    try {
      final docRef = await FirebaseFirestore.instance
          .collection('student_performance_records')
          .add(record.toMap());

      final savedRecord = PerformanceRecord(
        id: docRef.id,
        institutionId: record.institutionId,
        classId: record.classId,
        className: record.className,
        studentId: record.studentId,
        studentName: record.studentName,
        type: record.type,
        scoreChange: record.scoreChange,
        createdAt: record.createdAt,
        dateKey: record.dateKey,
      );

      student.records.insert(0, savedRecord);

      if (!mounted) return;

      // 2. Geri Al (Undo) Özellikli SnackBar Göster
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          backgroundColor: isPlus ? const Color(0xFF059669) : const Color(0xFFDC2626),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(
            children: [
              Icon(
                isPlus ? Icons.add_circle_outline_rounded : Icons.remove_circle_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${student.name}\'e ${isPlus ? "Artı (+)" : "Eksi (-)"} verildi.',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Geri Al',
            textColor: const Color(0xFFFDE047),
            onPressed: () {
              _undoRecord(savedRecord, student);
            },
          ),
        ),
      );
    } catch (e) {
      // Hata durumunda sayacı geri al
      setState(() {
        if (isPlus) {
          student.plusCount--;
        } else {
          student.minusCount--;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kayıt eklenirken hata: $e')),
        );
      }
    }
  }

  Future<void> _undoRecord(PerformanceRecord record, QuickPerformanceStudent student) async {
    HapticFeedback.mediumImpact();

    setState(() {
      if (record.isPlus) {
        student.plusCount = (student.plusCount - 1).clamp(0, 999);
      } else {
        student.minusCount = (student.minusCount - 1).clamp(0, 999);
      }
      student.records.removeWhere((r) => r.id == record.id);
    });

    try {
      if (record.id.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('student_performance_records')
            .doc(record.id)
            .delete();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🔄 "${student.name}" için son işlem geri alındı.'),
            backgroundColor: const Color(0xFF4F46E5),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Geri alma işlemi başarısız oldu: $e')),
        );
      }
    }
  }

  // ===========================================================================
  // ANA ARAYÜZ (BUILD)
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: 'Hızlı Performans Takibi',
        subtitle: '${widget.schoolTypeName} • Anlık Artı/Eksi Değerlendirme',
      ),
      body: _isLoadingClasses
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 1. Üst Filtre & Tarih Seçim Çubuğu
                _buildTopFilterHeader(isMobile),

                // 2. Canlı İstatistik / Özet Çubuğu
                _buildDailyStatsBar(),

                // 3. Arama & Filtreleme Çubuğu
                _buildSearchAndFilterBar(),

                // 4. Öğrenci Listesi (ListView with Dismissible Swipe)
                Expanded(
                  child: _isLoadingStudents
                      ? const Center(child: CircularProgressIndicator())
                      : _buildStudentListView(),
                ),
              ],
            ),
    );
  }

  // ===========================================================================
  // ÜST FİLTRE VE TARİH ÇUBUĞU
  // ===========================================================================
  Widget _buildTopFilterHeader(bool isMobile) {
    final isToday = DateFormat('yyyy-MM-dd').format(_selectedDate) == DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: isMobile
          ? Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: _buildClassLevelDropdown(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _buildBranchDropdown(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildDateSelectorRow(isToday),
              ],
            )
          : Row(
              children: [
                SizedBox(
                  width: 140,
                  child: _buildClassLevelDropdown(),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 220,
                  child: _buildBranchDropdown(),
                ),
                const Spacer(),
                _buildDateSelectorRow(isToday),
              ],
            ),
    );
  }

  Widget _buildClassLevelDropdown() {
    return DropdownButtonFormField<int>(
      isExpanded: true,
      isDense: true,
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(16),
      value: _selectedClassLevel,
      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: Color(0xFF64748B)),
      decoration: InputDecoration(
        labelText: 'Seviye',
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF4F46E5)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: _availableClassLevels.map((lvl) {
        return DropdownMenuItem<int>(
          value: lvl,
          child: Text('$lvl. Sınıf', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFF1E293B))),
        );
      }).toList(),
      onChanged: (lvl) {
        if (lvl == null || lvl == _selectedClassLevel) return;
        setState(() {
          _selectedClassLevel = lvl;
          _selectedBranchId = 'all';
        });
        _loadStudentsAndRecords();
      },
    );
  }

  Widget _buildBranchDropdown() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      isDense: true,
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(16),
      value: _selectedBranchId,
      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: Color(0xFF64748B)),
      decoration: InputDecoration(
        labelText: 'Şube',
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF4F46E5)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: [
        DropdownMenuItem<String>(
          value: 'all',
          child: Text(
            '✨ Tümü',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF4F46E5), fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ..._branchesForSelectedLevel.map((c) {
          return DropdownMenuItem<String>(
            value: c.id!,
            child: Text(
              c.className,
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFF1E293B)),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }),
      ],
      onChanged: (val) {
        if (val == null || val == _selectedBranchId) return;
        setState(() {
          _selectedBranchId = val;
        });
        _loadStudentsAndRecords();
      },
    );
  }

  Widget _buildDateSelectorRow(bool isToday) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 22, color: Color(0xFF475569)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: () {
            setState(() {
              _selectedDate = _selectedDate.subtract(const Duration(days: 1));
            });
            _loadStudentsAndRecords();
          },
        ),
        InkWell(
          onTap: _pickCustomDate,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isToday ? const Color(0xFFEEF2FF) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isToday ? const Color(0xFFC7D2FE) : const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_rounded, size: 14, color: isToday ? const Color(0xFF4F46E5) : const Color(0xFF475569)),
                const SizedBox(width: 6),
                Text(
                  isToday ? 'Bugün (${DateFormat('d MMM', 'tr').format(_selectedDate)})' : DateFormat('d MMMM yyyy', 'tr').format(_selectedDate),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isToday ? const Color(0xFF4338CA) : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded, size: 22, color: Color(0xFF475569)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: () {
            setState(() {
              _selectedDate = _selectedDate.add(const Duration(days: 1));
            });
            _loadStudentsAndRecords();
          },
        ),
      ],
    );
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadStudentsAndRecords();
    }
  }

  // ===========================================================================
  // GÜNLÜK İSTATİSTİK ÇUBUĞU
  // ===========================================================================
  Widget _buildDailyStatsBar() {
    final netScore = _totalPlusCount - _totalMinusCount;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Mevcut', '${_students.length} Öğrenci', Colors.white70),
          Container(width: 1, height: 24, color: Colors.white24),
          _buildStatItem('Artılar', '+$_totalPlusCount', const Color(0xFF34D399)),
          Container(width: 1, height: 24, color: Colors.white24),
          _buildStatItem('Eksiler', '-$_totalMinusCount', const Color(0xFFF87171)),
          Container(width: 1, height: 24, color: Colors.white24),
          _buildStatItem(
            'Net Durum',
            '${netScore >= 0 ? "+" : ""}$netScore Net',
            netScore >= 0 ? const Color(0xFFFBBF24) : const Color(0xFFF87171),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color valueColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white60)),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: valueColor)),
      ],
    );
  }

  // ===========================================================================
  // ARAMA VE FİLTRELEME ÇUBUĞU (4 BUTON & ARAMA AÇILIR/KAPANIR MODU)
  // ===========================================================================
  Widget _buildSearchAndFilterBar() {
    if (_isSearchOpen) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF4F46E5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, size: 20, color: Color(0xFF4F46E5)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                  decoration: const InputDecoration(
                    hintText: 'Öğrenci adı, no veya şube ara...',
                    hintStyle: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  onSubmitted: (_) => setState(() => _isSearchOpen = false),
                ),
              ),
              if (_searchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF94A3B8)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
              // Onay / Arama Kapat Butonu (Tik)
              IconButton(
                icon: const Icon(Icons.check_circle_rounded, size: 22, color: Color(0xFF10B981)),
                tooltip: 'Aramayı Tamamla',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: () {
                  setState(() => _isSearchOpen = false);
                },
              ),
              // İptal / Kapat Butonu (Çarpı)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                tooltip: 'Aramayı Kapat',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _isSearchOpen = false;
                  });
                },
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // 1. Ara Butonu
          Expanded(
            child: _buildSegmentButton(
              isSelected: _searchQuery.isNotEmpty,
              icon: Icons.search_rounded,
              label: _searchQuery.isEmpty ? 'Ara' : _searchQuery,
              onTap: () => setState(() => _isSearchOpen = true),
            ),
          ),
          const SizedBox(width: 6),

          // 2. Tümü
          Expanded(
            child: _buildSegmentButton(
              isSelected: _activeFilter == 'all' && _searchQuery.isEmpty,
              label: 'Tümü',
              onTap: () => setState(() {
                _activeFilter = 'all';
                _searchQuery = '';
                _searchController.clear();
              }),
            ),
          ),
          const SizedBox(width: 6),

          // 3. Artılar
          Expanded(
            child: _buildSegmentButton(
              isSelected: _activeFilter == 'positive',
              icon: Icons.add_circle_outline_rounded,
              iconColor: const Color(0xFF059669),
              label: 'Artılar',
              onTap: () => setState(() => _activeFilter = 'positive'),
            ),
          ),
          const SizedBox(width: 6),

          // 4. Eksiler
          Expanded(
            child: _buildSegmentButton(
              isSelected: _activeFilter == 'negative',
              icon: Icons.remove_circle_outline_rounded,
              iconColor: const Color(0xFFDC2626),
              label: 'Eksiler',
              onTap: () => setState(() => _activeFilter = 'negative'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton({
    required bool isSelected,
    required String label,
    required VoidCallback onTap,
    IconData? icon,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4F46E5) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isSelected ? 0.08 : 0.02),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isSelected ? Colors.white : (iconColor ?? const Color(0xFF64748B)),
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF334155),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // ÖĞRENCİ LİSTESİ (DISMISSIBLE SWIPE + FAST BUTTONS)
  // ===========================================================================
  Widget _buildStudentListView() {
    final filtered = _students.where((s) {
      // 1. Arama Filtresi
      final matchesSearch = _searchQuery.isEmpty ||
          s.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (s.studentNumber?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
          (s.className?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);

      if (!matchesSearch) return false;

      // 2. Kategori Filtresi
      if (_activeFilter == 'positive') return s.plusCount > 0;
      if (_activeFilter == 'negative') return s.minusCount > 0;

      return true;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline_rounded, size: 54, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            Text(
              'Öğrenci bulunamadı',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15, color: const Color(0xFF64748B)),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final student = filtered[idx];
        return _buildStudentTileWithSwipe(student);
      },
    );
  }

  Widget _buildStudentTileWithSwipe(QuickPerformanceStudent student) {
    return Dismissible(
      key: ValueKey('swipe_${student.id}_${student.plusCount}_${student.minusCount}'),
      direction: DismissDirection.horizontal,

      // Sağa Kaydırma (Swipe Right ➡️ Artı Ver)
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.add_circle_rounded, color: Colors.white, size: 24),
            const SizedBox(width: 8),
            Text(
              'Artı (+) Ver',
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
          ],
        ),
      ),

      // Sola Kaydırma (Swipe Left ⬅️ Eksi Ver)
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Eksi (-) Ver',
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.remove_circle_rounded, color: Colors.white, size: 24),
          ],
        ),
      ),

      // Satır kaybolmaz, işlemi tetikler ve yerine geri döner
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          _addRecord(student, 'plus');
        } else {
          _addRecord(student, 'minus');
        }
        return false; // Satırın yok olmasını engeller, yerine yaylanır
      },

      child: Card(
        elevation: 0.5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        color: Colors.white,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showStudentDetailsModal(student),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Cinsiyet Renkli Avatar
                CircleAvatar(
                  radius: 17,
                  backgroundColor: student.isFemale
                      ? const Color(0xFFFCE7F3)
                      : (student.isMale ? const Color(0xFFDBEAFE) : Colors.grey.shade200),
                  child: Text(
                    student.name.isNotEmpty ? student.name[0] : '?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: student.isFemale
                          ? const Color(0xFFDB2777)
                          : (student.isMale ? const Color(0xFF2563EB) : Colors.black87),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Öğrenci Adı, Şube ve Sayaç Rozetleri (Tek Satır Garantisi)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        student.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${student.className ?? ""} ${student.studentNumber != null ? "• No: ${student.studentNumber}" : ""}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // Canlı Artı Rozeti
                          if (student.plusCount > 0)
                            Container(
                              margin: const EdgeInsets.only(right: 3),
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: Text(
                                '+${student.plusCount}',
                                style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w900, color: const Color(0xFF059669)),
                              ),
                            ),

                          // Canlı Eksi Rozeti
                          if (student.minusCount > 0)
                            Container(
                              margin: const EdgeInsets.only(right: 3),
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: const Color(0xFFFECACA)),
                              ),
                              child: Text(
                                '-${student.minusCount}',
                                style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w900, color: const Color(0xFFDC2626)),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // HIZLI ERİŞİM BUTONLARI: YEŞİL (+) VE KIRMIZI (-) (KOMPAKT 34x34)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Kırmızı Eksi (-) Butonu
                    Material(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () => _addRecord(student, 'minus'),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFECACA), width: 1.2),
                          ),
                          child: const Icon(Icons.remove_rounded, color: Color(0xFFDC2626), size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Yeşil Artı (+) Butonu
                    Material(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () => _addRecord(student, 'plus'),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFA7F3D0), width: 1.2),
                          ),
                          child: const Icon(Icons.add_rounded, color: Color(0xFF059669), size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // ÖĞRENCİ GÜNLÜK DETAY MODALI
  // ===========================================================================
  void _showStudentDetailsModal(QuickPerformanceStudent student) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: student.isFemale ? const Color(0xFFFCE7F3) : const Color(0xFFDBEAFE),
                        child: Text(student.name.isNotEmpty ? student.name[0] : '?', style: TextStyle(color: student.isFemale ? const Color(0xFFDB2777) : const Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(student.name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text('${student.className ?? ""} • $_dateKey', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          '${student.netScore >= 0 ? "+" : ""}${student.netScore} Net',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12.5, color: const Color(0xFF4F46E5)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Bugün Alınan Değerlendirmeler (${student.records.length})', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF334155))),
                  const SizedBox(height: 8),
                  if (student.records.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      child: Text('Henüz değerlendirme kaydı yok', style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 13)),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: student.records.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final r = student.records[idx];
                          final isPlus = r.isPlus;

                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: isPlus ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                              child: Icon(
                                isPlus ? Icons.add_rounded : Icons.remove_rounded,
                                color: isPlus ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                size: 16,
                              ),
                            ),
                            title: Text(
                              isPlus ? 'Artı (+) Değerlendirme' : 'Eksi (-) Değerlendirme',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: isPlus ? const Color(0xFF065F46) : const Color(0xFF991B1B)),
                            ),
                            subtitle: Text(DateFormat('HH:mm').format(r.createdAt), style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                              tooltip: 'Bu Kaydı Sil',
                              onPressed: () async {
                                await _undoRecord(r, student);
                                setModalState(() {});
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Kapat'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
