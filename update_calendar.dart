import 'dart:io';

void main() {
  final newPickRange = '''  Future<void> _pickRange() async {
    final picked = await CustomDateRangePicker.show(
      context,
      initialRange: _range,
      // desktopAlignment and desktopPadding retain default values for standard announcements layout
    );

    if (picked != null && picked.startDate != null) {
      setState(() {
        _range = DateTimeRange(
          start: picked.startDate!,
          end: picked.endDate ?? picked.startDate!,
        );
      });
    }
  }''';

  final files = [
    'lib/screens/announcements/announcements_screen.dart',
    'lib/screens/school/school_types/school_type_announcements_screen.dart',
    'lib/screens/teacher/teacher_announcements_screen.dart'
  ];

  for (final file in files) {
    final f = File(file);
    String content = f.readAsStringSync();
    
    final regExp = RegExp(r"  Future<void> _pickRange\(\) async \{.*?\n  \}", multiLine: true, dotAll: true);
    
    if (regExp.hasMatch(content)) {
      content = content.replaceFirst(regExp, newPickRange);
      
      // Also inject the import if not present
      if (!content.contains('custom_date_range_picker.dart')) {
        content = content.replaceFirst(
          "import 'package:flutter/material.dart';",
          "import 'package:flutter/material.dart';\nimport 'package:edukn/widgets/custom_date_range_picker.dart';"
        );
      }
      
      f.writeAsStringSync(content);
      print("Updated \$file");
    } else {
      print("Could not find _pickRange in \$file");
    }
  }
}
