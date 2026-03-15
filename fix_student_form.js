const fs = require('fs');

const filePath = 'lib\\screens\\school\\student_registration_screen.dart';

// Dosyayı oku
let content = fs.readFileSync(filePath, 'utf8');

// 1. Yanlış key pozisyonunu düzelt
const pattern1 = /(child: FutureBuilder<List<Map<String, dynamic>>>\(\s*\n\s*)future: (_selectedSchoolTypeId == null \|\| _selectedClassLevel == null)\s*\n\s*key: (ValueKey\([^\)]+\)),\s*\n\s*(\?)/g;
content = content.replace(pattern1, '$1key: $3,\n                  future: $2\n                      $4');

// 2. Bozuk Türkçe karakterleri düzelt
content = content.replace(/Ders SÄ±nÄ±fÄ±/g, 'Ders Sınıfı');
content = content.replace(/Ders Sinifi/g, 'Ders Sınıfı');

// Dosyayı yaz
fs.writeFileSync(filePath, content, 'utf8');

console.log('✅ Dosya başarıyla düzeltildi!');
console.log('- Key pozisyonları düzeltildi');
console.log('- Türkçe karakterler düzeltildi');
