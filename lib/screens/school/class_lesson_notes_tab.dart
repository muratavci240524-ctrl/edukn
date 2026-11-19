import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/lesson_notes_service.dart';
import '../../widgets/lesson_note_dialogs.dart';
import 'tools/smart_whiteboard/smart_whiteboard_screen.dart';

/// Ders sayfasındaki "Ders Notları" sekmesi: bu sınıf + derse eklenmiş notlar.
class ClassLessonNotesTab extends StatefulWidget {
  const ClassLessonNotesTab({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.classId,
    required this.className,
    required this.lessonId,
    required this.lessonName,
  });

  final String institutionId;
  final String schoolTypeId;
  final String classId;
  final String className;
  final String lessonId;
  final String lessonName;

  @override
  State<ClassLessonNotesTab> createState() => _ClassLessonNotesTabState();
}

class _ClassLessonNotesTabState extends State<ClassLessonNotesTab> {
  bool _loading = true;
  String? _error;
  List<LessonNoteLink> _links = [];

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
      final list = await LessonNotesService.instance.listClassNotes(
        institutionId: widget.institutionId,
        classId: widget.classId,
        lessonId: widget.lessonId,
      );
      if (mounted) setState(() => _links = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  NoteTarget get _fixedTarget => NoteTarget(
    classId: widget.classId,
    className: widget.className,
    lessonId: widget.lessonId,
    lessonName: widget.lessonName,
    schoolTypeId: widget.schoolTypeId,
    comment: '',
  );

  Future<void> _addFromLibrary() async {
    await showLessonNoteLibrary(
      context,
      institutionId: widget.institutionId,
      schoolTypeId: widget.schoolTypeId,
      fixedTarget: _fixedTarget,
      attachOnly: true,
      onChanged: _load,
    );
    _load();
  }

  Future<void> _openBoard() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SmartWhiteboardScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy HH:mm');
    final me = LessonNotesService.instance.uid;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _addFromLibrary,
                icon: const Icon(Icons.library_add_rounded),
                label: const Text('Notlarımdan Ekle'),
              ),
              OutlinedButton.icon(
                onPressed: _openBoard,
                icon: const Icon(Icons.draw_rounded),
                label: const Text('Akıllı Tahtada Not Hazırla'),
              ),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
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
              : _links.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.note_alt_outlined,
                          size: 56,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${widget.className} • ${widget.lessonName} için henüz ders notu eklenmemiş.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _links.length,
                  itemBuilder: (_, i) {
                    final l = _links[i];
                    final cover = l.pageUrls.isNotEmpty ? l.pageUrls.first : '';
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
                                title: l.title,
                                pageUrls: l.pageUrls,
                                pdfUrl: l.pdfUrl,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 64,
                                  height: 84,
                                  child: cover.isEmpty
                                      ? const ColoredBox(
                                          color: Color(0xFFE2E8F0),
                                        )
                                      : Image.network(
                                          cover,
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${l.pageUrls.length} sayfa • ${l.teacherName} • ${df.format(l.createdAt)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  if (l.comment.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        l.comment,
                                        style: const TextStyle(fontSize: 12.5),
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      ActionChip(
                                        avatar: const Icon(
                                          Icons.visibility_rounded,
                                          size: 16,
                                        ),
                                        label: const Text(
                                          'Görüntüle',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => showLessonNoteViewer(
                                          context,
                                          title: l.title,
                                          pageUrls: l.pageUrls,
                                          pdfUrl: l.pdfUrl,
                                        ),
                                      ),
                                      ActionChip(
                                        avatar: const Icon(
                                          Icons.campaign_rounded,
                                          size: 16,
                                          color: Color(0xFFEA580C),
                                        ),
                                        label: const Text(
                                          'Duyuru',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () =>
                                            shareNoteAsAnnouncement(
                                              context,
                                              title: l.title,
                                              pdfUrl: l.pdfUrl,
                                              pageUrls: l.pageUrls,
                                              institutionId:
                                                  widget.institutionId,
                                              schoolTypeId: widget.schoolTypeId,
                                              allowedClassIds: [widget.classId],
                                            ),
                                      ),
                                      ActionChip(
                                        avatar: const Icon(
                                          Icons.chat_rounded,
                                          size: 16,
                                          color: Color(0xFF7C3AED),
                                        ),
                                        label: const Text(
                                          'Mesaj',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => shareNoteAsMessage(
                                          context,
                                          title: l.title,
                                          pdfUrl: l.pdfUrl,
                                        ),
                                      ),
                                      if (me == null || l.teacherId == me)
                                        ActionChip(
                                          avatar: const Icon(
                                            Icons.link_off_rounded,
                                            size: 16,
                                            color: Colors.red,
                                          ),
                                          label: const Text(
                                            'Dersten Kaldır',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () async {
                                            await LessonNotesService.instance
                                                .deleteLink(l.id);
                                            _load();
                                          },
                                        ),
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
    );
  }
}
