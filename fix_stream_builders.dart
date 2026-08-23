import 'dart:io';

void main() async {
  final libDir = Directory('lib');
  if (!await libDir.exists()) {
    print('lib directory not found');
    return;
  }

  const importStatement = "import 'package:edukn/widgets/safe_stream_builder.dart';\n";
  int filesModified = 0;

  final files = libDir.listSync(recursive: true);
  for (final entity in files) {
    if (entity is File && entity.path.endsWith('.dart') && !entity.path.contains('safe_stream_builder.dart')) {
      String content;
      try {
        content = await entity.readAsString();
      } catch (e) {
        try {
           content = await entity.readAsString(encoding: SystemEncoding());
        } catch (e2) {
           print('Skipping ${entity.path} due to encoding error');
           continue;
        }
      }
      
      // Look for StreamBuilder< or StreamBuilder(
      final streamBuilderRegex = RegExp(r'(?<!Safe)StreamBuilder[\s]*[<\(]');
      
      if (streamBuilderRegex.hasMatch(content)) {
        String newContent = content.replaceAllMapped(streamBuilderRegex, (match) {
          final suffix = match.group(0)!.substring(match.group(0)!.length - 1);
          return 'SafeStreamBuilder$suffix';
        });

        if (!newContent.contains("import 'package:edukn/widgets/safe_stream_builder.dart';")) {
          final importRegex = RegExp(r'^import\s+.*;$', multiLine: true);
          final matches = importRegex.allMatches(newContent);
          
          if (matches.isNotEmpty) {
            final lastMatch = matches.last;
            final insertPos = lastMatch.end + 1;
            newContent = newContent.substring(0, insertPos) + importStatement + newContent.substring(insertPos);
          } else {
            newContent = importStatement + newContent;
          }
        }
        
        await entity.writeAsString(newContent);
        filesModified++;
        print('Updated: ${entity.path}');
      }
    }
  }
  
  print('Total files updated: $filesModified');
}
