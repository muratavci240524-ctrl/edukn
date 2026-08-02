import 'dart:io';

void main() {
  final file = File('lib/screens/announcements/announcement_form_sheet.dart');
  String content = file.readAsStringSync();
  
  if (!content.contains('custom_date_range_picker.dart')) {
    content = content.replaceFirst(
      "import 'package:flutter/material.dart';",
      "import 'package:flutter/material.dart';\nimport 'package:edukn/widgets/custom_date_range_picker.dart';"
    );
  }

  // Replace Pattern 1:
  final pattern1 = RegExp(r'final picked = await showDatePicker\([\s\S]*?initialDate:\s*_startDate,[\s\S]*?\);', multiLine: true);
  content = content.replaceFirst(pattern1, 'final picked = await CustomDateRangePicker.showSingle(context, initialDate: _startDate);');

  // Replace Pattern 2:
  final pattern2 = RegExp(r'final picked = await showDatePicker\([\s\S]*?initialDate:\s*_endDate,[\s\S]*?\);', multiLine: true);
  content = content.replaceFirst(pattern2, 'final picked = await CustomDateRangePicker.showSingle(context, initialDate: _endDate);');

  // Replace Pattern 3:
  final pattern3 = RegExp(r'final date = await showDatePicker\([\s\S]*?initialDate:\s*DateTime\.now\(\),[\s\S]*?\);', multiLine: true);
  content = content.replaceFirst(pattern3, 'final date = await CustomDateRangePicker.showSingle(context, initialDate: DateTime.now());');

  // Replace Pattern 4:
  final pattern4 = RegExp(r'final date = await showDatePicker\([\s\S]*?initialDate:\s*DateTime\.now\(\)\.add\([\s\S]*?\),[\s\S]*?\);', multiLine: true);
  content = content.replaceFirst(pattern4, 'final date = await CustomDateRangePicker.showSingle(context, initialDate: DateTime.now().add(const Duration(days: 1)));');

  // Wait, let's just make it simpler by matching exact strings if they are slightly different
  content = content.replaceAllMapped(RegExp(r'final (picked|date) = await showDatePicker\([\s\S]*?initialDate:\s*([^,]+),[\s\S]*?\);', multiLine: true), (match) {
    return 'final \${match.group(1)} = await CustomDateRangePicker.showSingle(context, initialDate: \${match.group(2)});';
  });

  file.writeAsStringSync(content);
  print("Updated announcement_form_sheet.dart");
}
