import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// Premium saat seçici bileşeni — CustomDateRangePicker ile uyumlu tema
class CustomTimePicker {

  /// Saat seçici açar. [minTime] verilirse o saatten önceki saatler seçilemez.
  /// [sourceContext] verilirse masaüstünde butonun yanında açılır.
  static Future<TimeOfDay?> show(
    BuildContext context, {
    TimeOfDay? initialTime,
    TimeOfDay? minTime,
    BuildContext? sourceContext,
  }) async {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    if (isDesktop && sourceContext != null) {
      return _showDesktopPicker(context, sourceContext,
          initialTime: initialTime, minTime: minTime);
    } else if (isDesktop) {
      return _showDesktopDialog(context,
          initialTime: initialTime, minTime: minTime);
    } else {
      return _showMobileSheet(context,
          initialTime: initialTime, minTime: minTime);
    }
  }

  static Future<TimeOfDay?> _showDesktopPicker(
    BuildContext context,
    BuildContext sourceContext, {
    TimeOfDay? initialTime,
    TimeOfDay? minTime,
  }) async {
    Offset? position;
    Size? sourceSize;
    final RenderObject? renderObject = sourceContext.findRenderObject();
    if (renderObject is RenderBox) {
      position = renderObject.localToGlobal(Offset.zero);
      sourceSize = renderObject.size;
    }

    return showDialog<TimeOfDay>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        const width = 280.0;
        const height = 360.0;

        Widget dialogContent = Material(
          color: Colors.transparent,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: _TimePickerBody(
              initialTime: initialTime ?? TimeOfDay.now(),
              minTime: minTime,
            ),
          ),
        );

        Widget positionedContent;
        if (position != null && sourceSize != null) {
          final screenH = MediaQuery.of(ctx).size.height;
          final screenW = MediaQuery.of(ctx).size.width;

          double top = position.dy + sourceSize.height + 8;
          if (top + height > screenH) top = position.dy - height - 8;
          if (top < 8) top = 8;

          double left = position.dx;
          if (left + width > screenW) left = screenW - width - 8;
          if (left < 8) left = 8;

          positionedContent = Positioned(top: top, left: left, child: dialogContent);
        } else {
          positionedContent = Center(child: dialogContent);
        }

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                behavior: HitTestBehavior.opaque,
                child: Container(color: Colors.transparent),
              ),
            ),
            positionedContent,
          ],
        );
      },
    );
  }

  static Future<TimeOfDay?> _showDesktopDialog(
    BuildContext context, {
    TimeOfDay? initialTime,
    TimeOfDay? minTime,
  }) async {
    return showDialog<TimeOfDay>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 280,
              height: 360,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: _TimePickerBody(
                initialTime: initialTime ?? TimeOfDay.now(),
                minTime: minTime,
              ),
            ),
          ),
        );
      },
    );
  }

  static Future<TimeOfDay?> _showMobileSheet(
    BuildContext context, {
    TimeOfDay? initialTime,
    TimeOfDay? minTime,
  }) async {
    return showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: 400,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: _TimePickerBody(
            initialTime: initialTime ?? TimeOfDay.now(),
            minTime: minTime,
          ),
        );
      },
    );
  }
}

class _TimePickerBody extends StatefulWidget {
  final TimeOfDay initialTime;
  final TimeOfDay? minTime;

  const _TimePickerBody({required this.initialTime, this.minTime});

  @override
  State<_TimePickerBody> createState() => _TimePickerBodyState();
}

class _TimePickerBodyState extends State<_TimePickerBody> {
  late int _selectedHour;
  late int _selectedMinute;
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  bool _isEditingTime = false;
  late TextEditingController _hourTextController;
  late TextEditingController _minuteTextController;
  final FocusNode _hourFocus = FocusNode();
  final FocusNode _minuteFocus = FocusNode();

