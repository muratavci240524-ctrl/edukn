import 'dart:io';

void main() {
  final file = File('c:\\Users\\mavci\\Desktop\\Projeler\\eduKN\\edukn21.11.2025\\edukn\\lib\\services\\pdf_service.dart');
  String content = file.readAsStringSync();
  
  // Find the pattern: closing brace, followed by potential spaces, followed by another closing brace
  // and then the comment or next declaration.
  final pattern = RegExp(r'\}\s*\}\s*(\/\/ --- PREMIUM)');
  
  if (pattern.hasMatch(content)) {
    content = content.replaceFirst(pattern, '} \$1');
    file.writeAsStringSync(content);
    print('Brace syntax error fixed successfully.');
  } else {
    print('Could not find the syntax error pattern.');
  }
}
