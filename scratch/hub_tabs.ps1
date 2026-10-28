$p = 'lib\screens\school\tools\butterfly_exam\butterfly_exam_hub_screen.dart'
$script:t = [System.IO.File]::ReadAllText($p)
function Rep([string]$pat, [string]$rep) {
  $m = [regex]::Match($script:t, $pat)
  if (-not $m.Success) { Write-Output "NO MATCH: $pat"; return }
  $script:t = $script:t.Remove($m.Index, $m.Length).Insert($m.Index, $rep)
}

# state
Rep "  String _searchQuery = '';" "  bool _showCompleted = false; // false: Aktif, true: Pasif (tamamlanan)`r`n  String _searchQuery = '';"

# sekmeler arama kutusunun üstünde
Rep "      child: Column\(\r?\n        children: \[\r?\n          // Arama Giri.i" "      child: Column(`r`n        children: [`r`n          _buildStatusTabs(),`r`n          const SizedBox(height: 10),`r`n          // Arama Girişi"

# duruma göre filtre
Rep "    final filteredExams = exams\.where\(\(e\) \{\r?\n      if \(_searchQuery\.isEmpty\) return true;" "    final filteredExams = exams.where((e) {`r`n      if (e.isCompleted != _showCompleted) return false;`r`n      if (_searchQuery.isEmpty) return true;"

Rep "    if \(filteredExams\.isEmpty\) \{\r?\n      return _buildEmptyState\(\);" "    if (filteredExams.isEmpty) {`r`n      if (exams.isNotEmpty || _showCompleted) return _buildNoResultState();`r`n      return _buildEmptyState();"

# Tamamla / Aktife Al butonu
$extra = @"
                  const SizedBox(width: 8),
                  Tooltip(
                    message: exam.isCompleted ? 'Aktife Al' : 'Sınavı Tamamla (Pasife Al)',
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        foregroundColor: exam.isCompleted ? const Color(0xFFF59E0B) : const Color(0xFF0F766E),
                        side: BorderSide(
                          color: exam.isCompleted ? const Color(0xFFFDE68A) : const Color(0xFF99F6E4),
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => exam.isCompleted ? _setCompleted(exam, false) : _confirmComplete(exam),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(exam.isCompleted ? Icons.unarchive_outlined : Icons.task_alt_rounded, size: 16),
                          const SizedBox(width: 4),
                          Text(exam.isCompleted ? 'Aktife Al' : 'Tamamla',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),

"@
Rep "(?<=style: GoogleFonts\.inter\(fontSize: 12, fontWeight: FontWeight\.w700\)\),\r?\n\s{20}\),\r?\n\s{18}\),\r?\n)(?=\s{16}\],)" ($extra -replace "`n", "`r`n")

# yeni yardımcı widget ve metotlar: _buildSearchAndInfoBar'ın hemen üstüne ekle
$helpers = @"
  // ===========================================================================
  // AKTİF / PASİF SEKMELERİ
  // ===========================================================================
  Widget _buildStatusTabs() {
    Widget tab(String label, IconData icon, bool completed, Color color) {
      final on = _showCompleted == completed;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _showCompleted = completed),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: on ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: on
                  ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: on ? Colors.white : const Color(0xFF64748B)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: on ? Colors.white : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8ECF4),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          tab('Aktif', Icons.play_circle_outline_rounded, false, const Color(0xFF4F46E5)),
          tab('Pasif', Icons.inventory_2_outlined, true, const Color(0xFF64748B)),
        ],
      ),
    );
  }

  Widget _buildNoResultState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_showCompleted ? Icons.inventory_2_outlined : Icons.search_off_rounded,
                size: 44, color: const Color(0xFF94A3B8)),
            const SizedBox(height: 10),
            Text(
              _showCompleted ? 'Tamamlanan sınav yok' : 'Aktif sınav bulunamadı',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15, color: const Color(0xFF334155)),
            ),
            const SizedBox(height: 4),
            Text(
              _showCompleted
                  ? 'Yoklaması alınan sınavları "Tamamla" ile buraya taşıyabilirsiniz.'
                  : 'Aramanızı değiştirin veya yeni bir sınav oluşturun.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmComplete(ExamDistribution exam) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Sınavı Tamamla', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
        content: Text(
          '"${exam.title}" çalışması tamamlandı olarak işaretlenecek ve Pasif sekmesine taşınacak. Dilediğiniz zaman Aktife alabilirsiniz.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tamamla'),
          ),
        ],
      ),
    );
    if (ok == true) await _setCompleted(exam, true);
  }

  Future<void> _setCompleted(ExamDistribution exam, bool completed) async {
    final id = exam.id;
    if (id == null || id.isEmpty) return;
    try {
      final db = FirebaseFirestore.instance;
      var ref = db.collection('butterfly_exams').doc(id);
      if (!(await ref.get()).exists) ref = db.collection('seating_plans').doc(id);
      await ref.set({
        'isCompleted': completed,
        'completedAt': completed ? Timestamp.now() : null,
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(completed ? 'Sınav tamamlandı, Pasif sekmesine taşındı.' : 'Sınav tekrar Aktif.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem başarısız: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

"@
Rep "  // =+\r?\n  // ARAMA VE B.LG. ..R.D.\r?\n" (($helpers -replace "`n", "`r`n") + "  // ===========================================================================`r`n  // ARAMA VE BİLGİ ŞERİDİ`r`n")

[System.IO.File]::WriteAllText($p, $script:t, (New-Object System.Text.UTF8Encoding($false)))
Select-String -Path $p -Pattern "_buildStatusTabs|_showCompleted|_buildNoResultState|_setCompleted" | ForEach-Object { "$($_.LineNumber): $($_.Line.Trim())" }
flutter analyze $p
