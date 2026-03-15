const fs = require('fs');

const filePath = 'lib\\screens\\school\\student_registration_screen.dart';

// Dosyayı oku
let content = fs.readFileSync(filePath, 'utf8');

// Duplike satırı kaldır (arka arkaya aynı where clause)
content = content.replace(/(\s*\.where\('classTypeName', isEqualTo: 'Ders Sınıfı'\)\s*\n)\s*\.where\('classTypeName', isEqualTo: 'Ders Sınıfı'\)/g, '$1');

// Dosyayı yaz
fs.writeFileSync(filePath, content, 'utf8');

console.log('✅ Duplike satır kaldırıldı!');
