$filePath = "lib\screens\school\student_registration_screen.dart"
$lines = Get-Content $filePath -Encoding UTF8
$newLines = @()

foreach ($line in $lines) {
    if ($line -notmatch "classTypeName.*Ders") {
        $newLines += $line
    }
}

$newLines | Out-File $filePath -Encoding UTF8
Write-Host "Filter removed successfully!"
