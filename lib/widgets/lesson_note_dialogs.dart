import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/lesson_notes_service.dart';
import '../services/term_service.dart';

/// Not hedefi: sınıf (+ isteğe bağlı ders) ve açıklama.
class NoteTarget {
  NoteTarget({
    required this.classId,
    required this.className,
    required this.lessonId,
    required this.lessonName,
    required this.schoolTypeId,
    required this.comment,
  });
  final String classId;
  final String className;
  final String lessonId;
  final String lessonName;
  final String schoolTypeId;
  final String comment;
}

void _snack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : null),
  );
}

Future<void> openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Not sayfalarını gösteren görüntüleyici.
Future<void> showLessonNoteViewer(
  BuildContext context, {
  required String title,
  required List<String> pageUrls,
  required String pdfUrl,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final controller = PageController();
      int index = 0;
      return StatefulBuilder(
        builder: (ctx, setD) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (pdfUrl.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => openUrl(pdfUrl),
                          icon: const Icon(Icons.picture_as_pdf_rounded),
                          label: const Text('PDF aç'),
                        ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: pageUrls.isEmpty
                      ? const Center(child: Text('Sayfa bulunamadı.'))
                      : PageView.builder(
                          controller: controller,
                          itemCount: pageUrls.length,
                          onPageChanged: (i) => setD(() => index = i),
                          itemBuilder: (_, i) => InteractiveViewer(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Image.network(
                                pageUrls[i],
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Text('Görsel yüklenemedi'),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: index > 0
                            ? () => controller.previousPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              )
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Text(
                        '${pageUrls.isEmpty ? 0 : index + 1} / ${pageUrls.length}',
                      ),
                      IconButton(
                        onPressed: index < pageUrls.length - 1
                            ? () => controller.nextPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              )
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Sınıf (+ ders) seçtiren ortak diyalog.
Future<NoteTarget?> showNoteTargetPicker(
  BuildContext context, {
  required String institutionId,
  String schoolTypeId = '',
  List<String>? allowedClassIds,
  bool requireLesson = true,
  bool askMessage = false,
  String title = 'Sınıf ve ders seçin',
  String confirmLabel = 'Tamam',
}) {
  return showDialog<NoteTarget>(
    context: context,
    builder: (_) => _TargetPickerDialog(
      institutionId: institutionId,
      schoolTypeId: schoolTypeId,
      allowedClassIds: allowedClassIds,
      requireLesson: requireLesson,
      askMessage: askMessage,
      title: title,
      confirmLabel: confirmLabel,
    ),
  );
}

class _TargetPickerDialog extends StatefulWidget {
  const _TargetPickerDialog({
    required this.institutionId,
    required this.schoolTypeId,
    required this.allowedClassIds,
    required this.requireLesson,
    required this.askMessage,
    required this.title,
    required this.confirmLabel,
  });
  final String institutionId;
  final String schoolTypeId;
  final List<String>? allowedClassIds;
  final bool requireLesson;
  final bool askMessage;
  final String title;
  final String confirmLabel;

  @override
  State<_TargetPickerDialog> createState() => _TargetPickerDialogState();
}

class _TargetPickerDialogState extends State<_TargetPickerDialog> {
  bool _loading = true;
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _lessons = [];
  String? _classId;
  String? _lessonId;
  final _msg = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();
      String? termId;
      try {
        termId =
            await TermService().getSelectedTermId() ??
            await TermService().getActiveTermId();
      } catch (_) {}
      final allowed = widget.allowedClassIds;
      var list = snap.docs
          .where((d) => d.data()['isActive'] != false)
          .where((d) {
            if (termId == null || termId.isEmpty) return true;
            final t = (d.data()['termId'] ?? '').toString();
            return t.isEmpty || t == termId;
          })
          .where(
            (d) => allowed == null || allowed.isEmpty || allowed.contains(d.id),
          )
          .map((d) => {'id': d.id, ...d.data()})
          .toList();
      list.sort(
        (a, b) => (a['className'] ?? '').toString().compareTo(
          (b['className'] ?? '').toString(),
        ),
      );
      if (mounted) {
        setState(() {
          _classes = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadLessons(String classId) async {
    setState(() {
      _lessons = [];
      _lessonId = null;
    });
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('classId', isEqualTo: classId)
          .get();
      final uid = LessonNotesService.instance.uid;
      var docs = snap.docs.where((d) => d.data()['isActive'] != false).toList();
      if (uid != null) {
        final mine = docs
            .where(
              (d) => List<String>.from(
                d.data()['teacherIds'] ?? const [],
              ).contains(uid),
            )
            .toList();
        if (mine.isNotEmpty) docs = mine;
      }
      final seen = <String>{};
      final list = <Map<String, dynamic>>[];
      for (final d in docs) {
        final lid = (d.data()['lessonId'] ?? '').toString();
        if (lid.isEmpty || !seen.add(lid)) continue;
        list.add({
          'id': lid,
          'name': (d.data()['lessonName'] ?? 'Ders').toString(),
        });
      }
      list.sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
      if (mounted) setState(() => _lessons = list);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: _classId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Sınıf / Şube',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final c in _classes)
                          DropdownMenuItem(
                            value: c['id'].toString(),
                            child: Text((c['className'] ?? '').toString()),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() => _classId = v);
                        if (v != null) _loadLessons(v);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _lessonId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: widget.requireLesson
                            ? 'Ders'
                            : 'Ders (isteğe bağlı)',
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final l in _lessons)
                          DropdownMenuItem(
                            value: l['id'].toString(),
                            child: Text(l['name'].toString()),
                          ),
                      ],
                      onChanged: (v) => setState(() => _lessonId = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _msg,
                      maxLines: 3,
                      minLines: 1,
                      decoration: InputDecoration(
                        labelText: widget.askMessage
                            ? 'Mesaj / açıklama (isteğe bağlı)'
                            : 'Not açıklaması (isteğe bağlı)',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () {
            if (_classId == null) {
              _snack(context, 'Lütfen sınıf seçin.', error: true);
              return;
            }
            if (widget.requireLesson && _lessonId == null) {
              _snack(context, 'Lütfen ders seçin.', error: true);
              return;
            }
            final cls = _classes.firstWhere((c) => c['id'] == _classId);
            final lesson = _lessonId == null
                ? null
                : _lessons.firstWhere((l) => l['id'] == _lessonId);
            Navigator.pop(
              context,
              NoteTarget(
                classId: _classId!,
                className: (cls['className'] ?? '').toString(),
                lessonId: _lessonId ?? '',
                lessonName: lesson?['name']?.toString() ?? '',
                schoolTypeId: (cls['schoolTypeId'] ?? widget.schoolTypeId)
                    .toString(),
                comment: _msg.text.trim(),
              ),
            );
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Notu bir sınıf + derse "ders notu" olarak ekler.
Future<bool> attachNoteToClass(
  BuildContext context,
  LessonNote note, {
  required String institutionId,
  String schoolTypeId = '',
  List<String>? allowedClassIds,
  NoteTarget? fixedTarget,
}) async {
  final target =
      fixedTarget ??
      await showNoteTargetPicker(
        context,
        institutionId: institutionId,
        schoolTypeId: schoolTypeId,
        allowedClassIds: allowedClassIds,
        title: 'Derse ders notu olarak ekle',
        confirmLabel: 'Ekle',
      );
  if (target == null) return false;
  try {
    await LessonNotesService.instance.attachToClass(
      note: note,
      institutionId: institutionId,
      schoolTypeId: target.schoolTypeId,
      classId: target.classId,
      className: target.className,
      lessonId: target.lessonId,
      lessonName: target.lessonName,
      comment: target.comment,
    );
    if (context.mounted) {
      _snack(
        context,
        '"${note.title}" ${target.className} • ${target.lessonName} dersine eklendi.',
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) _snack(context, 'Eklenemedi: $e', error: true);
    return false;
  }
}

/// Notu şubeye duyuru olarak paylaşır.
Future<void> shareNoteAsAnnouncement(
  BuildContext context, {
  required String title,
  required String pdfUrl,
  required List<String> pageUrls,
  required String institutionId,
  String schoolTypeId = '',
  List<String>? allowedClassIds,
}) async {
  final target = await showNoteTargetPicker(
    context,
    institutionId: institutionId,
    schoolTypeId: schoolTypeId,
    allowedClassIds: allowedClassIds,
    requireLesson: false,
    askMessage: true,
    title: 'Duyuru olarak paylaş',
    confirmLabel: 'Duyuru Yayınla',
  );
  if (target == null) return;
  try {
    await LessonNotesService.instance.shareAsAnnouncement(
      title: title,
      pdfUrl: pdfUrl,
      pageUrls: pageUrls,
      classId: target.classId,
      className: target.className,
      schoolTypeId: target.schoolTypeId,
      message: target.comment,
    );
    if (context.mounted) {
      _snack(
        context,
        'Duyuru ${target.className} için yayınlandı (onay gerektiren okullarda onaya düşer).',
      );
    }
  } catch (e) {
    if (context.mounted)
      _snack(context, 'Duyuru oluşturulamadı: $e', error: true);
  }
}

/// Notu bir veya birden fazla sohbete mesaj olarak gönderir.
Future<void> shareNoteAsMessage(
  BuildContext context, {
  required String title,
  required String pdfUrl,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _MessageShareDialog(title: title, pdfUrl: pdfUrl),
  );
}

class _MessageShareDialog extends StatefulWidget {
  const _MessageShareDialog({required this.title, required this.pdfUrl});
  final String title;
  final String pdfUrl;

  @override
  State<_MessageShareDialog> createState() => _MessageShareDialogState();
}

class _MessageShareDialogState extends State<_MessageShareDialog> {
  bool _loading = true;
  bool _sending = false;
  List<MapEntry<String, String>> _convs = [];
  final Set<String> _selected = {};
  final _msg = TextEditingController();

  @override
  void initState() {
    super.initState();
    LessonNotesService.instance
        .myConversations()
        .then((v) {
          if (mounted) {
            setState(() {
              _convs = v;
              _loading = false;
            });
          }
        })
        .catchError((_) {
          if (mounted) setState(() => _loading = false);
        });
  }

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_selected.isEmpty) return;
    setState(() => _sending = true);
    int ok = 0;
    for (final id in _selected) {
      try {
        await LessonNotesService.instance.shareAsMessage(
          conversationId: id,
          title: widget.title,
          pdfUrl: widget.pdfUrl,
          message: _msg.text,
        );
        ok++;
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.pop(context);
    _snack(context, '$ok sohbete mesaj gönderildi.');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mesaj olarak gönder'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: _convs.isEmpty
                        ? const Center(
                            child: Text(
                              'Henüz sohbetiniz yok. Önce Haberleşme bölümünden bir sohbet başlatın.',
                            ),
                          )
                        : ListView(
                            children: [
                              for (final c in _convs)
                                CheckboxListTile(
                                  dense: true,
                                  value: _selected.contains(c.key),
                                  title: Text(
                                    c.value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onChanged: (v) => setState(() {
                                    if (v == true) {
                                      _selected.add(c.key);
                                    } else {
                                      _selected.remove(c.key);
                                    }
                                  }),
                                ),
                            ],
                          ),
                  ),
                  TextField(
                    controller: _msg,
                    maxLines: 2,
                    minLines: 1,
                    decoration: const InputDecoration(
                      labelText: 'Mesaj (isteğe bağlı)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton.icon(
          onPressed: _sending || _selected.isEmpty ? null : _send,
          icon: const Icon(Icons.send_rounded, size: 18),
          label: Text(
            _sending ? 'Gönderiliyor...' : 'Gönder (${_selected.length})',
          ),
        ),
      ],
    );
  }
}

/// Öğretmenin kayıtlı notlarının kütüphanesi.
Future<void> showLessonNoteLibrary(
  BuildContext context, {
  required String institutionId,
  String schoolTypeId = '',
  List<String>? allowedClassIds,
  void Function(LessonNote note)? onOpenInBoard,
  NoteTarget? fixedTarget,
  VoidCallback? onChanged,
  bool attachOnly = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _LibraryDialog(
      institutionId: institutionId,
      schoolTypeId: schoolTypeId,
      allowedClassIds: allowedClassIds,
      onOpenInBoard: onOpenInBoard,
      fixedTarget: fixedTarget,
      onChanged: onChanged,
      attachOnly: attachOnly,
    ),
  );
}

class _LibraryDialog extends StatefulWidget {
  const _LibraryDialog({
    required this.institutionId,
    required this.schoolTypeId,
    required this.allowedClassIds,
    required this.onOpenInBoard,
    required this.fixedTarget,
    required this.onChanged,
    required this.attachOnly,
  });
  final String institutionId;
  final String schoolTypeId;
  final List<String>? allowedClassIds;
  final void Function(LessonNote note)? onOpenInBoard;
  final NoteTarget? fixedTarget;
  final VoidCallback? onChanged;
  final bool attachOnly;

  @override
  State<_LibraryDialog> createState() => _LibraryDialogState();
}

class _LibraryDialogState extends State<_LibraryDialog> {
  bool _loading = true;
  String? _error;
  List<LessonNote> _notes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await LessonNotesService.instance.listMyNotes(
        widget.institutionId,
      );
      if (mounted) setState(() => _notes = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  Widget _chipBtn(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy HH:mm');
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.folder_special_rounded,
                    color: Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.fixedTarget != null
                          ? 'Notlarımdan derse ekle'
                          : 'Not Kütüphanem',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(_error!),
                      ),
                    )
                  : _notes.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Henüz kayıtlı notunuz yok. Akıllı Tahta > Notlar sekmesinden dosya ekleyip "Notu Kaydet" ile oluşturabilirsiniz.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(14),
                      itemCount: _notes.length,
                      itemBuilder: (_, i) {
                        final n = _notes[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: () => showLessonNoteViewer(
                                    context,
                                    title: n.title,
                                    pageUrls: n.pageUrls,
                                    pdfUrl: n.pdfUrl,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 70,
                                      height: 92,
                                      child: n.coverUrl.isEmpty
                                          ? const ColoredBox(
                                              color: Color(0xFFE2E8F0),
                                            )
                                          : Image.network(
                                              n.coverUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  const ColoredBox(
                                                    color: Color(0xFFE2E8F0),
                                                    child: Icon(
                                                      Icons.description_rounded,
                                                    ),
                                                  ),
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        n.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${n.pageCount} sayfa • ${df.format(n.createdAt)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          _chipBtn(
                                            Icons.visibility_rounded,
                                            'Görüntüle',
                                            () => showLessonNoteViewer(
                                              context,
                                              title: n.title,
                                              pageUrls: n.pageUrls,
                                              pdfUrl: n.pdfUrl,
                                            ),
                                          ),
                                          if (widget.onOpenInBoard != null)
                                            _chipBtn(
                                              Icons.draw_rounded,
                                              'Tahtada Aç',
                                              () {
                                                Navigator.pop(context);
                                                widget.onOpenInBoard!(n);
                                              },
                                              color: const Color(0xFF2563EB),
                                            ),
                                          _chipBtn(
                                            Icons.library_add_rounded,
                                            'Derse Ekle',
                                            () async {
                                              final ok =
                                                  await attachNoteToClass(
                                                    context,
                                                    n,
                                                    institutionId:
                                                        widget.institutionId,
                                                    schoolTypeId:
                                                        widget.schoolTypeId,
                                                    allowedClassIds:
                                                        widget.allowedClassIds,
                                                    fixedTarget:
                                                        widget.fixedTarget,
                                                  );
                                              if (ok) {
                                                widget.onChanged?.call();
                                                if (widget.fixedTarget !=
                                                        null &&
                                                    context.mounted) {
                                                  Navigator.pop(context);
                                                }
                                              }
                                            },
                                            color: const Color(0xFF059669),
                                          ),
                                          if (!widget.attachOnly) ...[
                                            _chipBtn(
                                              Icons.campaign_rounded,
                                              'Duyuru',
                                              () => shareNoteAsAnnouncement(
                                                context,
                                                title: n.title,
                                                pdfUrl: n.pdfUrl,
                                                pageUrls: n.pageUrls,
                                                institutionId:
                                                    widget.institutionId,
                                                schoolTypeId:
                                                    widget.schoolTypeId,
                                                allowedClassIds:
                                                    widget.allowedClassIds,
                                              ),
                                              color: const Color(0xFFEA580C),
                                            ),
                                            _chipBtn(
                                              Icons.chat_rounded,
                                              'Mesaj',
                                              () => shareNoteAsMessage(
                                                context,
                                                title: n.title,
                                                pdfUrl: n.pdfUrl,
                                              ),
                                              color: const Color(0xFF7C3AED),
                                            ),
                                            _chipBtn(
                                              Icons.delete_outline_rounded,
                                              'Sil',
                                              () async {
                                                final ok = await showDialog<bool>(
                                                  context: context,
                                                  builder: (ctx) => AlertDialog(
                                                    title: const Text(
                                                      'Not silinsin mi?',
                                                    ),
                                                    content: Text(
                                                      '"${n.title}" kütüphanenizden kaldırılır. Derslere eklenmiş kopyalar kalır.',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              ctx,
                                                              false,
                                                            ),
                                                        child: const Text(
                                                          'Vazgeç',
                                                        ),
                                                      ),
                                                      FilledButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              ctx,
                                                              true,
                                                            ),
                                                        child: const Text(
                                                          'Sil',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                if (ok == true) {
                                                  await LessonNotesService
                                                      .instance
                                                      .deleteNote(n);
                                                  _load();
                                                }
                                              },
                                              color: Colors.red,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Notu kaydet ve paylaş" diyaloğunun sonucu.
class SaveShareRequest {
  SaveShareRequest({
    required this.title,
    required this.pages,
    required this.attach,
    required this.announce,
    required this.message,
    required this.pdfFile,
    required this.pngFiles,
    this.target,
  });

  final String title;

  /// Seçilen sayfaların (0 tabanlı) sırası.
  final List<int> pages;
  final bool attach;
  final bool announce;
  final bool message;
  final bool pdfFile;
  final bool pngFiles;
  final NoteTarget? target;

  /// Bulut kaydı (Storage + Firestore) gerektiren bir işlem var mı?
  bool get needsCloud => attach || announce || message;
}

/// Sayfa seçimi + hedef (şube/ders) + paylaşım biçimi seçtiren ortak diyalog.
Future<SaveShareRequest?> showSaveShareDialog(
  BuildContext context, {
  required String institutionId,
  String schoolTypeId = '',
  List<String>? allowedClassIds,
  required String defaultTitle,
  required List<ui.Image?> thumbs,
  required List<String> labels,
  required int currentPage,
}) {
  return showDialog<SaveShareRequest>(
    context: context,
    builder: (_) => _SaveShareDialog(
      institutionId: institutionId,
      schoolTypeId: schoolTypeId,
      allowedClassIds: allowedClassIds,
      defaultTitle: defaultTitle,
      thumbs: thumbs,
      labels: labels,
      currentPage: currentPage,
    ),
  );
}

class _SaveShareDialog extends StatefulWidget {
  const _SaveShareDialog({
    required this.institutionId,
    required this.schoolTypeId,
    required this.allowedClassIds,
    required this.defaultTitle,
    required this.thumbs,
    required this.labels,
    required this.currentPage,
  });
  final String institutionId;
  final String schoolTypeId;
  final List<String>? allowedClassIds;
  final String defaultTitle;
  final List<ui.Image?> thumbs;
  final List<String> labels;
  final int currentPage;

  @override
  State<_SaveShareDialog> createState() => _SaveShareDialogState();
}

class _SaveShareDialogState extends State<_SaveShareDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.defaultTitle,
  );
  final _comment = TextEditingController();
  late final Set<int> _sel = {for (int i = 0; i < widget.labels.length; i++) i};
  bool _attach = true;
  bool _announce = false;
  bool _message = false;
  bool _pdfFile = false;
  bool _pngFiles = false;

  bool _loading = true;
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _lessons = [];
  String? _classId;
  String? _lessonId;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  @override
  void dispose() {
    _title.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();
      String? termId;
      try {
        termId =
            await TermService().getSelectedTermId() ??
            await TermService().getActiveTermId();
      } catch (_) {}
      final allowed = widget.allowedClassIds;
      final list = snap.docs
          .where((d) => d.data()['isActive'] != false)
          .where((d) {
            if (termId == null || termId.isEmpty) return true;
            final t = (d.data()['termId'] ?? '').toString();
            return t.isEmpty || t == termId;
          })
          .where(
            (d) => allowed == null || allowed.isEmpty || allowed.contains(d.id),
          )
          .map((d) => {'id': d.id, ...d.data()})
          .toList();
      list.sort(
        (a, b) => (a['className'] ?? '').toString().compareTo(
          (b['className'] ?? '').toString(),
        ),
      );
      if (mounted) {
        setState(() {
          _classes = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadLessons(String classId) async {
    setState(() {
      _lessons = [];
      _lessonId = null;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();
      final uid = LessonNotesService.instance.uid;
      var docs = snap.docs
          .where((d) => d.data()['isActive'] != false)
          .where((d) => (d.data()['classId'] ?? '').toString() == classId)
          .toList();
      if (uid != null) {
        final mine = docs
            .where(
              (d) => List<String>.from(
                d.data()['teacherIds'] ?? const [],
              ).contains(uid),
            )
            .toList();
        if (mine.isNotEmpty) docs = mine;
      }
      final seen = <String>{};
      final list = <Map<String, dynamic>>[];
      for (final d in docs) {
        final lid = (d.data()['lessonId'] ?? '').toString();
        if (lid.isEmpty || !seen.add(lid)) continue;
        list.add({
          'id': lid,
          'name': (d.data()['lessonName'] ?? 'Ders').toString(),
        });
      }
      list.sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
      if (mounted) setState(() => _lessons = list);
    } catch (_) {}
  }

  bool get _needsClass => _attach || _announce;

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _snack(context, 'Not başlığı yazın.', error: true);
      return;
    }
    if (_sel.isEmpty) {
      _snack(context, 'En az bir sayfa seçin.', error: true);
      return;
    }
    if (!(_attach || _announce || _message || _pdfFile || _pngFiles)) {
      _snack(context, 'En az bir işlem seçin.', error: true);
      return;
    }
    NoteTarget? target;
    if (_needsClass) {
      if (_classId == null) {
        _snack(context, 'Lütfen sınıf / şube seçin.', error: true);
        return;
      }
      if (_attach && _lessonId == null) {
        _snack(
          context,
          'Ders notu olarak eklemek için ders seçin.',
          error: true,
        );
        return;
      }
      final cls = _classes.firstWhere((c) => c['id'] == _classId);
      final lesson = _lessonId == null
          ? null
          : _lessons.firstWhere((l) => l['id'] == _lessonId);
      target = NoteTarget(
        classId: _classId!,
        className: (cls['className'] ?? '').toString(),
        lessonId: _lessonId ?? '',
        lessonName: lesson?['name']?.toString() ?? '',
        schoolTypeId: (cls['schoolTypeId'] ?? widget.schoolTypeId).toString(),
        comment: _comment.text.trim(),
      );
    }
    Navigator.pop(
      context,
      SaveShareRequest(
        title: title,
        pages: _sel.toList()..sort(),
        attach: _attach,
        announce: _announce,
        message: _message,
        pdfFile: _pdfFile,
        pngFiles: _pngFiles,
        target: target,
      ),
    );
  }

  Widget _pageCard(int i) {
    final on = _sel.contains(i);
    final img = widget.thumbs[i];
    final cur = i == widget.currentPage;
    return GestureDetector(
      onTap: () => setState(() => on ? _sel.remove(i) : _sel.add(i)),
      child: Container(
        width: 118,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFDBEAFE) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: on ? const Color(0xFF2563EB) : Colors.grey.shade300,
            width: on ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: Colors.white,
                      child: img == null
                          ? const SizedBox.shrink()
                          : RawImage(image: img, fit: BoxFit.contain),
                    ),
                  ),
                  Positioned(
                    left: 2,
                    top: 2,
                    child: Icon(
                      on
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: on ? const Color(0xFF2563EB) : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              cur ? '${widget.labels[i]} (açık)' : widget.labels[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _check(
    bool value,
    ValueChanged<bool> onChanged,
    IconData icon,
    Color color,
    String title,
    String sub,
  ) {
    return CheckboxListTile(
      value: value,
      onChanged: (v) => setState(() => onChanged(v ?? false)),
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      secondary: Icon(icon, color: color),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.labels.length;
    return AlertDialog(
      title: const Text('Notu kaydet ve paylaş'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Not başlığı',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Sayfalar (${_sel.length}/$total seçili)',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(
                      () => _sel
                        ..clear()
                        ..addAll([for (int i = 0; i < total; i++) i]),
                    ),
                    child: const Text('Tümü'),
                  ),
                  TextButton(
                    onPressed: () => setState(
                      () => _sel
                        ..clear()
                        ..add(widget.currentPage),
                    ),
                    child: const Text('Sadece açık'),
                  ),
                ],
              ),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: total,
                  itemBuilder: (_, i) => _pageCard(i),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Ne yapılsın?',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              _check(
                _attach,
                (v) => _attach = v,
                Icons.library_add_rounded,
                const Color(0xFF059669),
                'Derse ders notu olarak ekle',
                'Seçtiğiniz şube ve dersin "Ders Notları" sekmesinde görünür',
              ),
              _check(
                _announce,
                (v) => _announce = v,
                Icons.campaign_rounded,
                const Color(0xFFEA580C),
                'Şubeye duyuru olarak paylaş',
                'Not PDF bağlantısıyla duyuru olur',
              ),
              _check(
                _message,
                (v) => _message = v,
                Icons.chat_rounded,
                const Color(0xFF7C3AED),
                'Mesaj olarak gönder',
                'Kaydedince sohbet seçimi açılır',
              ),
              _check(
                _pdfFile,
                (v) => _pdfFile = v,
                Icons.picture_as_pdf_rounded,
                const Color(0xFFDC2626),
                'PDF dosyası olarak indir',
                'Seçili sayfalar tek PDF dosyası',
              ),
              _check(
                _pngFiles,
                (v) => _pngFiles = v,
                Icons.image_rounded,
                const Color(0xFF0284C7),
                'Resim (PNG) olarak indir',
                'Her seçili sayfa ayrı resim dosyası',
              ),
              if (_needsClass) ...[
                const Divider(height: 20),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    initialValue: _classId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Sınıf / Şube',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final c in _classes)
                        DropdownMenuItem(
                          value: c['id'].toString(),
                          child: Text((c['className'] ?? '').toString()),
                        ),
                    ],
                    onChanged: (v) {
                      setState(() => _classId = v);
                      if (v != null) _loadLessons(v);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('lesson_${_classId}_${_lessons.length}'),
                    initialValue: _lessonId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: _attach ? 'Ders' : 'Ders (isteğe bağlı)',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final l in _lessons)
                        DropdownMenuItem(
                          value: l['id'].toString(),
                          child: Text(l['name'].toString()),
                        ),
                    ],
                    onChanged: (v) => setState(() => _lessonId = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _comment,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Açıklama / mesaj (isteğe bağlı)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Kaydet'),
        ),
      ],
    );
  }
}
