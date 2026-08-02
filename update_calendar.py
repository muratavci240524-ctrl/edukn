import re

new_pick_range = """  Future<void> _pickRange() async {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    
    final picked = await showDialog<PickerDateRange>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.2), 
      builder: (context) {
        final DateRangePickerController controller = DateRangePickerController();
        DateTime currentDisplayDate = DateTime(DateTime.now().year, DateTime.now().month, 1);

        Widget buildNavButton(IconData icon, VoidCallback onTap) {
          return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(icon, size: 22, color: Colors.grey.shade700),
            ),
          );
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                  alignment: isDesktop ? Alignment.topRight : Alignment.center,
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: isDesktop ? 130 : 0, 
                      right: isDesktop ? 24 : 0,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        width: isDesktop ? 640 : MediaQuery.of(context).size.width * 0.95,
                        height: isDesktop ? 440 : MediaQuery.of(context).size.height * 0.75,
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
                        child: Column(
                          children: [
                            // CUSTOM HEADER
                            Padding(
                              padding: const EdgeInsets.only(top: 12, left: 12, right: 12, bottom: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      buildNavButton(
                                        Icons.keyboard_double_arrow_left_rounded,
                                        () {
                                          final newDate = DateTime(currentDisplayDate.year - 1, currentDisplayDate.month);
                                          controller.displayDate = newDate;
                                          setDialogState(() => currentDisplayDate = newDate);
                                        },
                                      ),
                                      buildNavButton(
                                        Icons.chevron_left_rounded,
                                        () {
                                          final newDate = DateTime(currentDisplayDate.year, currentDisplayDate.month - 1);
                                          controller.displayDate = newDate;
                                          setDialogState(() => currentDisplayDate = newDate);
                                        },
                                      ),
                                    ],
                                  ),
                                  Expanded(
                                    child: isDesktop 
                                      ? Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                DateFormat.yMMMM('tr').format(currentDisplayDate),
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                DateFormat.yMMMM('tr').format(DateTime(currentDisplayDate.year, currentDisplayDate.month + 1)),
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
                                              ),
                                            ),
                                          ],
                                        )
                                      : Text(
                                          "${DateFormat.yMMMM('tr').format(currentDisplayDate)} - ${DateFormat.yMMMM('tr').format(DateTime(currentDisplayDate.year, currentDisplayDate.month + 1))}",
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
                                        ),
                                  ),
                                  Row(
                                    children: [
                                      buildNavButton(
                                        Icons.chevron_right_rounded,
                                        () {
                                          final newDate = DateTime(currentDisplayDate.year, currentDisplayDate.month + 1);
                                          controller.displayDate = newDate;
                                          setDialogState(() => currentDisplayDate = newDate);
                                        },
                                      ),
                                      buildNavButton(
                                        Icons.keyboard_double_arrow_right_rounded,
                                        () {
                                          final newDate = DateTime(currentDisplayDate.year + 1, currentDisplayDate.month);
                                          controller.displayDate = newDate;
                                          setDialogState(() => currentDisplayDate = newDate);
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
                                ),
                                child: SfDateRangePicker(
                                  controller: controller,
                                  backgroundColor: Colors.white, 
                                  selectionMode: DateRangePickerSelectionMode.range,
                                  initialSelectedRange: _range != null
                                      ? PickerDateRange(_range!.start, _range!.end)
                                      : null,
                                  showNavigationArrow: false, 
                                  enableMultiView: true, 
                                  navigationDirection: isDesktop 
                                      ? DateRangePickerNavigationDirection.horizontal 
                                      : DateRangePickerNavigationDirection.vertical,
                                  headerHeight: 0, // HIDE NATIVE HEADER
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
                                  showActionButtons: true,
                                  cancelText: 'İptal',
                                  confirmText: 'Uygula',
                                  onSubmit: (val) {
                                    Navigator.pop(context, val);
                                  },
                                  onCancel: () {
                                    Navigator.pop(context);
                                  },
                                  onViewChanged: (DateRangePickerViewChangedArgs args) {
                                    if (args.visibleDateRange.startDate != currentDisplayDate) {
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        setDialogState(() {
                                          currentDisplayDate = args.visibleDateRange.startDate!;
                                        });
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
        );
      },
    );

    if (picked != null && picked.startDate != null) {
      setState(() {
        _range = DateTimeRange(
          start: picked.startDate!,
          end: picked.endDate ?? picked.startDate!,
        );
      });
    }
  }"""

files = [
    r"c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\lib\screens\announcements\announcements_screen.dart",
    r"c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\lib\screens\school\school_types\school_type_announcements_screen.dart",
    r"c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\lib\screens\teacher\teacher_announcements_screen.dart",
]

for file in files:
    with open(file, "r", encoding="utf-8") as f:
        content = f.read()
    
    # Use regex to find and replace the _pickRange method
    pattern = re.compile(r"  Future<void> _pickRange\(\) async \{.*?\n  }", re.DOTALL)
    
    new_content = pattern.sub(new_pick_range, content)
    
    with open(file, "w", encoding="utf-8") as f:
        f.write(new_content)
    print(f"Updated {file}")
