import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../../models/class_model.dart';
import '../../../../models/school/random_student_picker_model.dart';
import '../../../../widgets/edukn_app_bar.dart';

class RandomStudentPickerHubScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final String? initialClassId;

  const RandomStudentPickerHubScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.initialClassId,
  });

  @override
  State<RandomStudentPickerHubScreen> createState() => _RandomStudentPickerHubScreenState();
}

class _RandomStudentPickerHubScreenState extends State<RandomStudentPickerHubScreen>
    with TickerProviderStateMixin {
  // Sınıf & Öğrenci Yönetimi
  List<ClassModel> _classes = [];
  int? _selectedClassLevel;
  String _selectedBranchId = 'all';
  List<PickerStudent> _students = [];
  bool _isLoadingClasses = true;
  bool _isLoadingStudents = false;

  // Çekiliş Durumu & Ayarları
  PickerAnimationMode _animationMode = PickerAnimationMode.wheel;
  bool _removePickedFromPool = true; // Adil Dağıtım: Seçileni havuzdan çıkar
  bool _isFullscreen = false; // Akıllı Tahta Tam Ekran Modu
  bool _isSpinning = false;
  String _searchFilter = '';

  // Geçmiş / Log Listesi
  final List<PickerLog> _historyLogs = [];
  PickerStudent? _lastWinner;

  // Animasyon Controller'ları
  late AnimationController _wheelController;
  late Animation<double> _wheelAnimation;
  double _currentWheelAngle = 0.0;

  // Slot Makinesi İçin Scroll / Timer
  late ScrollController _slotScrollController;
  Timer? _slotTimer;
  int _slotHighlightedIndex = 0;

  // Konfeti Animasyonu
  late AnimationController _confettiController;
  final List<_ConfettiParticle> _confettiParticles = [];
  final Random _random = Random();

  List<int> get _availableClassLevels => _classes.map((c) => c.classLevel).toSet().toList()..sort();
  List<ClassModel> get _branchesForSelectedLevel => _selectedClassLevel == null
      ? []
      : (_classes.where((c) => c.classLevel == _selectedClassLevel).toList()
        ..sort((a, b) => a.className.compareTo(b.className)));

  /// Çekilişte dönecek aktif havuzdaki öğrenciler
  List<PickerStudent> get _activePool =>
      _students.where((s) => s.isPresent && (!s.isPicked || !_removePickedFromPool)).toList();

  /// Tüm mevcut öğrenciler (Yoklamada var olanlar)
  List<PickerStudent> get _presentStudents => _students.where((s) => s.isPresent).toList();

  @override
  void initState() {
    super.initState();

    _wheelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    );

    _slotScrollController = ScrollController();

    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..addListener(() {
        if (_confettiController.isAnimating) {
          for (var p in _confettiParticles) {
            p.update();
          }
          setState(() {});
        }
      });

    _loadClasses();
  }

  @override
  void dispose() {
    _wheelController.dispose();
    _slotScrollController.dispose();
    _slotTimer?.cancel();
    _confettiController.dispose();
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
          _loadStudentsForSelection();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingClasses = false);
    }
  }

  Future<void> _loadStudentsForSelection() async {
    if (_selectedClassLevel == null) return;
    setState(() => _isLoadingStudents = true);

    try {
      final List<PickerStudent> loaded = [];

      List<ClassModel> targetClasses = [];
      if (_selectedBranchId == 'all') {
        targetClasses = _branchesForSelectedLevel;
      } else {
        targetClasses = _classes.where((c) => c.id == _selectedBranchId).toList();
      }

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

          loaded.add(PickerStudent(
            id: doc.id,
            name: fullName,
            studentNumber: data['studentNumber']?.toString() ?? data['schoolNumber']?.toString(),
            className: cls.className,
            gender: gender,
            avatarUrl: data['photoUrl'] ?? data['avatarUrl'],
            isPresent: true,
            isPicked: false,
          ));
        }
      }

      loaded.sort((a, b) => a.name.compareTo(b.name));

      if (mounted) {
        setState(() {
          _students = loaded;
          _isLoadingStudents = false;
          _historyLogs.clear();
          _lastWinner = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingStudents = false);
    }
  }

  // ===========================================================================
  // ÇEKİLİŞ & ANİMASYON MOTORU
  // ===========================================================================
  void _startPickProcess() {
    if (_isSpinning) return;
    final pool = _activePool;

    if (pool.isEmpty) {
      if (_presentStudents.isNotEmpty && _removePickedFromPool) {
        _showPoolExhaustedDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Çekiliş havuzunda aktif öğrenci bulunmuyor!'),
            backgroundColor: Color(0xFFEA580C),
          ),
        );
      }
      return;
    }

    // 1. Kazananı rastgele belirle
    final winnerIndex = _random.nextInt(pool.length);
    final winner = pool[winnerIndex];

    HapticFeedback.mediumImpact();

    setState(() {
      _isSpinning = true;
      _lastWinner = null;
    });

    if (_animationMode == PickerAnimationMode.wheel) {
      _spinWheelAnimation(winner, winnerIndex, pool.length);
    } else {
      _spinSlotAnimation(winner, pool);
    }
  }

  /// 🎡 Çarkıfelek Dönüş Animasyonu
  void _spinWheelAnimation(PickerStudent winner, int winnerIndex, int totalSlices) {
    final sliceAngle = (2 * pi) / totalSlices;

    // Hedef açı: İbre en üstte (270° = 1.5 * pi veya 3*pi/2).
    // Dilimin tam ortasına denk getirecek açı ofseti:
    final targetSliceCenterAngle = (winnerIndex * sliceAngle) + (sliceAngle / 2);

    // Çarkın ibreye (tepeye / 3*pi/2) oturması için gereken dönüş:
    // (5 ile 8 tam tur + hedef açının ibreye hizalanması)
    final fullTurns = 6 + _random.nextInt(3);
    final finalAngle = (fullTurns * 2 * pi) + (3 * pi / 2 - targetSliceCenterAngle);

    _wheelAnimation = Tween<double>(
      begin: _currentWheelAngle,
      end: _currentWheelAngle + finalAngle,
    ).animate(CurvedAnimation(
      parent: _wheelController,
      curve: Curves.easeOutQuart,
    ));

    _wheelController.reset();
    _wheelController.forward().then((_) {
      _currentWheelAngle = (_currentWheelAngle + finalAngle) % (2 * pi);
      _finishPicking(winner);
    });
  }

  /// 🎰 Slot Makinesi Akış Animasyonu
  void _spinSlotAnimation(PickerStudent winner, List<PickerStudent> pool) {
    int ticks = 0;
    const totalTicks = 28;
    int intervalMs = 60;

    _slotTimer?.cancel();
    _slotTimer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      ticks++;

      if (mounted) {
        setState(() {
          _slotHighlightedIndex = (ticks) % pool.length;
        });
      }

      if (ticks >= totalTicks) {
        timer.cancel();
        _finishPicking(winner);
      }
    });
  }

  /// Çekiliş Sonuçlandırma & Kutlama
  void _finishPicking(PickerStudent winner) {
    HapticFeedback.heavyImpact();

    setState(() {
      _isSpinning = false;
      _lastWinner = winner;

      if (_removePickedFromPool) {
        winner.isPicked = true;
      }

      _historyLogs.insert(
        0,
        PickerLog(
          id: 'log_${DateTime.now().millisecondsSinceEpoch}',
          studentId: winner.id,
          studentName: winner.name,
          className: winner.className,
          gender: winner.gender,
          pickedAt: DateTime.now(),
          orderNumber: _historyLogs.length + 1,
        ),
      );
    });

    _triggerConfetti();
    _showWinnerDialog(winner);
  }

  /// Konfeti Parçacıklarını Ateşle
  void _triggerConfetti() {
    _confettiParticles.clear();
    final colors = [
      const Color(0xFF4F46E5),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFFEC4899),
      const Color(0xFF8B5CF6),
      const Color(0xFF06B6D4),
    ];

    for (int i = 0; i < 70; i++) {
      _confettiParticles.add(_ConfettiParticle(
        x: 0.5 + (_random.nextDouble() * 0.2 - 0.1),
        y: 0.3,
        vx: (_random.nextDouble() - 0.5) * 16,
        vy: -(_random.nextDouble() * 14 + 6),
        color: colors[_random.nextInt(colors.length)],
        size: _random.nextDouble() * 8 + 6,
      ));
    }

    _confettiController.reset();
    _confettiController.forward();
  }

  void _resetPool() {
    setState(() {
      for (var s in _students) {
        s.isPicked = false;
      }
      _lastWinner = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✨ Çekiliş havuzu başarıyla sıfırlandı! Tüm öğrenciler tekrar havuzda.'),
        backgroundColor: Color(0xFF10B981),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showPoolExhaustedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.celebration_rounded, color: Color(0xFFF59E0B), size: 28),
            const SizedBox(width: 10),
            Text('Tüm Öğrenciler Seçildi!', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'Sınıftaki tüm aktif öğrenciler 1\'er kez seçildi ve havuz tamamlandı. Havuzu sıfırlayarak yeni bir tura başlayabilirsiniz.',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _resetPool();
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Havuzu Yeniden Doldur'),
          ),
        ],
      ),
    );
  }

  void _showWinnerDialog(PickerStudent winner) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              '🎉 TEBRİKLER!',
              style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 16, color: const Color(0xFF4F46E5), letterSpacing: 1.2),
            ),
            const SizedBox(height: 8),
            Text(
              winner.name,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 24, color: const Color(0xFF1E293B)),
            ),
            if (winner.className != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${winner.className} Şubesi ${winner.studentNumber != null ? "• No: ${winner.studentNumber}" : ""}',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF4338CA)),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'Kapat',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5, color: const Color(0xFF475569)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _startPickProcess();
                    },
                    child: Text(
                      'Tekrar Çevir',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // ANA ARAYÜZ (BUILD)
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _isFullscreen
          ? null
          : EduknAppBar(
              title: 'Rastgele Öğrenci Seçici',
              subtitle: '${widget.schoolTypeName} • Çarkıfelek & Slot Makinesi',
              actions: [
                IconButton(
                  tooltip: 'Akıllı Tahta Tam Ekran Modu',
                  icon: const Icon(Icons.fullscreen_rounded, color: Colors.white),
                  onPressed: () => setState(() => _isFullscreen = true),
                ),
              ],
            ),
      body: _isLoadingClasses
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    if (!_isFullscreen) _buildTopFilterHeader(isMobile),
                    Expanded(
                      child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
                    ),
                  ],
                ),
                // Konfeti Çizimi
                if (_confettiController.isAnimating)
                  IgnorePointer(
                    child: CustomPaint(
                      size: MediaQuery.of(context).size,
                      painter: _ConfettiPainter(particles: _confettiParticles),
                    ),
                  ),
                // Tam Ekrandan Çıkış Butonu
                if (_isFullscreen)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: FloatingActionButton.small(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white,
                      tooltip: 'Tam Ekrandan Çık',
                      onPressed: () => setState(() => _isFullscreen = false),
                      child: const Icon(Icons.fullscreen_exit_rounded),
                    ),
                  ),
              ],
            ),
    );
  }

  // ===========================================================================
  // ÜST FİLTRE VE SINIF SEÇİM ÇUBUĞU
  // ===========================================================================
  Widget _buildTopFilterHeader(bool isMobile) {
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
                _buildModeAndSettingSwitches(isMobile),
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
                _buildModeAndSettingSwitches(isMobile),
              ],
            ),
    );
  }

  Widget _buildClassLevelDropdown() {
    return DropdownButtonFormField<int>(
      isExpanded: true,
      isDense: true,
      value: _selectedClassLevel,
      decoration: InputDecoration(
        labelText: 'Seviye',
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      items: _availableClassLevels.map((lvl) {
        return DropdownMenuItem<int>(
          value: lvl,
          child: Text('$lvl. Sınıflar', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5)),
        );
      }).toList(),
      onChanged: (lvl) {
        if (lvl == null || lvl == _selectedClassLevel) return;
        setState(() {
          _selectedClassLevel = lvl;
          _selectedBranchId = 'all';
        });
        _loadStudentsForSelection();
      },
    );
  }

  Widget _buildBranchDropdown() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      isDense: true,
      value: _selectedBranchId,
      decoration: InputDecoration(
        labelText: 'Şube',
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      items: [
        DropdownMenuItem<String>(
          value: 'all',
          child: Text('✨ Tümü (${_selectedClassLevel ?? ""}. Sınıf)', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF4338CA), fontSize: 12.5), overflow: TextOverflow.ellipsis),
        ),
        ..._branchesForSelectedLevel.map((c) {
          return DropdownMenuItem<String>(
            value: c.id!,
            child: Text('${c.className} Şubesi', style: GoogleFonts.inter(fontSize: 12.5), overflow: TextOverflow.ellipsis),
          );
        }),
      ],
      onChanged: (val) {
        if (val == null || val == _selectedBranchId) return;
        setState(() {
          _selectedBranchId = val;
        });
        _loadStudentsForSelection();
      },
    );
  }

  Widget _buildModeAndSettingSwitches(bool isMobile) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Animasyon Modu Seçici Segment
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModeOption(PickerAnimationMode.wheel, '🎡 Çark'),
              _buildModeOption(PickerAnimationMode.slot, '🎰 Slot'),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // Adil Dağıtım Toggle
        InkWell(
          onTap: () => setState(() => _removePickedFromPool = !_removePickedFromPool),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _removePickedFromPool ? const Color(0xFFECFDF5) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _removePickedFromPool ? const Color(0xFFA7F3D0) : Colors.grey.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _removePickedFromPool ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                  size: 16,
                  color: _removePickedFromPool ? const Color(0xFF059669) : Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  'Seçileni Çıkar',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: _removePickedFromPool ? const Color(0xFF065F46) : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeOption(PickerAnimationMode mode, String label) {
    final isSelected = _animationMode == mode;
    return InkWell(
      onTap: () => setState(() => _animationMode = mode),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)] : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // MASAÜSTÜ (DESKTOP / WEB) DÜZENİ
  // ===========================================================================
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Sol Panel: Çarkıfelek / Slot Animasyon Sahnesi & Aksiyon Butonu
        Expanded(
          flex: 6,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildAnimatedStage(),
                  const SizedBox(height: 24),
                  _buildBigActionButton(),
                ],
              ),
            ),
          ),
        ),

        // Sağ Panel: Yoklama / Havuz Filtresi ve Geçmiş Listesi
        Expanded(
          flex: 4,
          child: Container(
            margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    labelColor: const Color(0xFF4F46E5),
                    unselectedLabelColor: const Color(0xFF64748B),
                    indicatorColor: const Color(0xFF4F46E5),
                    labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                    tabs: [
                      Tab(text: 'Havuz & Yoklama (${_activePool.length}/${_presentStudents.length})'),
                      Tab(text: 'Bugün Seçilenler (${_historyLogs.length})'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildAttendancePoolTab(),
                        _buildHistoryLogTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // MOBİL DÜZENİ
  // ===========================================================================
  Widget _buildMobileLayout() {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              labelColor: const Color(0xFF4F46E5),
              unselectedLabelColor: const Color(0xFF64748B),
              indicatorColor: const Color(0xFF4F46E5),
              labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12.5),
              tabs: [
                const Tab(icon: Icon(Icons.casino_rounded, size: 18), text: 'Çekiliş Sahnesi'),
                Tab(icon: const Icon(Icons.how_to_reg_rounded, size: 18), text: 'Havuz (${_activePool.length})'),
                Tab(icon: const Icon(Icons.history_rounded, size: 18), text: 'Geçmiş (${_historyLogs.length})'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                // 1. Tab: Çekiliş Sahnesi
                SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: Column(
                    children: [
                      _buildAnimatedStage(),
                      const SizedBox(height: 20),
                      _buildBigActionButton(),
                      if (_lastWinner != null) ...[
                        const SizedBox(height: 16),
                        _buildLastWinnerCard(),
                      ],
                    ],
                  ),
                ),

                // 2. Tab: Havuz & Yoklama
                _buildAttendancePoolTab(),

                // 3. Tab: Geçmiş Listesi
                _buildHistoryLogTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ANİMASYONLU ÇEKİLİŞ SAHNESİ (WHEEL / SLOT)
  // ===========================================================================
  Widget _buildAnimatedStage() {
    final pool = _activePool;

    if (pool.isEmpty) {
      return Container(
        height: 320,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.groups_rounded, size: 54, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            Text(
              _presentStudents.isEmpty ? 'Sınıfta öğrenci bulunamadı' : 'Tüm öğrenciler seçildi!',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF475569)),
            ),
            const SizedBox(height: 6),
            Text(
              'Yeni çekiliş için havuzu yenileyin',
              style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _resetPool,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Havuzu Doldur'),
            ),
          ],
        ),
      );
    }

    if (_animationMode == PickerAnimationMode.wheel) {
      return _buildFortuneWheelView(pool);
    } else {
      return _buildSlotMachineView(pool);
    }
  }

  /// 🎡 Renkli Çarkıfelek Görünümü (Wheel Painter)
  Widget _buildFortuneWheelView(List<PickerStudent> pool) {
    const wheelSize = 320.0;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Dönen Çark
        AnimatedBuilder(
          animation: _wheelController,
          builder: (context, child) {
            final angle = _wheelController.isAnimating ? _wheelAnimation.value : _currentWheelAngle;

            return Transform.rotate(
              angle: angle,
              child: Container(
                width: wheelSize,
                height: wheelSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.2),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: CustomPaint(
                  size: const Size(wheelSize, wheelSize),
                  painter: _WheelPainter(students: pool),
                ),
              ),
            );
          },
        ),

        // Merkez Göbek Rozeti
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: const Color(0xFF4F46E5), width: 3),
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFF59E0B), size: 24),
        ),

        // Üst İbre / Pointer (Tepede Aşağı Doğru Bakan Ok)
        Positioned(
          top: 0,
          child: CustomPaint(
            size: const Size(36, 40),
            painter: _TopPointerPainter(),
          ),
        ),
      ],
    );
  }

  /// 🎰 Neon Slot Makinesi Görünümü
  Widget _buildSlotMachineView(List<PickerStudent> pool) {
    return Container(
      width: 320,
      height: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: const Color(0xFF6366F1), width: 2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Kayan İsimler
          ListView.builder(
            controller: _slotScrollController,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pool.length * 3,
            itemBuilder: (context, index) {
              final student = pool[index % pool.length];
              final isHighlighted = (index % pool.length) == _slotHighlightedIndex;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isHighlighted ? const Color(0xFF4F46E5).withValues(alpha: 0.3) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: student.isFemale ? const Color(0xFFEC4899) : const Color(0xFF3B82F6),
                      child: Text(
                        student.name.isNotEmpty ? student.name[0] : '?',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      student.name,
                      style: GoogleFonts.inter(
                        fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w500,
                        fontSize: isHighlighted ? 16 : 14,
                        color: isHighlighted ? const Color(0xFFFBBF24) : Colors.white70,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Odak Çerçevesi
          Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFBBF24), width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFBBF24).withValues(alpha: 0.2),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // BÜYÜK ÇEKİLİŞ AKSİYON BUTONU
  // ===========================================================================
  Widget _buildBigActionButton() {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: _isSpinning ? const Color(0xFF94A3B8) : const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
        elevation: 6,
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        shadowColor: const Color(0xFF4F46E5).withValues(alpha: 0.5),
      ),
      onPressed: _isSpinning ? null : _startPickProcess,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _animationMode == PickerAnimationMode.wheel ? Icons.pie_chart_rounded : Icons.view_carousel_rounded,
            size: 24,
          ),
          const SizedBox(width: 12),
          Text(
            _isSpinning
                ? 'DÖNÜYOR...'
                : (_animationMode == PickerAnimationMode.wheel ? 'ÇARKI ÇEVİR' : 'ÖĞRENCİ ÇEK'),
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 1.1),
          ),
        ],
      ),
    );
  }

  Widget _buildLastWinnerCard() {
    final winner = _lastWinner;
    if (winner == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFF4F46E5),
            radius: 16,
            child: Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Son Seçilen Öğrenci', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                Text(winner.name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF1E293B))),
              ],
            ),
          ),
          if (winner.className != null)
            Text(winner.className!, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF4F46E5))),
        ],
      ),
    );
  }

  // ===========================================================================
  // 1. TAB: HAVUZ & YOKLAMA LİSTESİ
  // ===========================================================================
  Widget _buildAttendancePoolTab() {
    final filtered = _students.where((s) {
      if (_searchFilter.isEmpty) return true;
      return s.name.toLowerCase().contains(_searchFilter.toLowerCase()) ||
          (s.className?.toLowerCase().contains(_searchFilter.toLowerCase()) ?? false);
    }).toList();

    return Column(
      children: [
        // Arama & Hızlı Butonlar
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Öğrenci ara...',
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF64748B)),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            ),
            onChanged: (v) => setState(() => _searchFilter = v.trim()),
          ),
        ),

        // Hızlı Aksiyonlar: Tümünü Seç / Kaldır & Sayaç
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Havuz: ${_activePool.length} / ${_presentStudents.length} Aktif',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF4F46E5)),
              ),
              Row(
                children: [
                  TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 26)),
                    onPressed: () {
                      setState(() {
                        for (var s in _students) {
                          s.isPresent = true;
                        }
                      });
                    },
                    child: const Text('Tümünü Seç', style: TextStyle(fontSize: 11.5)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 26)),
                    onPressed: () {
                      setState(() {
                        for (var s in _students) {
                          s.isPresent = false;
                        }
                      });
                    },
                    child: const Text('Tümünü Kaldır', style: TextStyle(fontSize: 11.5, color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Öğrenci Listesi
        Expanded(
          child: _isLoadingStudents
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(child: Text('Öğrenci bulunamadı', style: GoogleFonts.inter(color: Colors.grey.shade500)))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final student = filtered[idx];

                        return CheckboxListTile(
                          dense: true,
                          value: student.isPresent,
                          activeColor: const Color(0xFF4F46E5),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          secondary: CircleAvatar(
                            radius: 14,
                            backgroundColor: student.isFemale
                                ? const Color(0xFFFCE7F3)
                                : (student.isMale ? const Color(0xFFDBEAFE) : Colors.grey.shade200),
                            child: Text(
                              student.name.isNotEmpty ? student.name[0] : '?',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: student.isFemale
                                    ? const Color(0xFFDB2777)
                                    : (student.isMale ? const Color(0xFF2563EB) : Colors.black87),
                              ),
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  student.name,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    decoration: student.isPresent ? null : TextDecoration.lineThrough,
                                    color: student.isPresent
                                        ? (student.isPicked && _removePickedFromPool ? const Color(0xFF94A3B8) : const Color(0xFF1E293B))
                                        : Colors.grey.shade400,
                                  ),
                                ),
                              ),
                              if (student.isPicked && _removePickedFromPool)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFFDE68A)),
                                  ),
                                  child: Text(
                                    'Seçildi',
                                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFD97706)),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            '${student.className ?? ""} ${student.studentNumber != null ? "• No: ${student.studentNumber}" : ""}',
                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                          ),
                          onChanged: (val) {
                            setState(() {
                              student.isPresent = val ?? false;
                              if (val == true && student.isPicked) {
                                student.isPicked = false;
                              }
                            });
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 2. TAB: BUGÜN SEÇİLENLER (GEÇMİŞ LOG LİSTESİ)
  // ===========================================================================
  Widget _buildHistoryLogTab() {
    if (_historyLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.history_rounded, size: 48, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 10),
            Text(
              'Henüz çekiliş yapılmadı',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 4),
            Text(
              'Seçilen öğrenciler burada listelenecektir',
              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF94A3B8)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Toplam Seçim: ${_historyLogs.length}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12.5, color: const Color(0xFF334155))),
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 26)),
                icon: const Icon(Icons.refresh_rounded, size: 14, color: Colors.red),
                label: const Text('Seçimleri Sıfırla (Havuzu Doldur)', style: TextStyle(fontSize: 11.5, color: Colors.red, fontWeight: FontWeight.bold)),
                onPressed: () {
                  setState(() {
                    _historyLogs.clear();
                    for (var s in _students) {
                      s.isPicked = false;
                    }
                    _lastWinner = null;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🔄 Tüm seçimler temizlendi! Tüm öğrenciler tekrar havuzda.'),
                      backgroundColor: Color(0xFF10B981),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: _historyLogs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, idx) {
              final log = _historyLogs[idx];

              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: const Color(0xFFEEF2FF),
                  child: Text(
                    '#${log.orderNumber}',
                    style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: const Color(0xFF4F46E5)),
                  ),
                ),
                title: Text(log.studentName, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text(log.className ?? '', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('HH:mm').format(log.pickedAt),
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF94A3B8)),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFEF4444)),
                      tooltip: 'Seçimi İptal Et ve Tekrar Havuzuna Ekle',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () {
                        setState(() {
                          _historyLogs.removeAt(idx);
                          // Öğrencinin seçilme durumunu sıfırla, tekrar havuza girsin
                          final match = _students.where((s) => s.id == log.studentId).toList();
                          if (match.isNotEmpty) {
                            match.first.isPicked = false;
                          }
                          if (_lastWinner?.id == log.studentId) {
                            _lastWinner = null;
                          }
                        });

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('🔄 "${log.studentName}" seçimi iptal edildi ve tekrar havuza eklendi!'),
                            duration: const Duration(seconds: 2),
                            backgroundColor: const Color(0xFF4F46E5),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// ÇARKI VE İBREYİ ÇİZEN ÖZEL PAINTER SINIFLARI
// =============================================================================
class _WheelPainter extends CustomPainter {
  final List<PickerStudent> students;

  static const List<Color> sliceColors = [
    Color(0xFF4F46E5), // İndigo
    Color(0xFF059669), // Zümrüt Yeşili
    Color(0xFFD97706), // Kehribar
    Color(0xFFDC2626), // Kırmızı
    Color(0xFF0284C7), // Mavi
    Color(0xFF7C3AED), // Mor
    Color(0xFFDB2777), // Pembe
    Color(0xFF0D9488), // Teal
    Color(0xFFEA580C), // Turuncu
    Color(0xFF65A30D), // Fıstık Yeşili
  ];

  _WheelPainter({required this.students});

  @override
  void paint(Canvas canvas, Size size) {
    if (students.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final sliceAngle = (2 * pi) / students.length;

    final paint = Paint()..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < students.length; i++) {
      final startAngle = i * sliceAngle;
      final student = students[i];

      // 1. Dilim Rengini Çiz
      paint.color = sliceColors[i % sliceColors.length];
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sliceAngle,
        true,
        paint,
      );

      // 2. Dilim Ayrım Çizgisi
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sliceAngle,
        true,
        linePaint,
      );

      // 3. Dilim Üzerindeki Öğrenci İsmini Çiz
      final midAngle = startAngle + (sliceAngle / 2);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(midAngle);

      final textSpan = TextSpan(
        text: student.shortName,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: (students.length > 20 ? 9.5 : (students.length > 12 ? 11.0 : 12.5)),
          fontWeight: FontWeight.bold,
          shadows: [
            const Shadow(color: Colors.black45, blurRadius: 3),
          ],
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: radius * 0.65);

      // İsmi dilimin dış kenarına doğru hizala
      textPainter.paint(canvas, Offset(radius * 0.25, -textPainter.height / 2));
      canvas.restore();
    }

    // Dış Halka Çerçevesi
    final outerRing = Paint()
      ..color = Colors.white
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, outerRing);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) {
    return oldDelegate.students != students;
  }
}

/// Çarkın Tepesindeki İbre / Ok
class _TopPointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFBBF24)
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black26
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final path = Path()
      ..moveTo(size.width / 2, size.height) // Alt sivri uç
      ..lineTo(0, 0) // Sol üst
      ..lineTo(size.width, 0) // Sağ üst
      ..close();

    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// =============================================================================
// KONFETİ PARÇACIK MODELİ & ÇİZİCİSİ
// =============================================================================
class _ConfettiParticle {
  double x;
  double y;
  double vx;
  double vy;
  Color color;
  double size;
  double rotation = 0;
  double vRot = 0.1;

  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.size,
  });

  void update() {
    x += vx * 0.001;
    y += vy * 0.001;
    vy += 0.4; // Yerçekimi
    rotation += vRot;
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;

  _ConfettiPainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (var p in particles) {
      final px = p.x * size.width;
      final py = p.y * size.height;

      paint.color = p.color;
      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(p.rotation);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}
