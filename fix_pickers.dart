import 'dart:io';

void main() {
  final file = File('lib/screens/announcements/create_announcement_screen.dart');
  String content = file.readAsStringSync();
  
  // Replace Pattern 1
  final pattern1 = RegExp(r'final picked = await showDatePicker\([\s\S]*?initialDate:\s*_publishDate,[\s\S]*?\);', multiLine: true);
  content = content.replaceFirst(pattern1, 'final picked = await CustomDateRangePicker.showSingle(context, initialDate: _publishDate);');

  // Replace Pattern 2
  final pattern2 = RegExp(r'final date = await showDatePicker\([\s\S]*?initialDate:\s*DateTime\.now\(\)\.add\([\s\S]*?\),[\s\S]*?\);', multiLine: true);
  content = content.replaceFirst(pattern2, 'final date = await CustomDateRangePicker.showSingle(context, initialDate: DateTime.now().add(const Duration(days: 1)));');

  file.writeAsStringSync(content);
  print("Updated create_announcement_screen.dart via regex");
}
