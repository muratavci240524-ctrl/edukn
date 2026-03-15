$filePath = "lib\screens\school\student_registration_screen.dart"
$content = Get-Content $filePath -Encoding UTF8 -Raw

# Türkçe karakter düzeltmesi
$content = $content -replace "Ders SÄ±nÄ±fÄ±", "Ders Sınıfı"

# Key pozisyonunu düzelt
$content = $content -replace "future: _selectedSchoolTypeId == null \|\| _selectedClassLevel == null\s+key: ValueKey", "key: ValueKey('new_student_class_`${_selectedSchoolTypeId}_`${_selectedClassLevel}'),`n                  future: _selectedSchoolTypeId == null || _selectedClassLevel == null"

# Yanlış key satırını kaldır
$content = $content -replace "\s+key: ValueKey\('new_student_class_\`\$\{_selectedSchoolTypeId\}_\`\$\{_selectedClassLevel\}'\),\s+\?", "`n                      ?"

$content | Out-File $filePath -Encoding UTF8 -NoNewline
Write-Host "Encoding fixed!"
