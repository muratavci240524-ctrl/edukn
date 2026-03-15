import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/survey_model.dart';
import '../../../services/survey_service.dart';

class BurdonTestExecutionScreen extends StatefulWidget {
  final Survey survey;
  final String? surveyId;

  const BurdonTestExecutionScreen({
    Key? key,
    required this.survey,
    this.surveyId,
  }) : super(key: key);

  @override
  State<BurdonTestExecutionScreen> createState() =>
      _BurdonTestExecutionScreenState();
}

class _BurdonTestExecutionScreenState extends State<BurdonTestExecutionScreen> {
  final SurveyService _surveyService = SurveyService();
  final Random _random = Random();

  // Configuration
  static const int totalChars =
      840; // Total characters to maintain test consistency
  static const List<String> targets = ['a', 'b', 'd', 'g'];
  static const List<String> distractors = [
    'c',
    'e',
    'f',
    'h',
    'i',
    'j',
    'k',
    'l',
    'm',
    'n',
    'o',
    'p',
    'r',
    's',
    't',
    'u',
    'v',
    'y',
    'z',
  ];

  // State
  late List<String> _flatGrid;
  late List<bool> _flatSelections;
  int _timeLeft = 300; // 5 minutes in seconds
  Timer? _timer;
  bool _isSubmitting = false;
  bool _isPreparing = true;

  @override
  void initState() {
    super.initState();
    _prepareTest();
  }

  Future<void> _prepareTest() async {
    // Show preparing animation for at least 1.5 seconds for UX
    await Future.delayed(const Duration(milliseconds: 1500));

    _generateFlatGrid();
    _startTimer();

    if (mounted) {
      setState(() {
        _isPreparing = false;
      });
    }
  }

  void _generateFlatGrid() {
    _flatGrid = List.generate(totalChars, (i) {
      if (_random.nextDouble() < 0.2) {
        return targets[_random.nextInt(targets.length)];
      } else {
        return distractors[_random.nextInt(distractors.length)];
      }
    });
    _flatSelections = List.generate(totalChars, (i) => false);
  }

  void _startTimer() {
    // Timer is now handled by TimerDisplay widget to avoid full screen rebuilds
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _submitTest() async {
    if (widget.surveyId == null) {
      _showPreviewEndDialog();
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final Map<String, dynamic> answers = {
        'grid_flat': _flatGrid,
        'selections_flat': _flatSelections,
        'charsPerRow': 40, // Standard width for report processing
        'timestamp': DateTime.now().toIso8601String(),
        'timeLeft': _timeLeft,
      };

      await _surveyService.submitResponse(widget.surveyId!, answers);

      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showPreviewEndDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Önizleme Tamamlandı'),
        content: const Text('Bu bir önizlemedir, veriler kaydedilmez.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Test Tamamlandı'),
        content: const Text('Yanıtlarınız başarıyla kaydedildi.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isPreparing) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(strokeWidth: 3),
              const SizedBox(height: 24),
              Text(
                'Test hazırlanıyor...',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Lütfen bekleyiniz, bu işlem birkaç saniye sürebilir.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          widget.survey.title,
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          Center(
            child: TimerDisplay(
              initialSeconds: _timeLeft,
              onFinished: _submitTest,
              onTick: (seconds) => _timeLeft = seconds,
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Dynamic calculation based on width
          // 22px char + 2px spacing + 2px border ≈ 26px per char
          // Plus row number (30px) and padding (32px)
          final double availableWidth = constraints.maxWidth - 62;
          final int charsPerRow = (availableWidth / 26).floor().clamp(10, 40);
          final int rows = (totalChars / charsPerRow).ceil();

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.amber.shade50,
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline, color: Colors.amber),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Lütfen "a, b, d, g" harflerini bulup üzerlerine dokunarak işaretleyiniz.',
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  itemCount: rows,
                  itemBuilder: (context, rIndex) {
                    return _buildRow(rIndex, charsPerRow);
                  },
                ),
              ),
              _buildFooter(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRow(int rowIndex, int charsPerRow) {
    int start = rowIndex * charsPerRow;
    int end = (rowIndex + 1) * charsPerRow;
    if (start >= totalChars) return const SizedBox();
    if (end > totalChars) end = totalChars;

    return RepaintBoundary(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  '${rowIndex + 1}.',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ),
              Wrap(
                spacing: 2,
                children: List.generate(end - start, (i) {
                  final globalIndex = start + i;
                  return BurdonCharacterCell(
                    char: _flatGrid[globalIndex],
                    isSelected: _flatSelections[globalIndex],
                    onChanged: (val) {
                      _flatSelections[globalIndex] = val;
                      // No need to call setState() here, cell updates itself
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submitTest,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSubmitting
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text(
                    'Testi Bitir ve Gönder',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ),
    );
  }
}

class BurdonCharacterCell extends StatefulWidget {
  final String char;
  final bool isSelected;
  final ValueChanged<bool> onChanged;

  const BurdonCharacterCell({
    Key? key,
    required this.char,
    required this.isSelected,
    required this.onChanged,
  }) : super(key: key);

  @override
  State<BurdonCharacterCell> createState() => _BurdonCharacterCellState();
}

class _BurdonCharacterCellState extends State<BurdonCharacterCell> {
  late bool _isSelected;

  @override
  void initState() {
    super.initState();
    _isSelected = widget.isSelected;
  }

  @override
  void didUpdateWidget(BurdonCharacterCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSelected != widget.isSelected) {
      _isSelected = widget.isSelected;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        setState(() {
          _isSelected = !_isSelected;
        });
        widget.onChanged(_isSelected);
      },
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _isSelected ? Colors.indigo : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _isSelected ? Colors.indigo : Colors.grey.shade200,
          ),
        ),
        child: Text(
          widget.char,
          style: TextStyle(
            color: _isSelected ? Colors.white : Colors.black87,
            fontWeight: _isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class TimerDisplay extends StatefulWidget {
  final int initialSeconds;
  final VoidCallback onFinished;
  final ValueChanged<int> onTick;

  const TimerDisplay({
    Key? key,
    required this.initialSeconds,
    required this.onFinished,
    required this.onTick,
  }) : super(key: key);

  @override
  State<TimerDisplay> createState() => _TimerDisplayState();
}

class _TimerDisplayState extends State<TimerDisplay> {
  late int _timeLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timeLeft = widget.initialSeconds;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft > 0) {
        if (mounted) {
          setState(() => _timeLeft--);
          widget.onTick(_timeLeft);
        }
      } else {
        _timer?.cancel();
        widget.onFinished();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: _timeLeft < 60 ? Colors.red.shade50 : Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _timeLeft < 60 ? Colors.red : Colors.indigo),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer,
            size: 18,
            color: _timeLeft < 60 ? Colors.red : Colors.indigo,
          ),
          const SizedBox(width: 6),
          Text(
            _formatTime(_timeLeft),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _timeLeft < 60 ? Colors.red : Colors.indigo,
            ),
          ),
        ],
      ),
    );
  }
}
