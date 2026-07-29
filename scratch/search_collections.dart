import 'dart:io';

void main() async {
  final file = File(r"c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\lib\screens\school\student_registration_screen.dart");
  final content = await file.readAsString();
  
  final regex = RegExp(r"collection\(['""](\w+)['""]\)");
  final matches = regex.allMatches(content);
  print("Firestore Collections queried in student_registration_screen.dart:");
  for (var m in matches) {
    print("  - ${m.group(1)}");
  }
}
