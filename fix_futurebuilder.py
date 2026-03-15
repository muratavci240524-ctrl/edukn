import re

# Dosyayı oku
with open('lib/screens/school/student_registration_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# İlk FutureBuilder'a key ekle (satır 4867 civarı)
# İkinci FutureBuilder'a key ekle (satır 7730 civarı)

# Pattern: child: FutureBuilder<List<Map<String, dynamic>>>(
#          future: _selectedSchoolTypeId == null || _selectedClassLevel == null

pattern = r'(child: FutureBuilder<List<Map<String, dynamic>>>\(\s*\n\s*)(future: _selectedSchoolTypeId == null \|\| _selectedClassLevel == null)'

replacement = r'\1key: ValueKey(\'class_dropdown_${_selectedSchoolTypeId}_${_selectedClassLevel}\'),\n                  \2'

# Replace all occurrences
new_content = re.sub(pattern, replacement, content)

# Dosyayı yaz
with open('lib/screens/school/student_registration_screen.dart', 'w', encoding='utf-8') as f:
    f.write(new_content)

print("✅ FutureBuilder'lara key eklendi!")
