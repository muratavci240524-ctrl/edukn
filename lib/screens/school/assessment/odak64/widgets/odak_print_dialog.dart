import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/odak_models.dart';
import '../services/odak_engine.dart';
import '../services/odak_pdf_service.dart';
import '../services/odak_excel_service.dart';

/// Yazdırılacak sınıf(lar) ve ders(ler)i seçtiren şık yazdırma penceresi.
Future<void> showOdakPrintDialog(
  BuildContext context, {
  required List<OdakClassGroup> groups,
  required OdakAnalyzer analyzer,
  required List<String> subjects,
  required String examName,
  String? schoolName,
  String brand = 'ODAK-64',
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _OdakPrintDialog(
      groups: groups,
      analyzer: analyzer,
      subjects: subjects,
      examName: examName,
      schoolName: schoolName,
      brand: brand,
    ),
  );
}

class _OdakPrintDialog extends StatefulWidget {
  final List<OdakClassGroup> groups;
  final OdakAnalyzer analyzer;
  final List<String> subjects;
  final String examName;
  final String? schoolName;
  final String brand;

  const _OdakPrintDialog({
    required this.groups,
    required this.analyzer,
    required this.subjects,
    required this.examName,
    this.schoolName,
    required this.brand,
  });

  @override
  State<_OdakPrintDialog> createState() => _OdakPrintDialogState();
}

class _OdakPrintDialogState extends State<_OdakPrintDialog> {
  late final Set<String> _classes = {for (final g in OdakClassGroup.visibleGroups(widget.groups)) g.id};
  late final Set<String> _subjects = {...widget.subjects};
  bool _busy = false;

  bool _door = false;

  bool get _canPrint =>
      _classes.isNotEmpty && (_door || _subjects.isNotEmpty) && !_busy;

  Future<void> _run(bool print) async {
    setState(() => _busy = true);
    try {
      // Sıralamayı koru: seçili dersler orijinal sıradaki gibi.
      final subs = widget.subjects.where(_subjects.contains).toList();
      final bytes = _door
          ? await OdakPdfService.buildDoorList(
              groups: widget.groups,
              examName: widget.examName,
              schoolName: widget.schoolName,
              brand: widget.brand,
              classIds: Set<String>.from(_classes),
            )
          : await OdakPdfService.build(
              groups: widget.groups,
              analyzer: widget.analyzer,
              subjects: subs,
              examName: widget.examName,
              schoolName: widget.schoolName,
              brand: widget.brand,
              classIds: Set<String>.from(_classes),
            );
      if (print) {
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name: '${OdakPdfService.fileBase(widget.brand)}_Rapor.pdf',
        );
      } else {
        await Printing.sharePdf(bytes: bytes, filename: '${OdakPdfService.fileBase(widget.brand)}_Rapor.pdf');
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF hazırlanamadı: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 18, 12, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal.shade700, Colors.cyan.shade800, Colors.blue.shade900],
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.print_rounded, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Raporları Yazdır',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Sınıf ve ders seçin',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Group(
                      title: 'Sınıflar',
                      icon: Icons.groups_rounded,
                      allSelected: _classes.length == OdakClassGroup.visibleGroups(widget.groups).length,
                      onToggleAll: (v) => setState(() {
                        _classes
                          ..clear()
                          ..addAll(v ? OdakClassGroup.visibleGroups(widget.groups).map((g) => g.id) : const []);
                      }),
                      chips: [
                        for (final g in OdakClassGroup.visibleGroups(widget.groups))
                          FilterChip(
                            label: Text('${g.name} (${g.students.length})'),
                            selected: _classes.contains(g.id),
                            onSelected: (v) => setState(
                              () => v ? _classes.add(g.id) : _classes.remove(g.id),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (widget.brand == 'ODAK-64')
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Kapı listesi (sadece isimler)'),
                      subtitle: const Text('Puan, yüzde ve sıralama içermez'),
                      value: _door,
                      onChanged: (v) => setState(() => _door = v),
                    ),
                    const SizedBox(height: 8),
                    if (!_door)
                    _Group(
                      title: 'Dersler',
                      icon: Icons.menu_book_rounded,
                      allSelected: _subjects.length == widget.subjects.length,
                      onToggleAll: (v) => setState(() {
                        _subjects
                          ..clear()
                          ..addAll(v ? widget.subjects : const []);
                      }),
                      chips: [
                        for (final s in widget.subjects)
                          FilterChip(
                            label: Text(s),
                            selected: _subjects.contains(s),
                            onSelected: (v) => setState(
                              () => v ? _subjects.add(s) : _subjects.remove(s),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: scheme.primary, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _door
                                  ? '${_classes.length} sınıf seçili. Her sınıf için tek sayfa, sadece isimler (puan/yüzde yok).'
                                  : '${_classes.length} sınıf • ${_subjects.length} ders seçili. '
                              'Her sınıf ayrı sayfalarda, seçilen derslerin raporlarıyla basılır.',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _canPrint ? () => _run(false) : null,
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: const Text('PDF İndir'),
                  ),
                  if (_door)
                    TextButton.icon(
                      onPressed: _canPrint
                          ? () async {
                              setState(() => _busy = true);
                              try {
                                await OdakExcelService.saveDoorList(
                                  groups: widget.groups,
                                  examName: widget.examName,
                                  schoolName: widget.schoolName,
                                  classIds: Set<String>.from(_classes),
                                );
                                if (mounted) Navigator.pop(context);
                              } catch (e) {
                                if (mounted) {
                                  setState(() => _busy = false);
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Excel hazırlanamadı: $e')),
                                  );
                                }
                              }
                            }
                          : null,
                      icon: const Icon(Icons.table_chart_rounded, color: Colors.green),
                      label: const Text('Excel'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('Vazgeç'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _canPrint ? () => _run(true) : null,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print_rounded),
                    label: const Text('Yazdır'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool allSelected;
  final ValueChanged<bool> onToggleAll;
  final List<Widget> chips;

  const _Group({
    required this.title,
    required this.icon,
    required this.allSelected,
    required this.onToggleAll,
    required this.chips,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            TextButton(
              onPressed: () => onToggleAll(!allSelected),
              child: Text(allSelected ? 'Hiçbiri' : 'Tümünü seç'),
            ),
          ],
        ),
        Wrap(spacing: 8, runSpacing: 8, children: chips),
      ],
    );
  }
}
