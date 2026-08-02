import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';

class CustomDateRangePicker {
  static Future<DateTimeRange?> showRange(
    BuildContext context, {
    BuildContext? sourceContext,
    DateTimeRange? initialRange,
    AlignmentGeometry desktopAlignment = Alignment.topRight,
    EdgeInsetsGeometry desktopPadding = const EdgeInsets.only(top: 130, right: 24),
  }) async {
    return await _show<DateTimeRange>(
      context: context, 
      sourceContext: sourceContext,
      isRange: true, 
      initialRange: initialRange,
      desktopAlignment: desktopAlignment,
      desktopPadding: desktopPadding,
    );
  }

  static Future<DateTime?> showSingle(
    BuildContext context, {
    BuildContext? sourceContext,
    DateTime? initialDate,
    AlignmentGeometry desktopAlignment = Alignment.center,
    EdgeInsetsGeometry desktopPadding = EdgeInsets.zero,
  }) async {
    return await _show<DateTime>(
      context: context, 
      sourceContext: sourceContext,
      isRange: false, 
      initialDate: initialDate,
      desktopAlignment: desktopAlignment,
      desktopPadding: desktopPadding,
    );
  }

  static Future<T?> _show<T>(
    {required BuildContext context,
    BuildContext? sourceContext,
    required bool isRange,
    DateTimeRange? initialRange,
    DateTime? initialDate,
    required AlignmentGeometry desktopAlignment,
    required EdgeInsetsGeometry desktopPadding}
  ) async {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    
    Offset? position;
    Size? sourceSize;
    if (isDesktop && sourceContext != null) {
      final RenderObject? renderObject = sourceContext.findRenderObject();
      if (renderObject is RenderBox) {
        position = renderObject.localToGlobal(Offset.zero);
        sourceSize = renderObject.size;
      }
    }
    
    if (isDesktop) {
      return await showDialog<T>(
        context: context,
        barrierColor: Colors.transparent, // Making it look like a dropdown
        builder: (context) {
          final width = isRange ? 640.0 : 340.0;
          final height = 440.0;
          
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
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 32,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: _PickerBody<T>(initialRange: initialRange, initialDate: initialDate, isDesktop: true, isRange: isRange),
            ),
          );

          Widget positionedContent;
          if (position != null && sourceSize != null) {
            final screenHeight = MediaQuery.of(context).size.height;
            final screenWidth = MediaQuery.of(context).size.width;
            
            double topPos = position.dy + sourceSize.height + 8;
            if (topPos + height > screenHeight) {
              topPos = position.dy - height - 8;
            }
            if (topPos < 8.0) topPos = 8.0;
            
            double leftPos = position.dx;
            if (leftPos + width > screenWidth) {
              leftPos = screenWidth - width - 8;
            }
            if (leftPos < 8.0) leftPos = 8.0;

            positionedContent = Positioned(
              top: topPos,
              left: leftPos,
              child: dialogContent,
            );
          } else {
            positionedContent = Align(
              alignment: desktopAlignment,
              child: Padding(
                padding: desktopPadding,
                child: dialogContent,
              ),
            );
          }

          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  behavior: HitTestBehavior.opaque,
                  child: Container(color: Colors.transparent),
                ),
              ),
              positionedContent,
            ],
          );
        },
      );
    } else {
      // MOBILE BOTTOM SHEET
      return await showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: _PickerBody<T>(initialRange: initialRange, initialDate: initialDate, isDesktop: false, isRange: isRange),
          );
        },
      );
    }
  }

  // Deprecated support for backward compatibility with previous refactor
  static Future<DateTimeRange?> show(
    BuildContext context, {
    DateTimeRange? initialRange,
    AlignmentGeometry desktopAlignment = Alignment.topRight,
    EdgeInsetsGeometry desktopPadding = const EdgeInsets.only(top: 130, right: 24),
  }) async {
    return showRange(context, initialRange: initialRange, desktopAlignment: desktopAlignment, desktopPadding: desktopPadding);
  }
}

class _PickerBody<T> extends StatefulWidget {
  final DateTimeRange? initialRange;
  final DateTime? initialDate;
  final bool isDesktop;
  final bool isRange;

  const _PickerBody({Key? key, this.initialRange, this.initialDate, required this.isDesktop, required this.isRange}) : super(key: key);

  @override
  State<_PickerBody<T>> createState() => _PickerBodyState<T>();
}

