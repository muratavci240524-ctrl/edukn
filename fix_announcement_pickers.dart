import 'dart:io';

void main() {
  final newPickRange = '''  Future<void> _pickRange() async {
    final picked = await CustomDateRangePicker.show(
      context,
      initialRange: _range,
      // desktopAlignment and desktopPadding retain default values for standard announcements layout
    );

    if (picked != null) {
      setState(() {
        _range = picked;
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
      f.writeAsStringSync(content);
      print("Updated \$file");
    }
  }
}
