import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../models/school/daily_report_models.dart';
import '../../../services/daily_report_service.dart';

/// Tüm Günlük Rapor alt pencerelerini ekranın TAM ALTINA sıfır oturacak şekilde açar.
Future<T?> showDailyReportBottomSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext sheetContext) builder,
  double maxWidth = 760,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    enableDrag: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.52),
    constraints: const BoxConstraints(maxWidth: double.infinity),
    builder: (ctx) => Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: builder(ctx),
      ),
    ),
  );
}

class _DailySheetFrame extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color accentColor;
  final Widget child;
  final Widget? footer;
  final double maxHeightFactor;

  const _DailySheetFrame({
    required this.title,
    this.subtitle,
    required this.icon,
    this.accentColor = const Color(0xFF4F46E5),
    required this.child,
    this.footer,
    this.maxHeightFactor = 0.92,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboardInset = mq.viewInsets.bottom;
    final bottomSafe = mq.padding.bottom;
    final maxH = mq.size.height * maxHeightFactor;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Color(0x290F172A),
                blurRadius: 36,
                offset: Offset(0, -10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Material(
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 16, 14),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(icon, color: accentColor, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: -0.2,
                                ),
                              ),
                              if (subtitle != null &&
                                  subtitle!.trim().isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  subtitle!,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFF64748B),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFF1F5F9),
                            foregroundColor: const Color(0xFF475569),
                            minimumSize: const Size(36, 36),
                            padding: EdgeInsets.zero,
                          ),
                          icon: const Icon(Icons.close_rounded, size: 19),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        22,
                        18,
                        22,
                        footer == null ? 24 + bottomSafe : 18,
                      ),
                      child: child,
                    ),
                  ),
                  if (footer != null)
                    Container(
                      padding: EdgeInsets.fromLTRB(
                        22,
                        14,
                        22,
                        keyboardInset > 0 ? 14 : 16 + bottomSafe,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        border: Border(
                          top: BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      child: footer!,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModernInput extends StatelessWidget {
  final TextEditingController controller;
  final String? label;
  final String? trailing;
  final String? hint;
  final IconData? icon;
  final Color accent;
  final int maxLines;

  const _ModernInput({
    required this.controller,
    this.label,
    this.trailing,
    this.hint,
    this.icon,
    this.accent = const Color(0xFF4F46E5),
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  label!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF94A3B8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(
            fontSize: 13.8,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: Color(0xFF94A3B8),
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: maxLines > 1 ? 13 : 13,
            ),
            prefixIcon: icon == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(left: 10, right: 8),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 16, color: accent),
                    ),
                  ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 48, minHeight: 34),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFD5DFEC), width: 1.2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFD5DFEC), width: 1.2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: accent, width: 1.8),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 1. HIZLI SINIF ETKİNLİĞİ / BRANŞ DERSİ / KİTAP / GEZİ EKLEME SHEET'İ
// ═════════════════════════════════════════════════════════════════════════════

class QuickClassActivitySheet extends StatefulWidget {
  final String institutionId;
  final String schoolDocId;
  final String dateKey;
  final String className;
  final List<DailyReportStudentInfo> classStudents;
  final Map<String, DailyReportModel> existingReports;
  final String actorUid;
  final String actorName;

  const QuickClassActivitySheet({
    super.key,
    required this.institutionId,
    required this.schoolDocId,
    required this.dateKey,
    required this.className,
    required this.classStudents,
    required this.existingReports,
    required this.actorUid,
    required this.actorName,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String institutionId,
    required String schoolDocId,
    required String dateKey,
    required String className,
    required List<DailyReportStudentInfo> classStudents,
    required Map<String, DailyReportModel> existingReports,
    required String actorUid,
    required String actorName,
  }) {
    return showDailyReportBottomSheet<bool>(
      context: context,
      maxWidth: 720,
      builder: (_) => QuickClassActivitySheet(
        institutionId: institutionId,
        schoolDocId: schoolDocId,
        dateKey: dateKey,
        className: className,
        classStudents: classStudents,
        existingReports: existingReports,
        actorUid: actorUid,
        actorName: actorName,
      ),
    );
  }

  @override
  State<QuickClassActivitySheet> createState() =>
      _QuickClassActivitySheetState();
}

