import 'dart:io';
void main() {
  var dir = Directory('lib');
  for (var file in dir.listSync(recursive: true)) {
    if (file is File && file.path.endsWith('.dart')) {
      var content = file.readAsStringSync().toLowerCase();
      if (content.contains('deneme')) {
        print(file.path);
      }
    }
  }
}
