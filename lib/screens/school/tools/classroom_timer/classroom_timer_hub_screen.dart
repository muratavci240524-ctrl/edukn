import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../models/school/classroom_timer_model.dart';
import '../../../../widgets/edukn_app_bar.dart';
import '../../../../utils/fullscreen_helper.dart';

class ClassroomTimerHubScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;

  const ClassroomTimerHubScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
  });

  @override
  State<ClassroomTimerHubScreen> createState() => _ClassroomTimerHubScreenState();
}

class _ClassroomTimerHubScreenState extends State<ClassroomTimerHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isFullscreen = false;

  // ===========================================================================
  // SEKME 1: HIZLI GERİ SAYIM (QUICK TIMER) STATE
  // ===========================================================================
  int _quickTotalSeconds = 2400; // Varsayılan 40 Dk (Ders)
  int _quickRemainingSeconds = 2400;
  bool _isQuickRunning = false;
  Timer? _quickTimer;

  // ===========================================================================
  // SEKME 2: KRONOMETRE (STOPWATCH) STATE
  // ===========================================================================
  int _stopwatchElapsedMs = 0;
  bool _isStopwatchRunning = false;
  Timer? _stopwatchTimer;
  final List<StopwatchLap> _laps = [];
  int _lastLapTotalMs = 0;

  // ===========================================================================
  // SEKME 3: SENARYOLU ÇALIŞMALAR (PRESETS / PLAYLISTS) STATE
  // ===========================================================================
  List<TimerTemplate> _templates = [];
  TimerTemplate? _selectedTemplate;
  int _currentStepIndex = 0;
  int _scenarioRemainingSeconds = 0;
  int _scenarioTotalSeconds = 0;
  bool _isScenarioRunning = false;
  Timer? _scenarioTimer;
  bool _autoAdvanceScenario = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _templates = List.from(TimerTemplate.defaultTemplates);
    _selectScenarioTemplate(_templates.first);
    _loadCustomTemplates();
  }

  Future<void> _loadCustomTemplates() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('school_timer_templates')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      if (snap.docs.isNotEmpty && mounted) {
        final customs = snap.docs
            .map((d) => TimerTemplate.fromMap(d.data(), d.id))
            .toList();

        setState(() {
          _templates = [...TimerTemplate.defaultTemplates, ...customs];
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    _quickTimer?.cancel();
    _stopwatchTimer?.cancel();
    _scenarioTimer?.cancel();
    super.dispose();
  }

  // ===========================================================================
  // 1. HIZLI GERİ SAYIM (QUICK TIMER) MANTIĞI
  // ===========================================================================
  void _setQuickDuration(int minutes, {int seconds = 0, int hours = 0}) {
    _quickTimer?.cancel();
    setState(() {
      _isQuickRunning = false;
      _quickTotalSeconds = (hours * 3600) + (minutes * 60) + seconds;
      _quickRemainingSeconds = _quickTotalSeconds;
    });
  }

  void _toggleQuickTimer() {
    if (_isQuickRunning) {
      _quickTimer?.cancel();
      setState(() => _isQuickRunning = false);
    } else {
      if (_quickRemainingSeconds <= 0) {
        setState(() => _quickRemainingSeconds = _quickTotalSeconds);
      }
      setState(() => _isQuickRunning = true);
      HapticFeedback.lightImpact();

      _quickTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_quickRemainingSeconds > 0) {
          setState(() => _quickRemainingSeconds--);
          if (_quickRemainingSeconds <= 5 && _quickRemainingSeconds > 0) {
            HapticFeedback.selectionClick();
          }
        } else {
          timer.cancel();
          setState(() => _isQuickRunning = false);
          _onTimerFinished('Süre Doldu!', 'Belirlenen süre başarıyla tamamlandı.');
        }
      });
    }
  }

  void _resetQuickTimer() {
    _quickTimer?.cancel();
    setState(() {
      _isQuickRunning = false;
      _quickRemainingSeconds = _quickTotalSeconds;
    });
  }

  void _addQuickSeconds(int extraSeconds) {
    setState(() {
      _quickRemainingSeconds += extraSeconds;
      _quickTotalSeconds += extraSeconds;
    });
  }

  void _showCustomDurationDialog() {
    int selectedHour = _quickTotalSeconds ~/ 3600;
    int selectedMinute = (_quickTotalSeconds % 3600) ~/ 60;
    int selectedSecond = _quickTotalSeconds % 60;

    final hourController = FixedExtentScrollController(initialItem: selectedHour);
    final minuteController = FixedExtentScrollController(initialItem: selectedMinute);
    final secondController = FixedExtentScrollController(initialItem: selectedSecond);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final formattedPreview =
                '${selectedHour.toString().padLeft(2, '0')}:${selectedMinute.toString().padLeft(2, '0')}:${selectedSecond.toString().padLeft(2, '0')}';

            final readableText = [
              if (selectedHour > 0) '$selectedHour Saat',
              if (selectedMinute > 0) '$selectedMinute Dakika',
              if (selectedSecond > 0) '$selectedSecond Saniye',
            ].join(' ');

            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.av_timer_rounded, color: Color(0xFF4F46E5), size: 22),
                  ),
                  const SizedBox(width: 10),
                  Text('Özel Süre Ayarla', style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 17, color: const Color(0xFF1E293B))),
                ],
              ),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Canlı Seçilen Süre Göstergesi
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            formattedPreview,
                            style: GoogleFonts.robotoMono(
                              fontWeight: FontWeight.w900,
                              fontSize: 32,
                              color: const Color(0xFF4F46E5),
                              letterSpacing: 2,
                            ),
                          ),
                          Text(
                            readableText.isEmpty ? 'Süre seçilmedi' : readableText,
                            style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Sütun Başlıkları
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildWheelHeader('SAAT'),
                          const SizedBox(width: 16),
                          _buildWheelHeader('DAKİKA'),
                          const SizedBox(width: 16),
                          _buildWheelHeader('SANİYE'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),

                    // 3 Kayan Tekerlek (Wheel Picker) Alanı
                    SizedBox(
                      height: 180,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Ortadaki Seçili Satır Vurgusu
                          Container(
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFC7D2FE), width: 1.2),
                            ),
                          ),

                          // 3 Sütunlu Tekerlekler
                          Row(
                            children: [
                              // 1. SAAT (0..23)
                              Expanded(
                                child: _buildWheelColumn(
                                  controller: hourController,
                                  itemCount: 24,
                                  selectedItem: selectedHour,
                                  onChanged: (val) => setDialogState(() => selectedHour = val),
                                ),
                              ),
                              Text(':', style: GoogleFonts.robotoMono(fontWeight: FontWeight.bold, fontSize: 24, color: const Color(0xFF4F46E5))),
                              // 2. DAKİKA (0..59)
                              Expanded(
                                child: _buildWheelColumn(
                                  controller: minuteController,
                                  itemCount: 60,
                                  selectedItem: selectedMinute,
                                  onChanged: (val) => setDialogState(() => selectedMinute = val),
                                ),
                              ),
                              Text(':', style: GoogleFonts.robotoMono(fontWeight: FontWeight.bold, fontSize: 24, color: const Color(0xFF4F46E5))),
                              // 3. SANİYE (0..59)
                              Expanded(
                                child: _buildWheelColumn(
                                  controller: secondController,
                                  itemCount: 60,
                                  selectedItem: selectedSecond,
                                  onChanged: (val) => setDialogState(() => selectedSecond = val),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Vazgeç', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    final totalSec = (selectedHour * 3600) + (selectedMinute * 60) + selectedSecond;
                    if (totalSec <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Lütfen 0 dan büyük bir süre seçiniz.')),
                      );
                      return;
                    }
                    Navigator.pop(ctx);
                    _setQuickDuration(selectedMinute, seconds: selectedSecond, hours: selectedHour);
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text('Süreyi Uygula', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildWheelHeader(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(
        fontWeight: FontWeight.w800,
        fontSize: 11,
        color: const Color(0xFF64748B),
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildWheelColumn({
    required FixedExtentScrollController controller,
    required int itemCount,
    required int selectedItem,
    required ValueChanged<int> onChanged,
  }) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 40,
      perspective: 0.003,
      diameterRatio: 1.4,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: (index) {
        HapticFeedback.selectionClick();
        onChanged(index);
      },
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: itemCount,
        builder: (context, index) {
          final isSelected = index == selectedItem;
          return Center(
            child: Text(
              index.toString().padLeft(2, '0'),
              style: GoogleFonts.robotoMono(
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
                fontSize: isSelected ? 22 : 16,
                color: isSelected ? const Color(0xFF4F46E5) : Colors.grey.shade400,
              ),
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // 2. KRONOMETRE (STOPWATCH) MANTIĞI
  // ===========================================================================
  void _toggleStopwatch() {
    if (_isStopwatchRunning) {
      _stopwatchTimer?.cancel();
      setState(() => _isStopwatchRunning = false);
    } else {
      setState(() => _isStopwatchRunning = true);
      HapticFeedback.lightImpact();

      _stopwatchTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
        setState(() {
          _stopwatchElapsedMs += 30;
        });
      });
    }
  }

  void _recordStopwatchLap() {
    if (_stopwatchElapsedMs == 0) return;
    HapticFeedback.selectionClick();

    final lapTime = _stopwatchElapsedMs - _lastLapTotalMs;
    _lastLapTotalMs = _stopwatchElapsedMs;

    setState(() {
      _laps.add(
        StopwatchLap(
          lapNumber: _laps.length + 1,
          lapTimeMs: lapTime,
          totalTimeMs: _stopwatchElapsedMs,
        ),
      );
    });
  }

  void _resetStopwatch() {
    _stopwatchTimer?.cancel();
    setState(() {
      _isStopwatchRunning = false;
      _stopwatchElapsedMs = 0;
      _lastLapTotalMs = 0;
      _laps.clear();
    });
  }

  // ===========================================================================
  // 3. SENARYOLU ÇALIŞMALAR (SCENARIOS) MANTIĞI
  // ===========================================================================
  void _selectScenarioTemplate(TimerTemplate template) {
    _scenarioTimer?.cancel();
    setState(() {
      _selectedTemplate = template;
      _currentStepIndex = 0;
      _isScenarioRunning = false;
      if (template.steps.isNotEmpty) {
        _scenarioTotalSeconds = template.steps.first.totalSeconds;
        _scenarioRemainingSeconds = _scenarioTotalSeconds;
      }
    });
  }

  void _toggleScenarioTimer() {
    final template = _selectedTemplate;
    if (template == null || template.steps.isEmpty) return;

    if (_isScenarioRunning) {
      _scenarioTimer?.cancel();
      setState(() => _isScenarioRunning = false);
    } else {
      if (_scenarioRemainingSeconds <= 0) {
        _scenarioTotalSeconds = template.steps[_currentStepIndex].totalSeconds;
        _scenarioRemainingSeconds = _scenarioTotalSeconds;
      }

      setState(() => _isScenarioRunning = true);
      HapticFeedback.lightImpact();

      _scenarioTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_scenarioRemainingSeconds > 0) {
          setState(() => _scenarioRemainingSeconds--);
          if (_scenarioRemainingSeconds <= 5 && _scenarioRemainingSeconds > 0) {
            HapticFeedback.selectionClick();
          }
        } else {
          timer.cancel();
          setState(() => _isScenarioRunning = false);

          final currentStep = template.steps[_currentStepIndex];

          // Sonraki aşamaya geç
          if (_currentStepIndex < template.steps.length - 1) {
            _onTimerFinished(
              'Aşama Tamamlandı: ${currentStep.title}',
              'Sıradaki Aşama: ${template.steps[_currentStepIndex + 1].title}',
            );

            if (_autoAdvanceScenario) {
              _goToScenarioStep(_currentStepIndex + 1, autoStart: true);
            }
          } else {
            _onTimerFinished(
              'Tüm Senaryo Tamamlandı! 🎉',
              '${template.title} oturumunun tüm aşamaları başarıyla bitti.',
            );
          }
        }
      });
    }
  }

  void _goToScenarioStep(int stepIndex, {bool autoStart = false}) {
    final template = _selectedTemplate;
    if (template == null || stepIndex < 0 || stepIndex >= template.steps.length) return;

    _scenarioTimer?.cancel();
    setState(() {
      _currentStepIndex = stepIndex;
      _scenarioTotalSeconds = template.steps[stepIndex].totalSeconds;
      _scenarioRemainingSeconds = _scenarioTotalSeconds;
      _isScenarioRunning = false;
    });

    if (autoStart) {
      _toggleScenarioTimer();
    }
  }

  void _resetScenario() {
    _scenarioTimer?.cancel();
    final template = _selectedTemplate;
    setState(() {
      _isScenarioRunning = false;
      _currentStepIndex = 0;
      if (template != null && template.steps.isNotEmpty) {
        _scenarioTotalSeconds = template.steps.first.totalSeconds;
        _scenarioRemainingSeconds = _scenarioTotalSeconds;
      }
    });
  }

  Future<void> _deleteCustomScenario(TimerTemplate template) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Senaryoyu Sil', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Text('"${template.title}" adlı özel senaryoyu silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      if (template.id.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('school_timer_templates')
            .doc(template.id)
            .delete();
      }

      setState(() {
        _templates.removeWhere((t) => t.id == template.id);
        _selectScenarioTemplate(_templates.first);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Özel senaryo silindi.'), backgroundColor: Color(0xFF10B981)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Silinirken hata oluştu: $e')),
        );
      }
    }
  }

  void _showCreateScenarioBottomSheet() {
    final titleController = TextEditingController();
    final descController = TextEditingController();

    // Tek aşama ile başla
    final List<Map<String, dynamic>> tempSteps = [
      {
        'title': '1. Aşama: Soru Çözümü',
        'minutes': 40,
        'instruction': 'Soruları dikkatlice okuyunuz ve çözmeye başlayınız.',
        'isBreak': false,
      },
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final totalMinutes = tempSteps.fold(0, (acc, s) => acc + ((s['minutes'] is int) ? s['minutes'] as int : (int.tryParse(s['minutes']?.toString() ?? '0') ?? 0)));

            return Center(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                  maxWidth: 480,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 20,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Sürükleme Tutamacı
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),

                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.playlist_add_rounded, color: Color(0xFF4F46E5), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Yeni Senaryolu Oturum Oluştur',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 16, color: const Color(0xFF1E293B)),
                                ),
                                Text(
                                  'Aşamaları ve akıllı tahta yönergelerini belirleyin',
                                  style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 20),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),

                    // İçerik (Doğal Yükseklik & Aşağı Kaydırılabilir)
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).viewInsets.bottom + 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1. Senaryo Genel Bilgileri (Temiz Kart)
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('SENARYO BAŞLIĞI', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 10.5, color: const Color(0xFF6366F1), letterSpacing: 0.8)),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: TextField(
                                      controller: titleController,
                                      style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: InputBorder.none,
                                        hintText: 'Örn: Türkçe Paragraf Soru Kampı',
                                        hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text('AÇIKLAMA (OPSİYONEL)', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 10.5, color: const Color(0xFF64748B), letterSpacing: 0.8)),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: TextField(
                                      controller: descController,
                                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: InputBorder.none,
                                        hintText: 'Örn: 40 dakikalık odaklanmış deneme oturumu',
                                        hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 2. Aşamalar Başlığı ve Ekle Butonu
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Aşamalar',
                                      style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13.5, color: const Color(0xFF1E293B)),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEEF2FF),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${tempSteps.length} Aşama • $totalMinutes Dk',
                                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 11, color: const Color(0xFF4F46E5)),
                                      ),
                                    ),
                                  ],
                                ),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    backgroundColor: const Color(0xFFEEF2FF),
                                    foregroundColor: const Color(0xFF4F46E5),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () {
                                    setSheetState(() {
                                      tempSteps.add({
                                        'title': '${tempSteps.length + 1}. Aşama: Yeni Aşama',
                                        'minutes': 15,
                                        'instruction': 'Öğrenciler için yönerge metnini yazınız.',
                                        'isBreak': false,
                                      });
                                    });
                                  },
                                  icon: const Icon(Icons.add_rounded, size: 16),
                                  label: const Text('Aşama Ekle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // 3. Aşamalar Kart Listesi (Temiz, Ferah ve Yalın Tasarım)
                            ...List.generate(tempSteps.length, (sIdx) {
                              final stepMap = tempSteps[sIdx];
                              final isBreak = stepMap['isBreak'] == true;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isBreak ? const Color(0xFFF0FDF4) : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isBreak ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
                                    width: 1.2,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // Aşama Başlığı ve Süre Satırı
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 11,
                                          backgroundColor: isBreak ? const Color(0xFF059669) : const Color(0xFF4F46E5),
                                          child: Text('${sIdx + 1}', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF8FAFC),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0xFFE2E8F0)),
                                            ),
                                            child: TextFormField(
                                              initialValue: stepMap['title'],
                                              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                border: InputBorder.none,
                                                hintText: 'Aşama Başlığı',
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                              onChanged: (val) => stepMap['title'] = val.trim(),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          width: 76,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: const Color(0xFFE2E8F0)),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: TextFormField(
                                                  initialValue: stepMap['minutes'].toString(),
                                                  keyboardType: TextInputType.number,
                                                  textAlign: TextAlign.center,
                                                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                                                  decoration: const InputDecoration(
                                                    isDense: true,
                                                    border: InputBorder.none,
                                                    contentPadding: EdgeInsets.zero,
                                                  ),
                                                  onChanged: (val) => stepMap['minutes'] = int.tryParse(val) ?? 10,
                                                ),
                                              ),
                                              Text('Dk', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                        if (tempSteps.length > 1)
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                                            tooltip: 'Aşamayı Sil',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                            onPressed: () => setSheetState(() => tempSteps.removeAt(sIdx)),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),

                                    // Yönerge Metni
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: TextFormField(
                                        initialValue: stepMap['instruction'],
                                        style: GoogleFonts.inter(fontSize: 12.5),
                                        maxLines: 2,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          border: InputBorder.none,
                                          hintText: '📢 Öğrenci Yönergesi (Tahtada yansıtılacak metin...)',
                                          hintStyle: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        onChanged: (val) => stepMap['instruction'] = val.trim(),
                                      ),
                                    ),
                                    const SizedBox(height: 4),

                                    // Mola Switch'i
                                    InkWell(
                                      onTap: () => setSheetState(() => stepMap['isBreak'] = !isBreak),
                                      borderRadius: BorderRadius.circular(6),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 3),
                                        child: Row(
                                          children: [
                                            Icon(
                                              isBreak ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                              color: isBreak ? const Color(0xFF059669) : const Color(0xFF94A3B8),
                                              size: 18,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Bu bir Dinlenme / Mola Aşamasıdır (Yeşil Tema)',
                                              style: GoogleFonts.inter(
                                                fontSize: 11.5,
                                                fontWeight: isBreak ? FontWeight.bold : FontWeight.normal,
                                                color: isBreak ? const Color(0xFF065F46) : const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),

                    // Alt Sabit Butonlar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                side: const BorderSide(color: Color(0xFFCBD5E1)),
                              ),
                              onPressed: () => Navigator.pop(ctx),
                              child: Text('Vazgeç', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF64748B))),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4F46E5),
                                foregroundColor: Colors.white,
                                elevation: 2,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () async {
                                final title = titleController.text.trim();
                                if (title.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Lütfen senaryo başlığı giriniz!')),
                                  );
                                  return;
                                }

                                final steps = tempSteps.map((m) {
                                  return TimerStep(
                                    id: 'step_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}',
                                    title: m['title']?.toString() ?? 'Aşama',
                                    durationMinutes: (m['minutes'] is int) ? m['minutes'] as int : (int.tryParse(m['minutes']?.toString() ?? '10') ?? 10),
                                    instructionText: m['instruction']?.toString() ?? '',
                                    isBreak: m['isBreak'] == true,
                                  );
                                }).toList();

                                final newTemplate = TimerTemplate(
                                  id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                                  title: title,
                                  description: descController.text.trim(),
                                  icon: Icons.playlist_add_check_rounded,
                                  color: const Color(0xFF4F46E5),
                                  steps: steps,
                                  category: 'custom',
                                  isCustom: true,
                                  institutionId: widget.institutionId,
                                );

                                final messenger = ScaffoldMessenger.of(context);
                                try {
                                  final docRef = await FirebaseFirestore.instance
                                      .collection('school_timer_templates')
                                      .add(newTemplate.toMap());

                                  final savedTemplate = TimerTemplate(
                                    id: docRef.id,
                                    title: newTemplate.title,
                                    description: newTemplate.description,
                                    icon: newTemplate.icon,
                                    color: newTemplate.color,
                                    steps: newTemplate.steps,
                                    category: newTemplate.category,
                                    isCustom: true,
                                    institutionId: newTemplate.institutionId,
                                  );

                                  setState(() {
                                    _templates.add(savedTemplate);
                                    _selectScenarioTemplate(savedTemplate);
                                  });

                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
                                  }

                                  messenger.showSnackBar(
                                    const SnackBar(content: Text('✅ Özel senaryo başarıyla oluşturuldu ve kaydedildi!'), backgroundColor: Color(0xFF10B981)),
                                  );
                                } catch (e) {
                                  messenger.showSnackBar(
                                    SnackBar(content: Text('Kayıt hatası: $e')),
                                  );
                                }
                              },
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: Text('Kaydet ve Başlat', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _onTimerFinished(String title, String message) {
    HapticFeedback.heavyImpact();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: const Icon(Icons.notifications_active_rounded, color: Color(0xFFD97706), size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 20, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13.5, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: Text('Tamam', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleFullscreen() {
    final nextState = !_isFullscreen;

    // Web'de F11 gibi gerçek tarayıcı tam ekranını tetikle
    toggleBrowserFullscreen(nextState);

    // Mobil platformlar için SystemChrome
    if (!kIsWeb) {
      try {
        if (nextState) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        } else {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
      } catch (_) {}
    }

    setState(() {
      _isFullscreen = nextState;
    });
  }

  // ===========================================================================
  // ANA ARAYÜZ (BUILD)
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Akıllı tahta için modern koyu tema
      appBar: EduknAppBar(
        title: _isFullscreen ? 'Zaman Yönetim Merkezi (Tam Ekran)' : 'Zaman Yönetim Merkezi',
        subtitle: '${widget.schoolTypeName} • Geri Sayım, Kronometre & Senaryolar',
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        subtitleColor: const Color(0xFF94A3B8),
        backButtonColor: const Color(0xFF818CF8),
        borderColor: const Color(0xFF334155),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            decoration: BoxDecoration(
              color: _isFullscreen ? const Color(0xFF4F46E5) : const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _isFullscreen ? const Color(0xFF6366F1) : const Color(0xFF334155),
                width: 1.2,
              ),
            ),
            child: IconButton(
              tooltip: _isFullscreen ? 'Tam Ekrandan Çık (F11)' : 'Tarayıcı Tam Ekranı (F11)',
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
              icon: Icon(
                _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                color: _isFullscreen ? Colors.white : const Color(0xFF818CF8),
                size: 22,
              ),
              onPressed: _toggleFullscreen,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTabBar(isMobile),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildQuickTimerTab(isMobile),
                _buildStopwatchTab(isMobile),
                _buildScenarioTab(isMobile),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isMobile) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(bottom: BorderSide(color: Color(0xFF334155))),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: isMobile,
        tabAlignment: isMobile ? TabAlignment.start : TabAlignment.fill,
        labelColor: const Color(0xFF818CF8),
        unselectedLabelColor: const Color(0xFF94A3B8),
        indicatorColor: const Color(0xFF818CF8),
        indicatorWeight: 3,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
        tabs: const [
          Tab(icon: Icon(Icons.timer_rounded, size: 18), text: 'Hızlı Geri Sayım'),
          Tab(icon: Icon(Icons.timer_outlined, size: 18), text: 'Kronometre & Tur'),
          Tab(icon: Icon(Icons.playlist_play_rounded, size: 18), text: 'Senaryolu Oturumlar'),
        ],
      ),
    );
  }

  // ===========================================================================
  // SEKME 1: HIZLI GERİ SAYIM (QUICK TIMER) ARAYÜZÜ
  // ===========================================================================
  Widget _buildQuickTimerTab(bool isMobile) {
    final progress = _quickTotalSeconds > 0 ? (_quickRemainingSeconds / _quickTotalSeconds) : 0.0;
    final isWarning = _quickRemainingSeconds <= 60 && _quickRemainingSeconds > 0;
    final isCritical = _quickRemainingSeconds <= 15 && _quickRemainingSeconds > 0;

    final hours = _quickRemainingSeconds ~/ 3600;
    final minutes = ((_quickRemainingSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (_quickRemainingSeconds % 60).toString().padLeft(2, '0');
    final timeDisplay = hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$minutes:$seconds'
        : '$minutes:$seconds';

    final ringColor = isCritical
        ? const Color(0xFFEF4444)
        : (isWarning ? const Color(0xFFF59E0B) : const Color(0xFF6366F1));

    final circleSize = isMobile ? 240.0 : 280.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          // 1. Hızlı Süre Seçim Butonları
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildQuickPresetButton(1, '1 Dk'),
              _buildQuickPresetButton(3, '3 Dk'),
              _buildQuickPresetButton(5, '5 Dk'),
              _buildQuickPresetButton(10, '10 Dk'),
              _buildQuickPresetButton(15, '15 Dk'),
              _buildQuickPresetButton(20, '20 Dk'),
              _buildQuickPresetButton(40, '40 Dk (Ders)'),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF818CF8),
                  side: const BorderSide(color: Color(0xFF4F46E5)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _showCustomDurationDialog,
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: const Text('Özel Süre'),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // 2. Büyük Dairesel & Dijital Sayaç
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: circleSize,
                height: circleSize,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: isMobile ? 12 : 14,
                  backgroundColor: const Color(0xFF334155),
                  valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeDisplay,
                    style: GoogleFonts.robotoMono(
                      fontWeight: FontWeight.w900,
                      fontSize: hours > 0 ? (isMobile ? 38 : 46) : (isMobile ? 52 : 64),
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                  if (isWarning)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: ringColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: ringColor),
                      ),
                      child: Text(
                        isCritical ? '⚠️ SON 15 SANİYE!' : '⏳ SON 1 DAKİKA',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: ringColor),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 28),

          // 3. Kontrol Butonları (Responsive Wrap ile Taşmasız)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildSecondaryActionButton(Icons.replay_rounded, 'Sıfırla', _resetQuickTimer),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isQuickRunning ? const Color(0xFFEF4444) : const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  elevation: 6,
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 36, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  shadowColor: (_isQuickRunning ? const Color(0xFFEF4444) : const Color(0xFF4F46E5)).withValues(alpha: 0.4),
                ),
                onPressed: _toggleQuickTimer,
                icon: Icon(_isQuickRunning ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 28),
                label: Text(
                  _isQuickRunning ? 'DURAKLAT' : 'BAŞLAT',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.1),
                ),
              ),
              _buildSecondaryActionButton(Icons.add_rounded, '+1 Dk', () => _addQuickSeconds(60)),
              _buildSecondaryActionButton(Icons.add_rounded, '+5 Dk', () => _addQuickSeconds(300)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickPresetButton(int minutes, String label) {
    final isSelected = _quickTotalSeconds == minutes * 60;

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF1E293B),
        foregroundColor: isSelected ? Colors.white : const Color(0xFFCBD5E1),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF334155)),
        ),
      ),
      onPressed: () => _setQuickDuration(minutes),
      child: Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12.5)),
    );
  }

  Widget _buildSecondaryActionButton(IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFCBD5E1),
        backgroundColor: const Color(0xFF1E293B),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
      ),
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12.5)),
        ],
      ),
    );
  }

  // ===========================================================================
  // SEKME 2: KRONOMETRE & TUR (STOPWATCH & LAPS) ARAYÜZÜ
  // ===========================================================================
  Widget _buildStopwatchTab(bool isMobile) {
    final formattedTime = StopwatchLap.formatStopwatchTime(_stopwatchElapsedMs);

    return Column(
      children: [
        const SizedBox(height: 24),
        // Büyük Dijital Kronometre
        Container(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 18 : 24, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Text(
            formattedTime,
            style: GoogleFonts.robotoMono(
              fontWeight: FontWeight.w900,
              fontSize: isMobile ? 44 : 58,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Kontrol Butonları (Responsive Wrap)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF334155),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _resetStopwatch,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: Text('Sıfırla', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isStopwatchRunning ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _toggleStopwatch,
              icon: Icon(_isStopwatchRunning ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 24),
              label: Text(
                _isStopwatchRunning ? 'DURAKLAT' : 'BAŞLAT',
                style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _isStopwatchRunning ? _recordStopwatchLap : null,
              icon: const Icon(Icons.flag_rounded, size: 20),
              label: Text('Tur (Lap)', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Tur (Lap) Listesi (1. Basılan En Üstte, Sırayla Aşağıya Doğru)
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: _laps.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.timer_outlined, size: 40, color: Color(0xFF64748B)),
                        const SizedBox(height: 8),
                        Text('Henüz tur kaydedilmedi', style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13)),
                        Text('Öğrenci sürelerini kaydetmek için "Tur (Lap)" butonuna basın', style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 11.5)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _laps.length,
                    separatorBuilder: (_, __) => const Divider(color: Color(0xFF334155), height: 1),
                    itemBuilder: (context, idx) {
                      final lap = _laps[idx];

                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: const Color(0xFF334155),
                          child: Text('#${lap.lapNumber}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                        title: Text(
                          'Tur Süresi: ${lap.formattedLapTime}',
                          style: GoogleFonts.robotoMono(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13.5),
                        ),
                        trailing: Text(
                          'Toplam: ${lap.formattedTotalTime}',
                          style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12.5),
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ===========================================================================
  // SEKME 3: SENARYOLU OTURUMLAR (SCENARIOS) ARAYÜZÜ
  // ===========================================================================
  Widget _buildScenarioTab(bool isMobile) {
    final template = _selectedTemplate;

    if (template == null || template.steps.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.playlist_remove_rounded, size: 54, color: Color(0xFF64748B)),
            const SizedBox(height: 12),
            Text('Seçili senaryo şablonu bulunamadı', style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 15)),
          ],
        ),
      );
    }

    final currentStep = template.steps[_currentStepIndex];
    final progress = _scenarioTotalSeconds > 0 ? (_scenarioRemainingSeconds / _scenarioTotalSeconds) : 0.0;

    final minutes = (_scenarioRemainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_scenarioRemainingSeconds % 60).toString().padLeft(2, '0');

    final circleSize = isMobile ? 180.0 : 220.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Şablon Seçici Bar (Premium Dropdown & En Altta Yeni Senaryo Ekle)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF334155), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: template.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(template.icon, color: template.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      dropdownColor: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(16),
                      value: template.id,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF94A3B8)),
                      items: [
                        ..._templates.map((t) {
                          return DropdownMenuItem<String>(
                            value: t.id,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Icon(t.icon, color: t.color, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          t.title,
                                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.white),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '${t.steps.length} Aşama • Toplam ${t.totalDurationMinutes} Dk',
                                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (t.isCustom)
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4F46E5),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text('Özel', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),
                        // En Altta Yeni Senaryo Ekle Öğesi
                        DropdownMenuItem<String>(
                          value: '__create_new__',
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: const BoxDecoration(
                              border: Border(top: BorderSide(color: Color(0xFF334155))),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4F46E5),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '+ Yeni Senaryolu Oturum Oluştur',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 13, color: const Color(0xFF818CF8)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val == null) return;
                        if (val == '__create_new__') {
                          _showCreateScenarioBottomSheet();
                          return;
                        }
                        final match = _templates.where((t) => t.id == val).toList();
                        if (match.isNotEmpty) _selectScenarioTemplate(match.first);
                      },
                    ),
                  ),
                ),
                if (template.isCustom)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                    tooltip: 'Bu Özel Senaryoyu Sil',
                    onPressed: () => _deleteCustomScenario(template),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Aşamalar İlerleme Çubuğu (Step Indicator)
          Row(
            children: List.generate(template.steps.length, (idx) {
              final isCurrent = idx == _currentStepIndex;
              final isCompleted = idx < _currentStepIndex;

              return Expanded(
                child: InkWell(
                  onTap: () => _goToScenarioStep(idx),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? const Color(0xFF4F46E5)
                          : (isCompleted ? const Color(0xFF059669) : const Color(0xFF334155)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${idx + 1}. Aşama',
                        style: GoogleFonts.inter(
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                          fontSize: 11,
                          color: isCurrent || isCompleted ? Colors.white : Colors.white60,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),

          // 3. Aktif Aşama & Büyük Sayaç Kartı
          Container(
            padding: EdgeInsets.all(isMobile ? 18 : 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: currentStep.isBreak
                    ? [const Color(0xFF065F46), const Color(0xFF047857)]
                    : [const Color(0xFF1E293B), const Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: currentStep.isBreak ? const Color(0xFF10B981) : const Color(0xFF4F46E5), width: 1.5),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(currentStep.isBreak ? Icons.coffee_rounded : Icons.play_circle_fill_rounded, color: Colors.white70, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        currentStep.title,
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: circleSize,
                      height: circleSize,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 10,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          currentStep.isBreak ? const Color(0xFF34D399) : const Color(0xFF818CF8),
                        ),
                      ),
                    ),
                    Text(
                      '$minutes:$seconds',
                      style: GoogleFonts.robotoMono(
                        fontWeight: FontWeight.w900,
                        fontSize: isMobile ? 42 : 52,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ÖĞRENCİ YÖNERGE METNİ (BÜYÜK VE OKUNAKLI)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '📢 ÖĞRENCİ YÖNERGESİ',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 11, color: const Color(0xFFFBBF24), letterSpacing: 1),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentStep.instructionText,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4. Kontrol Butonları & Otomatik Geçiş Switch'i (Responsive Wrap)
          Wrap(
            spacing: 6,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_rounded, color: Colors.white70, size: 24),
                tooltip: 'Senaryoyu Baştan Başlat',
                onPressed: _resetScenario,
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 26),
                tooltip: 'Önceki Aşama',
                onPressed: _currentStepIndex > 0 ? () => _goToScenarioStep(_currentStepIndex - 1) : null,
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isScenarioRunning ? const Color(0xFFEF4444) : const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 18 : 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _toggleScenarioTimer,
                icon: Icon(_isScenarioRunning ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 22),
                label: Text(
                  _isScenarioRunning ? 'DURAKLAT' : 'AŞAMAYI BAŞLAT',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 13.5),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 26),
                tooltip: 'Sonraki Aşama',
                onPressed: _currentStepIndex < template.steps.length - 1
                    ? () => _goToScenarioStep(_currentStepIndex + 1)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Switch(
                value: _autoAdvanceScenario,
                onChanged: (val) => setState(() => _autoAdvanceScenario = val),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Süre bitince otomatik sonraki aşamaya geç',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFCBD5E1)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
