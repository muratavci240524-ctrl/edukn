$e = New-Object System.Text.UTF8Encoding($false)
$o = flutter analyze --no-pub 2>&1 | Out-String -Width 500
$hits = @{}
foreach ($l in ($o -split "`n")) {
  if ($l -match 'use_build_context_synchronously' -and $l -match ' - (lib\\[^:]+):(\d+):(\d+) - ') {
    $k = $Matches[1]; if (-not $hits[$k]) { $hits[$k] = New-Object System.Collections.ArrayList }
    [void]$hits[$k].Add([int]$Matches[2])
  }
}
$starter = '^\s*(await\s+)?(Navigator\.|ScaffoldMessenger\.of|showDialog|showModalBottomSheet)'
function Bal($s) { ($s.ToCharArray() | ? { $_ -eq '(' }).Count - ($s.ToCharArray() | ? { $_ -eq ')' }).Count }
$total = 0; $touched = @()
foreach ($k in $hits.Keys) {
  $raw = [IO.File]::ReadAllText($k)
  if ($raw -notmatch 'extends State<') { continue }
  $eol = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
  $lines = $raw -split "`r?`n"
  $done = @{}
  $mod = $false
  foreach ($n in ($hits[$k] | Sort-Object -Unique)) {
    for ($s = $n - 1; $s -ge [Math]::Max(0, $n - 12); $s--) {
      if ($lines[$s] -match $starter -and $lines[$s] -notmatch 'if \(mounted\)') {
        $bal = 0; $end = -1
        for ($j = $s; $j -lt [Math]::Min($lines.Count, $s + 40); $j++) {
          $bal += (Bal $lines[$j])
          if ($bal -le 0) { $end = $j; break }
        }
        if ($end -ge ($n - 1) -and $lines[$end].TrimEnd().EndsWith(';') -and -not $done[$s]) {
          # önceki satır tamamlanmamış bir ifade ise (',' ile bitiyorsa) dokunma
          $prev = if ($s -gt 0) { $lines[$s - 1].TrimEnd() } else { '' }
          if ($prev.EndsWith(',') -or $prev.EndsWith('=>') -or $prev.EndsWith('(') -or $prev.EndsWith('=')) { break }
          $lines[$s] = ($lines[$s] -replace '^(\s*)', '$1if (mounted) ')
          $done[$s] = $true; $mod = $true; $total++
        }
        break
      }
      if ($lines[$s] -match '^\s*(\}|\{)\s*$' -or $lines[$s] -match ';\s*$') { if ($s -lt $n - 1) { break } }
    }
  }
  if ($mod) { [IO.File]::WriteAllText($k, ($lines -join $eol), $e); $touched += $k }
}
"$total statements in $($touched.Count) files"
