import 'dart:io';

void main() {
  final content = '''import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';

class CustomDateRangePicker {
  static Future<PickerDateRange?> show(
    BuildContext context, {
    DateTimeRange? initialRange,
    AlignmentGeometry desktopAlignment = Alignment.topRight,
    EdgeInsetsGeometry desktopPadding = const EdgeInsets.only(top: 130, right: 24),
  }) async {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    
    if (isDesktop) {
      return await showDialog<PickerDateRange>(
        context: context,
        barrierColor: Colors.black.withOpacity(0.2), 
        builder: (context) {
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  behavior: HitTestBehavior.opaque,
                  child: Container(color: Colors.transparent),
                ),
              ),
              Align(
                alignment: desktopAlignment,
                child: Padding(
                  padding: desktopPadding,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 640,
                      height: 440,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: _PickerBody(initialRange: initialRange, isDesktop: true),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    } else {
      // MOBILE BOTTOM SHEET
      return await showModalBottomSheet<PickerDateRange>(
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
            child: _PickerBody(initialRange: initialRange, isDesktop: false),
          );
        },
      );
    }
  }
}

class _PickerBody extends StatefulWidget {
  final DateTimeRange? initialRange;
  final bool isDesktop;

  const _PickerBody({Key? key, this.initialRange, required this.isDesktop}) : super(key: key);

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  late DateRangePickerController _controller;
  late DateTime _currentDisplayDate;
  DateRangePickerView _currentView = DateRangePickerView.month;

  @override
  void initState() {
    super.initState();
    _controller = DateRangePickerController();
    _currentDisplayDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
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
      return "\$startYear - \${startYear + 9}";
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
                child: widget.isDesktop 
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(child: Center(child: _buildClickableHeader(_currentDisplayDate))),
                        if (_currentView == DateRangePickerView.month)
                          Expanded(child: Center(child: _buildClickableHeader(DateTime(_currentDisplayDate.year, _currentDisplayDate.month + 1)))),
                      ],
                    )
                  : Center(
                      child: _currentView == DateRangePickerView.month
                        ? InkWell(
                            onTap: () {
                              _controller.view = DateRangePickerView.year;
                              setState(() => _currentView = DateRangePickerView.year);
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                              child: Text(
                                "\${DateFormat.yMMMM('tr').format(_currentDisplayDate)} - \${DateFormat.yMMMM('tr').format(DateTime(_currentDisplayDate.year, _currentDisplayDate.month + 1))}",
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
              selectionMode: DateRangePickerSelectionMode.range,
              initialSelectedRange: widget.initialRange != null
                  ? PickerDateRange(widget.initialRange!.start, widget.initialRange!.end)
                  : null,
              showNavigationArrow: false, 
              enableMultiView: true, 
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
              showActionButtons: false, // We use custom action buttons now
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
                    final range = _controller.selectedRange;
                    Navigator.pop(context, range);
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
''';

  final f = File('lib/widgets/custom_date_range_picker.dart');
  f.writeAsStringSync(content);
  print("Updated custom_date_range_picker.dart");
}
