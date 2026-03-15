#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import re

file_path = r'lib\screens\school\student_registration_screen.dart'

# Dosyayı oku
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Yanlış key pozisyonunu düzelt (2 yerde)
# Önce: future: ... \n key: ... \n ?
# Sonra: key: ... \n future: ... \n ?
pattern1 = r'(child: FutureBuilder<List<Map<String, dynamic>>>\(\s*\n\s*)future: (_selectedSchoolTypeId == null \|\| _selectedClassLevel == null)\s*\n\s*key: (ValueKey\([^\)]+\)),\s*\n\s*(\?)'
replacement1 = r'\1key: \3,\n                  future: \2\n                      \4'
content = re.sub(pattern1, replacement1, content)

# 2. Bozuk Türkçe karakterleri düzelt
content = content.replace('Ders SÄ±nÄ±fÄ±', 'Ders Sınıfı')
content = content.replace('Ders Sinifi', 'Ders Sınıfı')

# 3. Eğer hala classTypeName filtresi yoksa ekle
# Düzenleme dialog için
pattern2 = r"(\.where\('classLevel', isEqualTo: int\.tryParse\(tempData\['classLevel'\]\?\.toString\(\) \?\? '0'\) \?\? 0\)\s*\n\s*\.where\('isActive', isEqualTo: true\))"
if re.search(pattern2, content):
    replacement2 = r"\1\n                .where('classTypeName', isEqualTo: 'Ders Sınıfı')"
    content = re.sub(pattern2, replacement2, content, count=1)

# Dosyayı yaz
with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("✅ Dosya başarıyla düzeltildi!")
print("- Key pozisyonları düzeltildi")
print("- Türkçe karakterler düzeltildi")
print("- Ders Sınıfı filtreleri eklendi")
