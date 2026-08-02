import 'dart:io';

void main() {
  final file = File('lib/screens/announcements/create_announcement_screen.dart');
  String content = file.readAsStringSync();
  
  if (!content.contains('custom_date_range_picker.dart')) {
    content = content.replaceFirst(
      "import 'package:flutter/material.dart';",
      "import 'package:flutter/material.dart';\nimport 'package:edukn/widgets/custom_date_range_picker.dart';"
    );
  }

  content = content.replaceAll('''    final picked = await showDatePicker(
      context: context,
      initialDate: _publishDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );''', '''    final picked = await CustomDateRangePicker.showSingle(
      context,
      initialDate: _publishDate,
    );''');
    
  content = content.replaceAll('''                                  final date = await showDatePicker(
                                    context: context,
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime(DateTime.now().year + 2),
                                    initialDate: DateTime.now().add(
                                      const Duration(days: 1),
                                    ),
                                  );''', '''                                  final date = await CustomDateRangePicker.showSingle(
                                    context,
                                    initialDate: DateTime.now().add(const Duration(days: 1)),
                                  );''');
                                  
  file.writeAsStringSync(content);
  print("Updated create_announcement_screen.dart");
}
