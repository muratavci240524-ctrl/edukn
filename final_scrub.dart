import 'dart:io';
import 'dart:convert';

void main() {
  final file = File('c:\\Users\\mavci\\Desktop\\Projeler\\eduKN\\edukn21.11.2025\\edukn\\lib\\services\\pdf_service.dart');
  String content = file.readAsStringSync(encoding: utf8);

  final Map<String, String> fixes = {
    'Ã‡': 'Ç',
    'Ã§': 'ç',
    'ÄŸ': 'ğ',
    'Äž': 'Ğ',
    'Ä±': 'ı',
    'Ä°': 'İ',
    'Ã¶': 'ö',
    'Ã–': 'Ö',
    'ÅŸ': 'ş',
    'Åž': 'Ş',
    'Ã¼': 'ü',
    'Ãœ': 'Ü',
    'Ã–ÄžRENCÄ°': 'ÖĞRENCİ',
    'ÖÄžRENCİ': 'ÖĞRENCİ',
    'GELİÅžÄ°M': 'GELİŞİM',
    'GELİÅžİM': 'GELİŞİM',
    'Ã‡alÄ±ÅŸma': 'Çalışma',
  };

  fixes.forEach((key, value) {
    content = content.replaceAll(key, value);
  });

  file.writeAsStringSync(content, encoding: utf8);
  print('Final character scrub completed.');
}
