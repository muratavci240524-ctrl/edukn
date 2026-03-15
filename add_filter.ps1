$filePath = "lib\screens\school\student_registration_screen.dart"
$content = Get-Content $filePath -Encoding UTF8 -Raw

# Düzenleme dialog'u (satır ~4143)
$content = $content -replace "(\s+\.where\('classLevel', isEqualTo: int\.tryParse\(tempData\['classLevel'\]\?\.toString\(\) \?\? '0'\) \?\? 0\)\s+\.where\('isActive', isEqualTo: true\))", "`$1`n                .where('classTypeName', isEqualTo: 'Ders Sınıfı')"

# Yeni öğrenci formu (satır ~4873) - Key ekle ve filtre ekle
$content = $content -replace "(\s+child: FutureBuilder<List<Map<String, dynamic>>>\(\s+future: _selectedSchoolTypeId == null \|\| _selectedClassLevel == null)", "`$1`n                  key: ValueKey('new_student_class_`${_selectedSchoolTypeId}_`${_selectedClassLevel}'),"

$content = $content -replace "(\s+\.where\('classLevel', isEqualTo: int\.tryParse\(_selectedClassLevel \?\? ''\) \?\? 0\)\s+\.where\('isActive', isEqualTo: true\))", "`$1`n                          .where('classTypeName', isEqualTo: 'Ders Sınıfı')"

# Düzenleme formu (satır ~7734)
$pattern = "\.where\('classLevel', isEqualTo: int\.tryParse\(_selectedClassLevel \?\? ''\) \?\? 0\)\s+\.where\('isActive', isEqualTo: true\)"
$matches = [regex]::Matches($content, $pattern)
if ($matches.Count -ge 2) {
    $secondMatch = $matches[1]
    $before = $content.Substring(0, $secondMatch.Index + $secondMatch.Length)
    $after = $content.Substring($secondMatch.Index + $secondMatch.Length)
    $content = $before + "`n                          .where('classTypeName', isEqualTo: 'Ders Sınıfı')" + $after
}

$content | Out-File $filePath -Encoding UTF8 -NoNewline
Write-Host "Filters added successfully!"