class _PickerBodyState<T> extends State<_PickerBody<T>> {
  late DateRangePickerController _controller;
  late DateTime _currentDisplayDate;
  DateRangePickerView _currentView = DateRangePickerView.month;

  @override
  void initState() {
    super.initState();
    _controller = DateRangePickerController();
    
    DateTime refDate = DateTime.now();
    if (widget.isRange && widget.initialRange != null) {
      refDate = widget.initialRange!.start;
    } else if (!widget.isRange && widget.initialDate != null) {
      refDate = widget.initialDate!;
    }
    
    _currentDisplayDate = DateTime(refDate.year, refDate.month, 1);
  }

  Widget _buildNavButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(icon, size: 22, color: Colors.grey.shade700),
      ),
    );
  }

  String _getHeaderText(DateTime date) {
    if (_currentView == DateRangePickerView.year) {
      return date.year.toString();
    } else if (_currentView == DateRangePickerView.decade) {
      int startYear = date.year - (date.year % 10);
      return '$startYear - ${startYear + 9}';
    } else {
      return DateFormat.yMMMM('tr').format(date);
    }
  }

  Widget _buildClickableHeader(DateTime date) {
    return InkWell(
      onTap: () {
        if (_currentView == DateRangePickerView.month) {
          _controller.view = DateRangePickerView.year;
          setState(() => _currentView = DateRangePickerView.year);
        } else if (_currentView == DateRangePickerView.year) {
          _controller.view = DateRangePickerView.decade;
          setState(() => _currentView = DateRangePickerView.decade);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        child: Text(
          _getHeaderText(date),
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // DRAG HANDLE FOR MOBILE
        if (!widget.isDesktop)
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        
        // CUSTOM HEADER
        Padding(
          padding: EdgeInsets.only(top: widget.isDesktop ? 12 : 4, left: 12, right: 12, bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _buildNavButton(
                    Icons.keyboard_double_arrow_left_rounded,
                    () {
                      if (_currentView == DateRangePickerView.month) {
                        setState(() {
                          _currentDisplayDate = DateTime(_currentDisplayDate.year - 1, _currentDisplayDate.month);
                          _controller.displayDate = _currentDisplayDate;
                        });
                      } else if (_currentView == DateRangePickerView.year) {
                        setState(() {
                          _currentDisplayDate = DateTime(_currentDisplayDate.year - 10, _currentDisplayDate.month);
                          _controller.displayDate = _currentDisplayDate;
                        });
                      }
                    },
                  ),
                  _buildNavButton(
                    Icons.chevron_left_rounded,
                    () {
                      if (_currentView == DateRangePickerView.month) {
                        setState(() {
                          _currentDisplayDate = DateTime(_currentDisplayDate.year, _currentDisplayDate.month - 1);
                          _controller.displayDate = _currentDisplayDate;
                        });
                      } else if (_currentView == DateRangePickerView.year) {
                        setState(() {
                          _currentDisplayDate = DateTime(_currentDisplayDate.year - 1, _currentDisplayDate.month);
                          _controller.displayDate = _currentDisplayDate;
                        });
                      }
                    },
                  ),
                ],
              ),
              Expanded(
                child: (widget.isDesktop && widget.isRange) 
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(child: Center(child: _buildClickableHeader(_currentDisplayDate))),
                        if (_currentView == DateRangePickerView.month)
                          Expanded(child: Center(child: _buildClickableHeader(DateTime(_currentDisplayDate.year, _currentDisplayDate.month + 1)))),
                      ],
                    )
                  : Center(
                      child: (widget.isRange && _currentView == DateRangePickerView.month && !widget.isDesktop)
                        ? InkWell(
                            onTap: () {
                              _controller.view = DateRangePickerView.year;
                              setState(() => _currentView = DateRangePickerView.year);
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                              child: Text(
                                '${DateFormat.yMMMM('tr').format(_currentDisplayDate)} - ${DateFormat.yMMMM('tr').format(DateTime(_currentDisplayDate.year, _currentDisplayDate.month + 1))}',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
                              ),
                            ),
                          )
                        : _buildClickableHeader(_currentDisplayDate),
                    ),
              ),
              Row(
                children: [
                  _buildNavButton(
                    Icons.chevron_right_rounded,
                    () {
                      if (_currentView == DateRangePickerView.month) {
                        setState(() {
                          _currentDisplayDate = DateTime(_currentDisplayDate.year, _currentDisplayDate.month + 1);
                          _controller.displayDate = _currentDisplayDate;
                        });
                      } else if (_currentView == DateRangePickerView.year) {
                        setState(() {
                          _currentDisplayDate = DateTime(_currentDisplayDate.year + 1, _currentDisplayDate.month);
                          _controller.displayDate = _currentDisplayDate;
                        });
                      }
                    },
                  ),
                  _buildNavButton(
                    Icons.keyboard_double_arrow_right_rounded,
                    () {
                      if (_currentView == DateRangePickerView.month) {
                        setState(() {
                          _currentDisplayDate = DateTime(_currentDisplayDate.year + 1, _currentDisplayDate.month);
                          _controller.displayDate = _currentDisplayDate;
                        });
                      } else if (_currentView == DateRangePickerView.year) {
                        setState(() {
                          _currentDisplayDate = DateTime(_currentDisplayDate.year + 10, _currentDisplayDate.month);
                          _controller.displayDate = _currentDisplayDate;
                        });
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // DATE PICKER
        Expanded(
          child: Theme(
            data: Theme.of(context).copyWith(
              hoverColor: const Color(0xFFE6F4FF),
              highlightColor: const Color(0xFFE6F4FF),
              splashColor: Colors.transparent,
              primaryColor: const Color(0xFF1677FF),
              colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: const Color(0xFF1677FF),
                secondary: const Color(0xFF1677FF),
                surfaceContainerHighest: const Color(0xFFE6F4FF), 
                onSurface: Colors.black87,
              ),
            ),
            child: SfDateRangePicker(
              controller: _controller,
              backgroundColor: Colors.white, 
              selectionMode: widget.isRange ? DateRangePickerSelectionMode.range : DateRangePickerSelectionMode.single,
              initialSelectedRange: widget.isRange && widget.initialRange != null
                  ? PickerDateRange(widget.initialRange!.start, widget.initialRange!.end)
                  : null,
              initialSelectedDate: !widget.isRange ? widget.initialDate : null,
              showNavigationArrow: false, 
              enableMultiView: widget.isRange, // Multi view ONLY for ranges now!
              navigationDirection: widget.isDesktop 
                  ? DateRangePickerNavigationDirection.horizontal 
                  : DateRangePickerNavigationDirection.vertical,
              headerHeight: 0, 
              allowViewNavigation: true,
              monthViewSettings: const DateRangePickerMonthViewSettings(
                viewHeaderStyle: DateRangePickerViewHeaderStyle(
                  backgroundColor: Colors.white,
                  textStyle: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    fontSize: 13,
                  ),
                ),
              ),
              monthCellStyle: DateRangePickerMonthCellStyle(
                textStyle: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
                todayTextStyle: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1677FF), 
                ),
              ),
              yearCellStyle: DateRangePickerYearCellStyle(
                textStyle: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
                todayTextStyle: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1677FF), 
                ),
              ),
              rangeSelectionColor: const Color(0xFFE6F4FF), 
              startRangeSelectionColor: const Color(0xFF1677FF),
              endRangeSelectionColor: const Color(0xFF1677FF),
              selectionColor: const Color(0xFF1677FF),
              selectionTextStyle: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              rangeTextStyle: GoogleFonts.inter(
                color: Colors.black87,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              showActionButtons: false,
              onViewChanged: (DateRangePickerViewChangedArgs args) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  bool changed = false;
                  if (args.visibleDateRange.startDate != _currentDisplayDate) {
                    _currentDisplayDate = args.visibleDateRange.startDate!;
                    changed = true;
                  }
                  if (_controller.view != null && _controller.view != _currentView) {
                    _currentView = _controller.view!;
                    changed = true;
                  }
                  if (changed) {
                    setState(() {});
                  }
                });
              },
            ),
          ),
        ),
        
        // CUSTOM ACTION BUTTONS
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                offset: const Offset(0, -4),
                blurRadius: 12,
              )
            ]
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    side: const BorderSide(color: Color(0xFFD9D9D9)),
                  ),
                  child: Text('İptal', style: GoogleFonts.inter(color: Colors.black87, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    if (widget.isRange) {
                      final range = _controller.selectedRange;
                      if (range != null && range.startDate != null) {
                        Navigator.pop(context, DateTimeRange(
                          start: range.startDate!,
                          end: range.endDate ?? range.startDate!
                        ) as T);
                      } else {
                        Navigator.pop(context, null);
                      }
                    } else {
                      final date = _controller.selectedDate;
                      if (date != null) {
                        Navigator.pop(context, date as T);
                      } else {
                        Navigator.pop(context, null);
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1677FF),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: Text('Uygula', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
