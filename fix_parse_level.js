const fs = require('fs');

const filePath = 'lib\\screens\\school\\student_registration_screen.dart';

// Dosyayı oku
let content = fs.readFileSync(filePath, 'utf8');

// int.tryParse(_selectedClassLevel ?? '') ?? 0
// Değiştir: int.tryParse(_selectedClassLevel?.replaceAll(RegExp(r'[^0-9]'), '') ?? '') ?? 0

// Yeni öğrenci formu ve düzenleme formu için
content = content.replace(
  /int\.tryParse\(_selectedClassLevel \?\? ''\) \?\? 0/g,
  "int.tryParse(_selectedClassLevel?.replaceAll(RegExp(r'[^0-9]'), '') ?? '') ?? 0"
);

// Dosyayı yaz
fs.writeFileSync(filePath, content, 'utf8');

console.log('✅ Parse düzeltildi - sadece rakamlar alınacak!');
console.log('   "8. Sınıf" → 8');
console.log('   "12" → 12');