  static const _primaryBlue = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    _selectedHour = widget.initialTime.hour;
    _selectedMinute = widget.initialTime.minute;
    _hourController = FixedExtentScrollController(initialItem: _selectedHour);
    _minuteController = FixedExtentScrollController(initialItem: _selectedMinute);
    _hourTextController = TextEditingController(text: _selectedHour.toString().padLeft(2, '0'));
    _minuteTextController = TextEditingController(text: _selectedMinute.toString().padLeft(2, '0'));
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _hourTextController.dispose();
    _minuteTextController.dispose();
    _hourFocus.dispose();
    _minuteFocus.dispose();
    super.dispose();
  }

  bool _isHourDisabled(int hour) {
    if (widget.minTime == null) return false;
    return hour < widget.minTime!.hour;
  }

  bool _isMinuteDisabled(int minute) {
    if (widget.minTime == null) return false;
    if (_selectedHour < widget.minTime!.hour) return true;
    if (_selectedHour == widget.minTime!.hour) {
      return minute < widget.minTime!.minute;
    }
    return false;
  }

  void _clampSelection() {
    if (widget.minTime == null) return;
    if (_selectedHour < widget.minTime!.hour) {
      _selectedHour = widget.minTime!.hour;
      _hourController.jumpToItem(_selectedHour);
    }
    if (_selectedHour == widget.minTime!.hour &&
        _selectedMinute < widget.minTime!.minute) {
      _selectedMinute = widget.minTime!.minute;
      _minuteController.jumpToItem(_selectedMinute);
    }
  }

  void _applyManualTime() {
    final h = int.tryParse(_hourTextController.text);
    final m = int.tryParse(_minuteTextController.text);
    if (h != null && h >= 0 && h <= 23 && m != null && m >= 0 && m <= 59) {
      setState(() {
        _selectedHour = h;
        _selectedMinute = m;
        _clampSelection();
        _hourController.jumpToItem(_selectedHour);
        _minuteController.jumpToItem(_selectedMinute);
        _hourTextController.text = _selectedHour.toString().padLeft(2, '0');
        _minuteTextController.text = _selectedMinute.toString().padLeft(2, '0');
        _isEditingTime = false;
      });
    } else {
      // Reset to current values
      _hourTextController.text = _selectedHour.toString().padLeft(2, '0');
      _minuteTextController.text = _selectedMinute.toString().padLeft(2, '0');
      setState(() => _isEditingTime = false);
    }
  }

  void _syncTextToWheels() {
    _hourTextController.text = _selectedHour.toString().padLeft(2, '0');
    _minuteTextController.text = _selectedMinute.toString().padLeft(2, '0');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _primaryBlue.withValues(alpha: 0.05),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.access_time_rounded,
                    color: _primaryBlue, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'Saat Seçin',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Color(0xFF1A237E),
                ),
              ),
              const Spacer(),
              // Editable time display
              _isEditingTime
                  ? _buildEditableTimeField()
                  : InkWell(
                      onTap: () {
                        setState(() => _isEditingTime = true);
                        Future.delayed(const Duration(milliseconds: 100), () {
                          _hourFocus.requestFocus();
                          _hourTextController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: _hourTextController.text.length,
                          );
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _primaryBlue.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${_selectedHour.toString().padLeft(2, '0')}:${_selectedMinute.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: _primaryBlue,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.edit_rounded, size: 12, color: _primaryBlue.withValues(alpha: 0.5)),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        ),

        // Wheels
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                // Hour wheel
                Expanded(
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Text('Saat',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[500])),
                      const SizedBox(height: 4),
                      Expanded(
                        child: _buildWheel(
                          controller: _hourController,
                          itemCount: 24,
                          selectedValue: _selectedHour,
                          onChanged: (val) {
                            setState(() {
                              _selectedHour = val;
                              _clampSelection();
                              _syncTextToWheels();
                            });
                          },
                          isDisabled: _isHourDisabled,
                        ),
                      ),
                    ],
                  ),
                ),

                // Separator
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 24),
                      Text(
                        ':',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: _primaryBlue.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),

                // Minute wheel
                Expanded(
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Text('Dakika',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[500])),
                      const SizedBox(height: 4),
                      Expanded(
                        child: _buildWheel(
                          controller: _minuteController,
                          itemCount: 60,
                          selectedValue: _selectedMinute,
                          onChanged: (val) {
                            setState(() {
                              _selectedMinute = val;
                              _clampSelection();
                              _syncTextToWheels();
                            });
                          },
                          isDisabled: _isMinuteDisabled,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Bottom buttons
        Container(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  child: Text('İptal',
                      style: TextStyle(
                          color: Colors.grey[600], fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      TimeOfDay(hour: _selectedHour, minute: _selectedMinute),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Uygula',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditableTimeField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _primaryBlue, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36,
            child: TextField(
              controller: _hourTextController,
              focusNode: _hourFocus,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 2,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: _primaryBlue,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
              ),
              onChanged: (val) {
                if (val.length == 2) {
                  _minuteFocus.requestFocus();
                  _minuteTextController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _minuteTextController.text.length,
                  );
                }
              },
              onSubmitted: (_) => _applyManualTime(),
            ),
          ),
          const Text(':', style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: _primaryBlue,
          )),
          SizedBox(
            width: 36,
            child: TextField(
              controller: _minuteTextController,
              focusNode: _minuteFocus,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 2,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: _primaryBlue,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
              ),
              onSubmitted: (_) => _applyManualTime(),
            ),
          ),
          InkWell(
            onTap: _applyManualTime,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.check_rounded, size: 16, color: _primaryBlue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required int selectedValue,
    required ValueChanged<int> onChanged,
    required bool Function(int) isDisabled,
  }) {
    return Stack(
      children: [
        // Selection highlight
        Center(
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: _primaryBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _primaryBlue.withValues(alpha: 0.15)),
            ),
          ),
        ),
        // Wheel with mouse scroll support
        Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              final delta = event.scrollDelta.dy;
              final currentItem = controller.selectedItem;
              if (delta > 0 && currentItem < itemCount - 1) {
                controller.animateToItem(
                  currentItem + 1,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              } else if (delta < 0 && currentItem > 0) {
                controller.animateToItem(
                  currentItem - 1,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            }
          },
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: 40,
            perspective: 0.003,
            diameterRatio: 1.5,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: onChanged,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: itemCount,
              builder: (context, index) {
                final disabled = isDisabled(index);
                final isSelected = index == selectedValue;
                return Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: isSelected ? 20 : 16,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                      color: disabled
                          ? Colors.grey[300]
                          : isSelected
                              ? _primaryBlue
                              : Colors.grey[600],
                      fontFeatures: const [FontFeature.tabularFigures()],
                      decoration: disabled ? TextDecoration.lineThrough : null,
                      decorationColor: Colors.grey[300],
                    ),
                    child: Text(index.toString().padLeft(2, '0')),
                  ),
                );
              },
            ),
          ),
          ),
        ),
      ],
    );
  }
}