class _QuickClassActivitySheetState extends State<QuickClassActivitySheet> {
  final _service = DailyReportService();
  String _category = 'book';
  late final TextEditingController _titleCtrl;
  final _descCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();
  String _participation = 'enthusiastic';
  String _photoUrl = '';
  bool _uploadingPhoto = false;
  bool _saving = false;
  late Set<String> _selectedStudentIds;
  bool _showStudentSelector = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(
      text: DailyReportCatalog.activityMeta(_category).title,
    );
    _timeCtrl.text = DateFormat('HH:mm').format(DateTime.now());
    _selectedStudentIds = widget.classStudents.map((s) => s.id).toSet();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _timeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    setState(() => _uploadingPhoto = true);
    try {
      if (!kIsWeb) {
        final picker = ImagePicker();
        final img = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 78,
        );
        if (img != null) {
          final bytes = await img.readAsBytes();
          final url = await _service.uploadActivityPhoto(
            schoolDocId: widget.schoolDocId,
            dateKey: widget.dateKey,
            bytes: bytes,
            fileName: img.name,
          );
          if (mounted) setState(() => _photoUrl = url);
        }
      } else {
        final res = await FilePicker.pickFiles(
          type: FileType.image,
          withData: true,
        );
        if (res != null &&
            res.files.isNotEmpty &&
            res.files.first.bytes != null) {
          final f = res.files.first;
          final url = await _service.uploadActivityPhoto(
            schoolDocId: widget.schoolDocId,
            dateKey: widget.dateKey,
            bytes: f.bytes!,
            fileName: f.name,
          );
          if (mounted) setState(() => _photoUrl = url);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotoğraf yüklenemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty && _descCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen etkinlik başlığı veya açıklaması giriniz.')),
      );
      return;
    }
    final targets = widget.classStudents
        .where((s) => _selectedStudentIds.contains(s.id))
        .toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('En az bir öğrenci seçmelisiniz.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final meta = DailyReportCatalog.activityMeta(_category);
      final activity = DailyActivityItemModel(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        category: _category,
        title: _titleCtrl.text.trim().isNotEmpty
            ? _titleCtrl.text.trim()
            : meta.title,
        description: _descCtrl.text.trim(),
        timeLabel: _timeCtrl.text.trim(),
        participation: _participation,
        photoUrl: _photoUrl,
        teacherName: widget.actorName,
        createdAt: DateTime.now(),
      );

      await _service.applyBulkClassReport(
        institutionId: widget.institutionId,
        schoolDocId: widget.schoolDocId,
        dateKey: widget.dateKey,
        targetStudents: targets,
        existingByStudentId: widget.existingReports,
        actorUid: widget.actorUid,
        actorName: widget.actorName,
        newActivitiesToAppend: [activity],
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Etkinlik kaydedilemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeMeta = DailyReportCatalog.activityMeta(_category);

    return _DailySheetFrame(
      title: 'Sınıfa Etkinlik / Branş Dersi Ekle',
      subtitle:
          '${widget.className} • Kitap okuma, İngilizce, gezi veya sanat akışını anlık velilere yansıtın',
      icon: Icons.auto_awesome_rounded,
      accentColor: activeMeta.color,
      footer: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: _saving ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: activeMeta.color,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send_rounded, size: 18),
          label: Text(
            _saving
                ? 'Kaydediliyor...'
                : 'Etkinliği ${_selectedStudentIds.length} Öğrencinin Karnesine Ekle',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Etkinlik / Ders Türü Seçin',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: DailyReportCatalog.activityCategories.map((c) {
              final selected = _category == c.key;
              return InkWell(
                onTap: () {
                  final prevDefault =
                      DailyReportCatalog.activityMeta(_category).title;
                  setState(() {
                    _category = c.key;
                    if (_titleCtrl.text.trim().isEmpty ||
                        _titleCtrl.text.trim() == prevDefault) {
                      _titleCtrl.text = c.title;
                    }
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? c.color.withValues(alpha: 0.14)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? c.color : const Color(0xFFE2E8F0),
                      width: selected ? 1.6 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(c.emoji, style: const TextStyle(fontSize: 15)),
                      const SizedBox(width: 6),
                      Text(
                        c.title,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                          color: selected ? c.color : const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _ModernInput(
                  controller: _titleCtrl,
                  label: 'Etkinlik / Ders Başlığı',
                  hint: activeMeta.title,
                  icon: activeMeta.icon,
                  accent: activeMeta.color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: _ModernInput(
                  controller: _timeCtrl,
                  label: 'Saat',
                  hint: '10:30',
                  icon: Icons.schedule_rounded,
                  accent: activeMeta.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ModernInput(
            controller: _descCtrl,
            label: 'Neler Yapıldı? (Veliye Görünecek Açıklama)',
            hint: activeMeta.hint,
            icon: Icons.notes_rounded,
            accent: activeMeta.color,
            maxLines: 3,
          ),
          const SizedBox(height: 14),
          const Text(
            'Katılım Durumu',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: DailyReportCatalog.participationLevels.map((p) {
              final sel = _participation == p.key;
              return ChoiceChip(
                label: Text(p.label),
                selected: sel,
                onSelected: (_) => setState(() => _participation = p.key),
                selectedColor: p.color.withValues(alpha: 0.16),
                backgroundColor: const Color(0xFFF8FAFC),
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                  color: sel ? p.color : const Color(0xFF475569),
                ),
                side: BorderSide(
                  color: sel ? p.color : const Color(0xFFE2E8F0),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          // Opsiyonel Fotoğraf Ekleme
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _uploadingPhoto ? null : _pickPhoto,
                style: OutlinedButton.styleFrom(
                  foregroundColor: activeMeta.color,
                  side: BorderSide(
                    color: activeMeta.color.withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                ),
                icon: _uploadingPhoto
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_a_photo_rounded, size: 17),
                label: Text(
                  _photoUrl.isEmpty
                      ? 'Etkinlik Fotoğrafı Ekle (Opsiyonel)'
                      : 'Fotoğraf Eklendi (Değiştir)',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_photoUrl.isNotEmpty) ...[
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    _photoUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _photoUrl = ''),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          // Öğrenci Seçimi (Varsayılan Tüm Sınıf)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: () => setState(
                    () => _showStudentSelector = !_showStudentSelector,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.groups_rounded,
                        color: Color(0xFF4F46E5),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _selectedStudentIds.length ==
                                  widget.classStudents.length
                              ? 'Tüm Sınıfa Uygulanacak (${widget.classStudents.length} Öğrenci)'
                              : 'Seçili ${_selectedStudentIds.length} / ${widget.classStudents.length} Öğrenciye Uygulanacak',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      Text(
                        _showStudentSelector ? 'Gizle' : 'Öğrenci Seç / Çıkar',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _showStudentSelector
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: const Color(0xFF4F46E5),
                      ),
                    ],
                  ),
                ),
                if (_showStudentSelector) ...[
                  const Divider(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => setState(() {
                          _selectedStudentIds =
                              widget.classStudents.map((s) => s.id).toSet();
                        }),
                        child: const Text('Tümünü Seç'),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _selectedStudentIds.clear()),
                        child: const Text('Temizle'),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: widget.classStudents.map((st) {
                      final sel = _selectedStudentIds.contains(st.id);
                      return FilterChip(
                        label: Text(st.fullName),
                        selected: sel,
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _selectedStudentIds.add(st.id);
                            } else {
                              _selectedStudentIds.remove(st.id);
                            }
                          });
                        },
                        selectedColor: const Color(0xFFE0E7FF),
                        checkmarkColor: const Color(0xFF4338CA),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          color: sel
                              ? const Color(0xFF312E81)
                              : const Color(0xFF475569),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 2. TÜM SINIFA TOPLU GÜNLÜK KARNE GİRİŞ SHEET'İ
// ═════════════════════════════════════════════════════════════════════════════

class BulkClassDailyReportSheet extends StatefulWidget {
  final String institutionId;
  final String schoolDocId;
  final String dateKey;
  final String className;
  final List<DailyReportStudentInfo> classStudents;
  final Map<String, DailyReportModel> existingReports;
  final DailyReportConfigModel config;
  final String actorUid;
  final String actorName;

  const BulkClassDailyReportSheet({
    super.key,
    required this.institutionId,
    required this.schoolDocId,
    required this.dateKey,
    required this.className,
    required this.classStudents,
    required this.existingReports,
    required this.config,
    required this.actorUid,
    required this.actorName,
  });

  static Future<int?> show(
    BuildContext context, {
    required String institutionId,
    required String schoolDocId,
    required String dateKey,
    required String className,
    required List<DailyReportStudentInfo> classStudents,
    required Map<String, DailyReportModel> existingReports,
    required DailyReportConfigModel config,
    required String actorUid,
    required String actorName,
  }) {
    return showDailyReportBottomSheet<int>(
      context: context,
      maxWidth: 780,
      builder: (_) => BulkClassDailyReportSheet(
        institutionId: institutionId,
        schoolDocId: schoolDocId,
        dateKey: dateKey,
        className: className,
        classStudents: classStudents,
        existingReports: existingReports,
        config: config,
        actorUid: actorUid,
        actorName: actorName,
      ),
    );
  }

  @override
  State<BulkClassDailyReportSheet> createState() =>
      _BulkClassDailyReportSheetState();
}

class _BulkClassDailyReportSheetState extends State<BulkClassDailyReportSheet> {
  final _service = DailyReportService();
  bool _saving = false;

  late Set<String> _selectedStudentIds;
  bool _showStudentFilter = false;

  // Seçilen alanlar (Boş bırakılanlar mevcut öğrenci verisini ezmez!)
  String _mood = '';
  String _socialHarmony = '';

  String _breakfastStatus = '';
  final _breakfastNoteCtrl = TextEditingController();

  String _lunchStatus = '';
  final _lunchNoteCtrl = TextEditingController();

  String _snackStatus = '';
  final _snackNoteCtrl = TextEditingController();

  String _waterIntake = '';

  String _sleepStatus = '';
  final _sleepDurationCtrl = TextEditingController();
  final _sleepNoteCtrl = TextEditingController();

  final Set<String> _selfCareTags = {};
  final Set<String> _neededItems = {};
  final _sharedNoteCtrl = TextEditingController();
  bool _overwriteNotes = false;

  @override
  void initState() {
    super.initState();
    _selectedStudentIds = widget.classStudents.map((s) => s.id).toSet();
  }

  @override
  void dispose() {
    _breakfastNoteCtrl.dispose();
    _lunchNoteCtrl.dispose();
    _snackNoteCtrl.dispose();
    _sleepDurationCtrl.dispose();
    _sleepNoteCtrl.dispose();
    _sharedNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyBulk() async {
    final targets = widget.classStudents
        .where((s) => _selectedStudentIds.contains(s.id))
        .toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir öğrenci seçin.')),
      );
      return;
    }

    final hasAnything = _mood.isNotEmpty ||
        _socialHarmony.isNotEmpty ||
        _breakfastStatus.isNotEmpty ||
        _lunchStatus.isNotEmpty ||
        _snackStatus.isNotEmpty ||
        _waterIntake.isNotEmpty ||
        _sleepStatus.isNotEmpty ||
        _selfCareTags.isNotEmpty ||
        _neededItems.isNotEmpty ||
        _sharedNoteCtrl.text.trim().isNotEmpty;

    if (!hasAnything) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Uygulamak için en az bir öğün, uyku veya durum seçiniz.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final count = await _service.applyBulkClassReport(
        institutionId: widget.institutionId,
        schoolDocId: widget.schoolDocId,
        dateKey: widget.dateKey,
        targetStudents: targets,
        existingByStudentId: widget.existingReports,
        actorUid: widget.actorUid,
        actorName: widget.actorName,
        mood: _mood.isNotEmpty ? _mood : null,
        socialHarmony: _socialHarmony.isNotEmpty ? _socialHarmony : null,
        breakfast: _breakfastStatus.isNotEmpty
            ? MealEntryModel(
                status: _breakfastStatus,
                menuOrNote: _breakfastNoteCtrl.text,
              )
            : null,
        lunch: _lunchStatus.isNotEmpty
            ? MealEntryModel(
                status: _lunchStatus,
                menuOrNote: _lunchNoteCtrl.text,
              )
            : null,
        snack: _snackStatus.isNotEmpty
            ? MealEntryModel(
                status: _snackStatus,
                menuOrNote: _snackNoteCtrl.text,
              )
            : null,
        waterIntake: _waterIntake.isNotEmpty ? _waterIntake : null,
        sleep: _sleepStatus.isNotEmpty
            ? SleepEntryModel(
                status: _sleepStatus,
                durationOrRange: _sleepDurationCtrl.text,
                note: _sleepNoteCtrl.text,
              )
            : null,
        selfCareTagsToAdd:
            _selfCareTags.isNotEmpty ? _selfCareTags.toList() : null,
        neededItemsToAdd:
            _neededItems.isNotEmpty ? _neededItems.toList() : null,
        sharedTeacherNote: _sharedNoteCtrl.text.trim().isNotEmpty
            ? _sharedNoteCtrl.text.trim()
            : null,
        overwriteExistingStudentNote: _overwriteNotes,
      );

      if (mounted) Navigator.of(context).pop(count);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Toplu kayıt sırasında hata oluştu: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildMealSelectorRow({
    required String title,
    required IconData icon,
    required Color color,
    required String selectedStatus,
    required ValueChanged<String> onSelect,
    required TextEditingController noteCtrl,
    required String noteHint,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              if (selectedStatus.isNotEmpty)
                InkWell(
                  onTap: () => onSelect(''),
                  child: const Text(
                    'Seçimi Kaldır',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: DailyReportCatalog.mealStatuses.map((m) {
              final sel = selectedStatus == m.key;
              return InkWell(
                onTap: () => onSelect(sel ? '' : m.key),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: sel
                        ? m.color.withValues(alpha: 0.14)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sel ? m.color : const Color(0xFFE2E8F0),
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        m.icon,
                        size: 15,
                        color: sel ? m.color : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        m.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                          color: sel ? m.color : const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          if (selectedStatus.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ModernInput(
              controller: noteCtrl,
              hint: noteHint,
              icon: Icons.restaurant_menu_rounded,
              accent: color,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _DailySheetFrame(
      title: 'Tüm Sınıfa Toplu Günlük Karne İşle',
      subtitle:
          '${widget.className} • Yalnızca seçtiğiniz başlıklar güncellenir; ardından tek tek öğrencileri düzenleyebilirsiniz',
      icon: Icons.auto_awesome_motion_rounded,
      accentColor: const Color(0xFF0D9488),
      footer: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: _saving ? null : _applyBulk,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D9488),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.done_all_rounded, size: 20),
          label: Text(
            _saving
                ? 'Sınıfa İşleniyor...'
                : 'Seçili Bilgileri ${_selectedStudentIds.length} Öğrenciye Uygula',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Öğrenci Hedef Seçici
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDFA),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF99F6E4)),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: () =>
                      setState(() => _showStudentFilter = !_showStudentFilter),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.people_alt_rounded,
                        color: Color(0xFF0F766E),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _selectedStudentIds.length ==
                                  widget.classStudents.length
                              ? 'Tüm Sınıf Seçili (${widget.classStudents.length} Öğrenci)'
                              : '${_selectedStudentIds.length} / ${widget.classStudents.length} Öğrenci Seçili',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF134E4A),
                          ),
                        ),
                      ),
                      Text(
                        _showStudentFilter ? 'Kapat' : 'İstisna Öğrenci Çıkar',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0D9488),
                        ),
                      ),
                      Icon(
                        _showStudentFilter
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: const Color(0xFF0D9488),
                      ),
                    ],
                  ),
                ),
                if (_showStudentFilter) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: widget.classStudents.map((st) {
                      final sel = _selectedStudentIds.contains(st.id);
                      return FilterChip(
                        label: Text(st.fullName),
                        selected: sel,
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _selectedStudentIds.add(st.id);
                            } else {
                              _selectedStudentIds.remove(st.id);
                            }
                          });
                        },
                        selectedColor: const Color(0xFFCCFBF1),
                        checkmarkColor: const Color(0xFF0F766E),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),

          // 1. Beslenme
          if (widget.config.trackMeals)
            _SectionCard(
              title: 'Beslenme Takibi',
              subtitle:
                  'Öğün durumunu tüm sınıfa tek dokunuşla girin (boş bıraktığınız öğün değişmez)',
              icon: Icons.restaurant_rounded,
              color: const Color(0xFFF59E0B),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMealSelectorRow(
                    title: 'Sabah Kahvaltısı',
                    icon: Icons.wb_twilight_rounded,
                    color: const Color(0xFFF59E0B),
                    selectedStatus: _breakfastStatus,
                    onSelect: (v) => setState(() => _breakfastStatus = v),
                    noteCtrl: _breakfastNoteCtrl,
                    noteHint:
                        'Menü / Not (Örn: Yumurta, peynir, zeytin, süt)',
                  ),
                  _buildMealSelectorRow(
                    title: 'Öğle Yemeği',
                    icon: Icons.lunch_dining_rounded,
                    color: const Color(0xFF10B981),
                    selectedStatus: _lunchStatus,
                    onSelect: (v) => setState(() => _lunchStatus = v),
                    noteCtrl: _lunchNoteCtrl,
                    noteHint:
                        'Menü / Not (Örn: Mercimek çorbası, köfte, bulgur pilavı)',
                  ),
                  _buildMealSelectorRow(
                    title: 'İkindi Kahvaltısı / Ara Öğün',
                    icon: Icons.bakery_dining_rounded,
                    color: const Color(0xFF8B5CF6),
                    selectedStatus: _snackStatus,
                    onSelect: (v) => setState(() => _snackStatus = v),
                    noteCtrl: _snackNoteCtrl,
                    noteHint: 'Menü / Not (Örn: Meyve tabağı / Ev yapımı kek)',
                  ),
                  if (widget.config.trackWater) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Su Tüketimi',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: DailyReportCatalog.waterOptions.map((w) {
                        final sel = _waterIntake == w.key;
                        return ChoiceChip(
                          label: Text('${w.emoji} ${w.label}'),
                          selected: sel,
                          onSelected: (_) => setState(
                            () => _waterIntake = sel ? '' : w.key,
                          ),
                          selectedColor: w.color.withValues(alpha: 0.16),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),

          // 2. Uyku & Dinlenme
          if (widget.config.trackSleep)
            _SectionCard(
              title: 'Uyku & Dinlenme Saati',
              subtitle: 'Öğle uykusu durumunu ve saat aralığını belirleyin',
              icon: Icons.bedtime_rounded,
              color: const Color(0xFF6366F1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: DailyReportCatalog.sleepStatuses.map((s) {
                      final sel = _sleepStatus == s.key;
                      return ChoiceChip(
                        avatar: Icon(
                          s.icon,
                          size: 16,
                          color: sel ? s.color : const Color(0xFF64748B),
                        ),
                        label: Text(s.label),
                        selected: sel,
                        onSelected: (_) =>
                            setState(() => _sleepStatus = sel ? '' : s.key),
                        selectedColor: s.color.withValues(alpha: 0.16),
                      );
                    }).toList(),
                  ),
                  if (_sleepStatus == 'slept' || _sleepStatus == 'rested') ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: DailyReportCatalog.sleepDurationPresets.map((p) {
                        final active = _sleepDurationCtrl.text.trim() == p;
                        return ActionChip(
                          label: Text(p, style: const TextStyle(fontSize: 11.5)),
                          backgroundColor: active
                              ? const Color(0xFFE0E7FF)
                              : Colors.white,
                          onPressed: () =>
                              setState(() => _sleepDurationCtrl.text = p),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _ModernInput(
                            controller: _sleepDurationCtrl,
                            label: 'Uyku Süresi / Saat Aralığı',
                            hint: 'Örn: 13:00 - 14:30',
                            icon: Icons.schedule_rounded,
                            accent: const Color(0xFF6366F1),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ModernInput(
                            controller: _sleepNoteCtrl,
                            label: 'Uyku Notu (Opsiyonel)',
                            hint: 'Örn: Rahat uyudu',
                            icon: Icons.nights_stay_rounded,
                            accent: const Color(0xFF6366F1),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

          // 3. Duygu Durumu & Uyum
          if (widget.config.trackMood)
            _SectionCard(
              title: 'Genel Duygu Durumu & Sınıf Uyumu',
              subtitle: 'Varsayılan genel durumu seçip bireysel farklılıkları listeden değiştirebilirsiniz',
              icon: Icons.mood_rounded,
              color: const Color(0xFF10B981),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: DailyReportCatalog.moods.map((m) {
                      final sel = _mood == m.key;
                      return ChoiceChip(
                        label: Text('${m.emoji} ${m.label}'),
                        selected: sel,
                        onSelected: (_) =>
                            setState(() => _mood = sel ? '' : m.key),
                        selectedColor: m.color.withValues(alpha: 0.16),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: DailyReportCatalog.socialHarmonyOptions.map((h) {
                      final sel = _socialHarmony == h.key;
                      return ChoiceChip(
                        avatar: Icon(h.icon, size: 15, color: h.color),
                        label: Text(h.label),
                        selected: sel,
                        onSelected: (_) => setState(
                          () => _socialHarmony = sel ? '' : h.key,
                        ),
                        selectedColor: h.color.withValues(alpha: 0.16),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

          // 4. Özbakım & Veliye Hatırlatma + Gün Sonu Notu
          _SectionCard(
            title: 'Özbakım, Veliye Hatırlatma & Ortak Gün Sonu Notu',
            icon: Icons.backpack_rounded,
            color: const Color(0xFF4F46E5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.config.trackSelfCare) ...[
                  const Text(
                    'Özbakım & Hijyen',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: DailyReportCatalog.selfCarePresets.map((tag) {
                      final sel = _selfCareTags.contains(tag);
                      return FilterChip(
                        label: Text(tag, style: const TextStyle(fontSize: 12)),
                        selected: sel,
                        onSelected: (v) => setState(() {
                          if (v) {
                            _selfCareTags.add(tag);
                          } else {
                            _selfCareTags.remove(tag);
                          }
                        }),
                        selectedColor: const Color(0xFFDCFCE7),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                const Text(
                  'Veliye Yarına Not / İhtiyaç Hatırlatması',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: DailyReportCatalog.neededItemPresets.map((item) {
                    final sel = _neededItems.contains(item);
                    return FilterChip(
                      label: Text(item, style: const TextStyle(fontSize: 12)),
                      selected: sel,
                      onSelected: (v) => setState(() {
                        if (v) {
                          _neededItems.add(item);
                        } else {
                          _neededItems.remove(item);
                        }
                      }),
                      selectedColor: const Color(0xFFFEF3C7),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                _ModernInput(
                  controller: _sharedNoteCtrl,
                  label: 'Sınıf Genel Gün Sonu Notu',
                  trailing: 'Opsiyonel',
                  hint:
                      'Örn: Bugün sınıfça harika ve enerjik bir gün geçirdik, iyi akşamlar dileriz...',
                  icon: Icons.chat_bubble_outline_rounded,
                  maxLines: 2,
                ),
                if (_sharedNoteCtrl.text.isNotEmpty || true)
                  CheckboxListTile(
                    value: _overwriteNotes,
                    onChanged: (v) =>
                        setState(() => _overwriteNotes = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Öğrenciye daha önce bireysel not yazıldıysa üzerine yaz (işaretlenmezse bireysel notlar korunur)',
                      style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 3. BİREYSEL ÖĞRENCİ GÜNLÜK KARNE GİRİŞ / DÜZENLEME SHEET'İ
// ═════════════════════════════════════════════════════════════════════════════

class StudentDailyReportEditorSheet extends StatefulWidget {
  final String institutionId;
  final String schoolDocId;
  final String dateKey;
  final DailyReportStudentInfo student;
  final DailyReportModel? existing;
  final DailyReportConfigModel config;
  final String actorUid;
  final String actorName;

  const StudentDailyReportEditorSheet({
    super.key,
    required this.institutionId,
    required this.schoolDocId,
    required this.dateKey,
    required this.student,
    required this.existing,
    required this.config,
    required this.actorUid,
    required this.actorName,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String institutionId,
    required String schoolDocId,
    required String dateKey,
    required DailyReportStudentInfo student,
    required DailyReportModel? existing,
    required DailyReportConfigModel config,
    required String actorUid,
    required String actorName,
  }) {
    return showDailyReportBottomSheet<bool>(
      context: context,
      maxWidth: 780,
      builder: (_) => StudentDailyReportEditorSheet(
        institutionId: institutionId,
        schoolDocId: schoolDocId,
        dateKey: dateKey,
        student: student,
        existing: existing,
        config: config,
        actorUid: actorUid,
        actorName: actorName,
      ),
    );
  }

  @override
  State<StudentDailyReportEditorSheet> createState() =>
      _StudentDailyReportEditorSheetState();
}

class _StudentDailyReportEditorSheetState
    extends State<StudentDailyReportEditorSheet> {
  final _service = DailyReportService();
  bool _saving = false;

  late String _mood;
  late String _socialHarmony;

  late String _breakfastStatus;
  late final TextEditingController _breakfastNoteCtrl;

  late String _lunchStatus;
  late final TextEditingController _lunchNoteCtrl;

  late String _snackStatus;
  late final TextEditingController _snackNoteCtrl;

  late String _waterIntake;

  late String _sleepStatus;
  late final TextEditingController _sleepDurationCtrl;
  late final TextEditingController _sleepNoteCtrl;

  late List<DailyActivityItemModel> _activities;
  late Set<String> _selfCareTags;
  late Set<String> _neededItems;

  late final TextEditingController _healthNoteCtrl;
  late final TextEditingController _teacherNoteCtrl;

  // Bireysel yeni etkinlik ekleme mini formu
  bool _addingInlineActivity = false;
  String _newActCategory = 'book';
  final _newActTitleCtrl = TextEditingController(text: 'Kitap Okuma & Masal');
  final _newActDescCtrl = TextEditingController();
  String _newActParticipation = 'enthusiastic';

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _mood = r?.mood ?? '';
    _socialHarmony = r?.socialHarmony ?? '';

    _breakfastStatus = r?.breakfast.status ?? 'unset';
    _breakfastNoteCtrl =
        TextEditingController(text: r?.breakfast.menuOrNote ?? '');

    _lunchStatus = r?.lunch.status ?? 'unset';
    _lunchNoteCtrl = TextEditingController(text: r?.lunch.menuOrNote ?? '');

    _snackStatus = r?.snack.status ?? 'unset';
    _snackNoteCtrl = TextEditingController(text: r?.snack.menuOrNote ?? '');

    _waterIntake = r?.waterIntake ?? '';

    _sleepStatus = r?.sleep.status ?? 'unset';
    _sleepDurationCtrl =
        TextEditingController(text: r?.sleep.durationOrRange ?? '');
    _sleepNoteCtrl = TextEditingController(text: r?.sleep.note ?? '');

    _activities = List<DailyActivityItemModel>.from(r?.activities ?? const []);
    _selfCareTags = Set<String>.from(r?.selfCareTags ?? const []);
    _neededItems = Set<String>.from(r?.neededItems ?? const []);

    _healthNoteCtrl = TextEditingController(text: r?.healthNote ?? '');
    _teacherNoteCtrl = TextEditingController(text: r?.teacherNote ?? '');
  }

  @override
  void dispose() {
    _breakfastNoteCtrl.dispose();
    _lunchNoteCtrl.dispose();
    _snackNoteCtrl.dispose();
    _sleepDurationCtrl.dispose();
    _sleepNoteCtrl.dispose();
    _healthNoteCtrl.dispose();
    _teacherNoteCtrl.dispose();
    _newActTitleCtrl.dispose();
    _newActDescCtrl.dispose();
    super.dispose();
  }

  void _addInlineActivity() {
    if (_newActTitleCtrl.text.trim().isEmpty &&
        _newActDescCtrl.text.trim().isEmpty) {
      return;
    }
    final meta = DailyReportCatalog.activityMeta(_newActCategory);
    setState(() {
      _activities.add(
        DailyActivityItemModel(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          category: _newActCategory,
          title: _newActTitleCtrl.text.trim().isNotEmpty
              ? _newActTitleCtrl.text.trim()
              : meta.title,
          description: _newActDescCtrl.text.trim(),
          timeLabel: DateFormat('HH:mm').format(DateTime.now()),
          participation: _newActParticipation,
          teacherName: widget.actorName,
          createdAt: DateTime.now(),
        ),
      );
      _newActDescCtrl.clear();
      _addingInlineActivity = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final base = widget.existing;
      final report = DailyReportModel(
        id: DailyReportModel.buildDocId(widget.dateKey, widget.student.id),
        institutionId: widget.institutionId,
        schoolDocId: widget.schoolDocId,
        schoolTypeId: widget.student.schoolTypeId,
        schoolTypeName: widget.student.schoolTypeName,
        classId: widget.student.classId,
        className: widget.student.className,
        classLevel: widget.student.classLevel,
        studentId: widget.student.id,
        studentName: widget.student.fullName,
        studentNo: widget.student.studentNo,
        dateKey: widget.dateKey,
        mood: _mood,
        socialHarmony: _socialHarmony,
        breakfast: MealEntryModel(
          status: _breakfastStatus,
          menuOrNote: _breakfastNoteCtrl.text,
        ),
        lunch: MealEntryModel(
          status: _lunchStatus,
          menuOrNote: _lunchNoteCtrl.text,
        ),
        snack: MealEntryModel(
          status: _snackStatus,
          menuOrNote: _snackNoteCtrl.text,
        ),
        waterIntake: _waterIntake,
        sleep: SleepEntryModel(
          status: _sleepStatus,
          durationOrRange: _sleepDurationCtrl.text,
          note: _sleepNoteCtrl.text,
        ),
        activities: _activities,
        selfCareTags: _selfCareTags.toList(),
        healthNote: _healthNoteCtrl.text,
        neededItems: _neededItems.toList(),
        teacherNote: _teacherNoteCtrl.text,
        isPublished: true,
        parentSeenAt: base?.parentSeenAt,
        parentReaction: base?.parentReaction ?? '',
        parentFeedbackNote: base?.parentFeedbackNote ?? '',
        parentFeedbackAt: base?.parentFeedbackAt,
        updatedAt: DateTime.now(),
        contributors: base?.contributors ?? const [],
      );

      await _service.saveStudentReport(
        report: report,
        actorUid: widget.actorUid,
        actorName: widget.actorName,
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydedilemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildSingleMealEditor({
    required String title,
    required IconData icon,
    required Color color,
    required String status,
    required ValueChanged<String> onChanged,
    required TextEditingController noteCtrl,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: DailyReportCatalog.mealStatuses.map((m) {
              final sel = status == m.key;
              return ChoiceChip(
                avatar: Icon(
                  m.icon,
                  size: 15,
                  color: sel ? m.color : const Color(0xFF64748B),
                ),
                label: Text(m.label, style: const TextStyle(fontSize: 12)),
                selected: sel,
                onSelected: (_) => onChanged(sel ? 'unset' : m.key),
                selectedColor: m.color.withValues(alpha: 0.16),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          _ModernInput(
            controller: noteCtrl,
            hint: 'Öğün detayı veya öğrenciye özel beslenme notu...',
            icon: Icons.edit_note_rounded,
            accent: color,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.student;

    return _DailySheetFrame(
      title: st.fullName,
      subtitle:
          '${st.className} • ${widget.dateKey} Günlük Karnesi (Kaydedildiğinde veliye anlık yansır)',
      icon: Icons.child_care_rounded,
      accentColor: const Color(0xFF4F46E5),
      footer: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4F46E5),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_circle_rounded, size: 19),
          label: Text(
            _saving ? 'Kaydediliyor...' : 'Öğrenci Günlük Karnesini Kaydet',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (st.allergyOrHealthInfo.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFDC2626),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Sağlık / Alerji Uyarısı: ${st.allergyOrHealthInfo}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF991B1B),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (widget.existing?.parentSeenAt != null ||
              (widget.existing?.parentFeedbackNote ?? '').isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFC7D2FE)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.visibility_rounded,
                    color: Color(0xFF4F46E5),
                    size: 19,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.existing?.parentSeenAt != null)
                          Text(
                            'Veli Görüntüledi: ${DateFormat('HH:mm').format(widget.existing!.parentSeenAt!)} ${widget.existing!.parentReaction}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF312E81),
                            ),
                          ),
                        if ((widget.existing?.parentFeedbackNote ?? '')
                            .isNotEmpty)
                          Text(
                            'Veli Notu: "${widget.existing!.parentFeedbackNote}"',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4338CA),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // 1. Duygu Durumu
          if (widget.config.trackMood)
            _SectionCard(
              title: 'Duygu Durumu & Arkadaş Uyumu',
              icon: Icons.mood_rounded,
              color: const Color(0xFF10B981),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: DailyReportCatalog.moods.map((m) {
                      final sel = _mood == m.key;
                      return ChoiceChip(
                        label: Text('${m.emoji} ${m.label}'),
                        selected: sel,
                        onSelected: (_) =>
                            setState(() => _mood = sel ? '' : m.key),
                        selectedColor: m.color.withValues(alpha: 0.16),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: DailyReportCatalog.socialHarmonyOptions.map((h) {
                      final sel = _socialHarmony == h.key;
                      return ChoiceChip(
                        avatar: Icon(h.icon, size: 15, color: h.color),
                        label: Text(h.label),
                        selected: sel,
                        onSelected: (_) => setState(
                          () => _socialHarmony = sel ? '' : h.key,
                        ),
                        selectedColor: h.color.withValues(alpha: 0.16),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

          // 2. Beslenme
          if (widget.config.trackMeals)
            _SectionCard(
              title: 'Beslenme Durumu',
              icon: Icons.restaurant_rounded,
              color: const Color(0xFFF59E0B),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSingleMealEditor(
                    title: 'Sabah Kahvaltısı',
                    icon: Icons.wb_twilight_rounded,
                    color: const Color(0xFFF59E0B),
                    status: _breakfastStatus,
                    onChanged: (v) => setState(() => _breakfastStatus = v),
                    noteCtrl: _breakfastNoteCtrl,
                  ),
                  _buildSingleMealEditor(
                    title: 'Öğle Yemeği',
                    icon: Icons.lunch_dining_rounded,
                    color: const Color(0xFF10B981),
                    status: _lunchStatus,
                    onChanged: (v) => setState(() => _lunchStatus = v),
                    noteCtrl: _lunchNoteCtrl,
                  ),
                  _buildSingleMealEditor(
                    title: 'İkindi Kahvaltısı / Ara Öğün',
                    icon: Icons.bakery_dining_rounded,
                    color: const Color(0xFF8B5CF6),
                    status: _snackStatus,
                    onChanged: (v) => setState(() => _snackStatus = v),
                    noteCtrl: _snackNoteCtrl,
                  ),
                  if (widget.config.trackWater) ...[
                    const Text(
                      'Su Tüketimi',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: DailyReportCatalog.waterOptions.map((w) {
                        final sel = _waterIntake == w.key;
                        return ChoiceChip(
                          label: Text('${w.emoji} ${w.label}'),
                          selected: sel,
                          onSelected: (_) => setState(
                            () => _waterIntake = sel ? '' : w.key,
                          ),
                          selectedColor: w.color.withValues(alpha: 0.16),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),

          // 3. Uyku
          if (widget.config.trackSleep)
            _SectionCard(
              title: 'Uyku & Dinlenme',
              icon: Icons.bedtime_rounded,
              color: const Color(0xFF6366F1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: DailyReportCatalog.sleepStatuses.map((s) {
                      final sel = _sleepStatus == s.key;
                      return ChoiceChip(
                        avatar: Icon(
                          s.icon,
                          size: 16,
                          color: sel ? s.color : const Color(0xFF64748B),
                        ),
                        label: Text(s.label),
                        selected: sel,
                        onSelected: (_) => setState(
                          () => _sleepStatus = sel ? 'unset' : s.key,
                        ),
                        selectedColor: s.color.withValues(alpha: 0.16),
                      );
                    }).toList(),
                  ),
                  if (_sleepStatus == 'slept' || _sleepStatus == 'rested') ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: DailyReportCatalog.sleepDurationPresets.map((p) {
                        return ActionChip(
                          label: Text(p, style: const TextStyle(fontSize: 11.5)),
                          onPressed: () =>
                              setState(() => _sleepDurationCtrl.text = p),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _ModernInput(
                            controller: _sleepDurationCtrl,
                            label: 'Süre / Saat',
                            hint: '13:00 - 14:30',
                            icon: Icons.schedule_rounded,
                            accent: const Color(0xFF6366F1),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ModernInput(
                            controller: _sleepNoteCtrl,
                            label: 'Uyku Notu',
                            hint: 'Örn: Deliksiz uyudu',
                            icon: Icons.nights_stay_rounded,
                            accent: const Color(0xFF6366F1),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

          // 4. Etkinlikler & Dersler (Öğrenci Bazlı Düzenlenebilir!)
          if (widget.config.trackActivities)
            _SectionCard(
              title: 'Günün Etkinlik, Kitap, Gezi & Branş Dersleri',
              subtitle:
                  'Öğrencinin her etkinlikteki katılım derecesini özelleştirebilir veya yeni etkinlik ekleyebilirsiniz',
              icon: Icons.palette_rounded,
              color: const Color(0xFF8B5CF6),
              trailing: TextButton.icon(
                onPressed: () => setState(
                  () => _addingInlineActivity = !_addingInlineActivity,
                ),
                icon: Icon(
                  _addingInlineActivity
                      ? Icons.close_rounded
                      : Icons.add_circle_outline_rounded,
                  size: 16,
                ),
                label: Text(_addingInlineActivity ? 'Kapat' : 'Etkinlik Ekle'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_addingInlineActivity)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFC4B5FD)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children:
                                DailyReportCatalog.activityCategories.map((c) {
                              final sel = _newActCategory == c.key;
                              return ChoiceChip(
                                label: Text(
                                  '${c.emoji} ${c.title}',
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                                selected: sel,
                                onSelected: (_) {
                                  setState(() {
                                    _newActCategory = c.key;
                                    _newActTitleCtrl.text = c.title;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 10),
                          _ModernInput(
                            controller: _newActTitleCtrl,
                            label: 'Etkinlik Başlığı',
                            accent: const Color(0xFF8B5CF6),
                          ),
                          const SizedBox(height: 8),
                          _ModernInput(
                            controller: _newActDescCtrl,
                            label: 'Açıklama',
                            hint: DailyReportCatalog.activityMeta(
                              _newActCategory,
                            ).hint,
                            accent: const Color(0xFF8B5CF6),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              onPressed: _addInlineActivity,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF8B5CF6),
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.add_rounded, size: 17),
                              label: const Text('Listeye Ekle'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_activities.isEmpty)
                    const Text(
                      'Henüz etkinlik eklenmedi.',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                    )
                  else
                    ...List.generate(_activities.length, (i) {
                      final act = _activities[i];
                      final meta = DailyReportCatalog.activityMeta(act.category);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  meta.emoji,
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    act.title,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                if (act.timeLabel.isNotEmpty)
                                  Text(
                                    act.timeLabel,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                IconButton(
                                  onPressed: () =>
                                      setState(() => _activities.removeAt(i)),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: Colors.redAccent,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                            if (act.description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                act.description,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: DailyReportCatalog.participationLevels
                                  .map((p) {
                                final sel = act.participation == p.key;
                                return InkWell(
                                  onTap: () {
                                    setState(() {
                                      _activities[i] =
                                          act.copyWith(participation: p.key);
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: sel
                                          ? p.color.withValues(alpha: 0.14)
                                          : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: sel
                                            ? p.color
                                            : const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Text(
                                      p.label,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: sel
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                        color: sel
                                            ? p.color
                                            : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),

          // 5. Özbakım, Sağlık & Öğretmen Özel Notu
          _SectionCard(
            title: 'Özbakım, Sağlık & Öğretmen Özel Notu',
            icon: Icons.favorite_border_rounded,
            color: const Color(0xFFEC4899),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.config.trackSelfCare) ...[
                  const Text(
                    'Özbakım & Hijyen',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: DailyReportCatalog.selfCarePresets.map((tag) {
                      final sel = _selfCareTags.contains(tag);
                      return FilterChip(
                        label: Text(tag, style: const TextStyle(fontSize: 12)),
                        selected: sel,
                        onSelected: (v) => setState(() {
                          if (v) {
                            _selfCareTags.add(tag);
                          } else {
                            _selfCareTags.remove(tag);
                          }
                        }),
                        selectedColor: const Color(0xFFDCFCE7),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.config.trackHealthNote) ...[
                  _ModernInput(
                    controller: _healthNoteCtrl,
                    label: 'İlaç / Sağlık / Revir Gözlem Notu',
                    trailing: 'Opsiyonel',
                    hint: 'Örn: 12:30 şurubu içirildi / hafif öksürük gözlemlendi',
                    icon: Icons.medical_services_outlined,
                    accent: const Color(0xFFEF4444),
                  ),
                  const SizedBox(height: 12),
                ],
                const Text(
                  'Veliye İhtiyaç / Yarına Hatırlatma',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: DailyReportCatalog.neededItemPresets.map((item) {
                    final sel = _neededItems.contains(item);
                    return FilterChip(
                      label: Text(item, style: const TextStyle(fontSize: 12)),
                      selected: sel,
                      onSelected: (v) => setState(() {
                        if (v) {
                          _neededItems.add(item);
                        } else {
                          _neededItems.remove(item);
                        }
                      }),
                      selectedColor: const Color(0xFFFEF3C7),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                _ModernInput(
                  controller: _teacherNoteCtrl,
                  label: 'Öğrenciye Özel Gün Sonu Notu',
                  trailing: 'Veliye Görünür',
                  hint:
                      'Örn: ${st.fullName.split(' ').first} bugün İngilizce şarkılara harika eşlik etti ve arkadaşlarıyla oyuncaklarını paylaştı...',
                  icon: Icons.rate_review_rounded,
                  accent: const Color(0xFF4F46E5),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 4. YÖNETİCİ GÜNLÜK RAPOR MODÜL AÇMA / KAPATMA VE ÖZELLEŞTİRME SHEET'İ
// ═════════════════════════════════════════════════════════════════════════════

class DailyReportSettingsSheet extends StatefulWidget {
  final String institutionId;
  final String schoolDocId;
  final DailyReportConfigModel initialConfig;

  const DailyReportSettingsSheet({
    super.key,
    required this.institutionId,
    required this.schoolDocId,
    required this.initialConfig,
  });

  static Future<DailyReportConfigModel?> show(
    BuildContext context, {
    required String institutionId,
    required String schoolDocId,
    required DailyReportConfigModel initialConfig,
  }) {
    return showDailyReportBottomSheet<DailyReportConfigModel>(
      context: context,
      maxWidth: 680,
      builder: (_) => DailyReportSettingsSheet(
        institutionId: institutionId,
        schoolDocId: schoolDocId,
        initialConfig: initialConfig,
      ),
    );
  }

  @override
  State<DailyReportSettingsSheet> createState() =>
      _DailyReportSettingsSheetState();
}

class _DailyReportSettingsSheetState extends State<DailyReportSettingsSheet> {
  final _service = DailyReportService();
  late DailyReportConfigModel _cfg;
  List<({String id, String name})> _schoolTypes = [];
  bool _loadingTypes = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _cfg = widget.initialConfig;
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    final types = await _service.loadSchoolTypes(widget.institutionId);
    if (mounted) {
      setState(() {
        _schoolTypes = types;
        _loadingTypes = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.saveConfig(
        schoolDocId: widget.schoolDocId,
        config: _cfg,
      );
      if (mounted) Navigator.of(context).pop(_cfg);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ayarlar kaydedilemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildToggle(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: _cfg.enabled ? onChanged : null,
      contentPadding: EdgeInsets.zero,
      activeColor: const Color(0xFF4F46E5),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _DailySheetFrame(
      title: 'Günlük Rapor (Günlük Karne) Modül Ayarları',
      subtitle:
          'Modülü açıp kapatın, hangi kademelerde (Anaokulu vb.) görüneceğini ve takip başlıklarını belirleyin',
      icon: Icons.tune_rounded,
      accentColor: const Color(0xFF4F46E5),
      footer: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4F46E5),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.save_rounded, size: 19),
          label: Text(
            _saving ? 'Kaydediliyor...' : 'Modül Ayarlarını Kaydet',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _cfg.enabled
                  ? const Color(0xFFEEF2FF)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _cfg.enabled
                    ? const Color(0xFFA5B4FC)
                    : const Color(0xFFCBD5E1),
              ),
            ),
            child: SwitchListTile.adaptive(
              value: _cfg.enabled,
              onChanged: (v) => setState(() => _cfg = _cfg.copyWith(enabled: v)),
              contentPadding: EdgeInsets.zero,
              activeColor: const Color(0xFF4F46E5),
              title: const Text(
                'Günlük Rapor (Günlük Karne) Modülü Aktif',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              subtitle: const Text(
                'Kapatıldığında öğretmen, okul türü ve veli ekranlarından gizlenir (Sistem Ayarları ile senkron çalışır).',
                style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!_loadingTypes && _schoolTypes.isNotEmpty) ...[
            const Text(
              'Hangi Okul Türlerinde Aktif Olsun?',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Hiçbiri seçilmezse tüm kademelerde aktiftir. Yalnızca Anaokulu / İlkokul seçerseniz diğer kademelerde görünmez.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Tüm Kademeler'),
                  selected: _cfg.enabledSchoolTypeIds.isEmpty,
                  onSelected: !_cfg.enabled
                      ? null
                      : (_) => setState(
                            () => _cfg = _cfg.copyWith(
                              enabledSchoolTypeIds: const [],
                            ),
                          ),
                ),
                ..._schoolTypes.map((st) {
                  final sel = _cfg.enabledSchoolTypeIds.contains(st.id);
                  return FilterChip(
                    label: Text(st.name),
                    selected: sel,
                    onSelected: !_cfg.enabled
                        ? null
                        : (v) {
                            final next =
                                Set<String>.from(_cfg.enabledSchoolTypeIds);
                            if (v) {
                              next.add(st.id);
                            } else {
                              next.remove(st.id);
                            }
                            setState(
                              () => _cfg = _cfg.copyWith(
                                enabledSchoolTypeIds: next.toList(),
                              ),
                            );
                          },
                  );
                }),
              ],
            ),
            const Divider(height: 26),
          ],
          const Text(
            'Karnede Yer Alacak Bölümler',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 6),
          _buildToggle(
            'Beslenme Takibi (Kahvaltı, Öğle, İkindi)',
            'Öğün tüketim durumu ve menü notları',
            _cfg.trackMeals,
            (v) => setState(() => _cfg = _cfg.copyWith(trackMeals: v)),
          ),
          _buildToggle(
            'Su Tüketimi Takibi',
            'Gün içi su içme miktarı',
            _cfg.trackWater,
            (v) => setState(() => _cfg = _cfg.copyWith(trackWater: v)),
          ),
          _buildToggle(
            'Uyku & Dinlenme Saati',
            'Öğle uykusu durumu ve saat aralığı (yarım gün sınıflarda kapatılabilir)',
            _cfg.trackSleep,
            (v) => setState(() => _cfg = _cfg.copyWith(trackSleep: v)),
          ),
          _buildToggle(
            'Duygu Durumu & Arkadaş Uyumu',
            'Günlük ruh hali emojileri ve sosyal uyum',
            _cfg.trackMood,
            (v) => setState(() => _cfg = _cfg.copyWith(trackMood: v)),
          ),
          _buildToggle(
            'Etkinlik, Kitap, Gezi & Branş Ders Akışı',
            'İngilizce, kitap okuma, sanat, gezi ve fotoğraf paylaşımı',
            _cfg.trackActivities,
            (v) => setState(() => _cfg = _cfg.copyWith(trackActivities: v)),
          ),
          _buildToggle(
            'Özbakım & Hijyen Takibi',
            'El yıkama, diş fırçalama, tuvalet ve yedek kıyafet bilgisi',
            _cfg.trackSelfCare,
            (v) => setState(() => _cfg = _cfg.copyWith(trackSelfCare: v)),
          ),
          _buildToggle(
            'Sağlık & İlaç Gözlem Notu',
            'Gün içi ilaç takibi veya sağlık gözlemi',
            _cfg.trackHealthNote,
            (v) => setState(() => _cfg = _cfg.copyWith(trackHealthNote: v)),
          ),
          _buildToggle(
            'Veli Emoji Tepkisi & Kısa Teşekkür Notu',
            'Veliler günlük karneyi gördüğünde teşekkür / kısa not bırakabilsin',
            _cfg.allowParentFeedback,
            (v) => setState(() => _cfg = _cfg.copyWith(allowParentFeedback: v)),
          ),
        ],
      ),
    );
  }
}
