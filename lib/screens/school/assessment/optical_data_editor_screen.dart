import 'package:edukn/models/assessment/optical_form_model.dart';
import 'package:edukn/models/assessment/trial_exam_model.dart';
import 'package:edukn/screens/school/assessment/evaluation_models.dart';
import 'package:edukn/services/optical_line_edits.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Okunan TXT/DAT dosyasını görüntüleme ve DOSYAYA DOKUNMADAN düzeltme ekranı.
///
/// Her satır bir öğrenci kâğıdıdır. Optik formdaki tüm alanlar (ad, no, TC,
/// sınıf, şube, kitapçık, oturum, kurum kodu ve ders cevapları) düzenlenebilir;
/// bir kâğıt değerlendirmeden çıkarılabilir. Düzeltmeler oturumda ayrıca
/// saklanır ve "Sınavı Değerlendir" sırasında satırlara uygulanır.
///
/// Kaydet ile güncel düzeltme listesi döner (`List<OpticalLineEdit>`).
class OpticalDataEditorScreen extends StatefulWidget {
  final String title;
  final List<String> rawLines;
  final OpticalForm form;
  final List<OpticalLineEdit> initialEdits;

  /// Cevap anahtarındaki kitapçıklar (hızlı kitapçık değiştirme için).
  final List<String> booklets;

  /// Bu oturumda değerlendirilen dersler (boşsa hepsi).
  final List<String> sessionSubjects;

  const OpticalDataEditorScreen({
    super.key,
    required this.title,
    required this.rawLines,
    required this.form,
    required this.initialEdits,
    this.booklets = const [],
    this.sessionSubjects = const [],
  });

  @override
  State<OpticalDataEditorScreen> createState() => _OpticalDataEditorScreenState();
}

enum _Filter { all, edited, excluded }

// ───────────── tasarım sabitleri ─────────────
const _primary = Color(0xFF3949AB);
const _ink = Color(0xFF1F2937);
const _muted = Color(0xFF6B7280);
const _line = Color(0xFFE5E7EB);
const _surface = Color(0xFFF7F8FA);
const _editBg = Color(0xFFFFF4D6);
const _editBorder = Color(0xFFF2B33D);
const _editInk = Color(0xFF8A5A00);
const _exclBg = Color(0xFFFDECEC);
const _exclInk = Color(0xFFC62828);

/// Ham görünümde alanları ayırt etmek için belirgin, birbirinden uzak tonlar.
/// Sıra, ardışık iki rengin kontrastı yüksek olacak şekilde dizildi. Sarı/turuncu
/// bilerek yok (düzeltilen alan vurgusuyla karışmasın).
const _fieldPalette = <Color>[
  Color(0xFF90CAF9), // mavi
  Color(0xFFA5D6A7), // yeşil
  Color(0xFFF48FB1), // pembe
  Color(0xFF80CBC4), // camgöbeği-yeşil
  Color(0xFFCE93D8), // mor
  Color(0xFFC5E1A5), // fıstık
  Color(0xFFEF9A9A), // kırmızımsı
  Color(0xFF81D4FA), // açık mavi
  Color(0xFFBCAAA4), // kahve
  Color(0xFF9FA8DA), // çivit
  Color(0xFF80DEEA), // turkuaz
  Color(0xFFB0BEC5), // gri-mavi
];

class _OpticalDataEditorScreenState extends State<OpticalDataEditorScreen> {
  static const _blank = '·'; // cevap alanında boşluğu görünür kılmak için
  static const _rowH = 46.0;
  static const _rawRowH = 24.0;

  late final TextStyle _mono = GoogleFonts.robotoMono(
    fontSize: 13,
    height: 1.4,
    color: _ink,
  );

  /// Optik formdaki tüm alanlar.
  late final List<OpticalFieldRef> _allRefs = OpticalLineEdits.fieldsOf(widget.form);

  /// Bu oturumda geçerli alanlar: öğrenci bilgileri + yalnızca oturumda seçili
  /// dersler. Aynı sütunları paylaşan dersler (ör. Sözel'de Türkçe 52–71,
  /// Sayısal'da Matematik 52–71) böylece doğru derse atanır.
  late final List<OpticalFieldRef> _refs = () {
    final subs = widget.sessionSubjects.map((s) => s.trim().toLowerCase()).toSet();
    if (subs.isEmpty) return _allRefs;
    return _allRefs
        .where((r) => !r.isAnswer || subs.contains(r.label.trim().toLowerCase()))
        .toList();
  }();
  late final Map<String, OpticalFieldRef> _refByKey = {for (final r in _refs) r.key: r};
  /// Renkler satırdaki konuma göre verilir: yan yana alanlar farklı tonda olur.
  late final Map<String, Color> _fieldColor = () {
    final sorted = _refs.where((r) => r.field.start > 0).toList()
      ..sort((a, b) => a.field.start.compareTo(b.field.start));
    return {
      for (var k = 0; k < sorted.length; k++)
        sorted[k].key: _fieldPalette[k % _fieldPalette.length],
    };
  }();
  late final List<int> _rows = [
    for (var i = 0; i < widget.rawLines.length; i++)
      if (widget.rawLines[i].trim().isNotEmpty) i,
  ];
  late final Map<int, OpticalLineEdit> _edits =
      Map.of(OpticalLineEdits.validEdits(widget.rawLines, widget.initialEdits));
  late final int _stale = OpticalLineEdits.staleCount(widget.rawLines, widget.initialEdits);

  final _searchCtrl = TextEditingController();
  final _hScroll = ScrollController();
  final _rawHScroll = ScrollController();
  String _query = '';
  _Filter _filter = _Filter.all;
  bool _rawView = false;
  bool _dirty = false;
  int? _hover;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _hScroll.dispose();
    _rawHScroll.dispose();
    super.dispose();
  }

  // ───────────── yardımcılar ─────────────

  String _raw(int i) => OpticalLineEdits.clean(widget.rawLines[i]);

  /// Dosya Windows-1254 (Türkçe ANSI) ise Latin-1 ile çözüldüğünde İ/ı/Ş/ş/Ğ/ğ
  /// Ý/ý/Þ/þ/Ð/ð olarak görünür. Ekranda düzeltilir; harf sayısı aynı kaldığı
  /// için sütun hizası bozulmaz.
  late final bool _legacyTr = widget.rawLines.any((l) => l.contains(RegExp('[ÝýÞþÐð]')));

  String _tr(String s) => StudentMatcher.fixWindows1254(s);

  /// Ekranda girilen değeri dosyanın kodlamasına geri çevirir.
  String _toFile(String s) => !_legacyTr
      ? s
      : s
          .replaceAll('İ', 'Ý')
          .replaceAll('ı', 'ý')
          .replaceAll('Ş', 'Þ')
          .replaceAll('ş', 'þ')
          .replaceAll('Ğ', 'Ð')
          .replaceAll('ğ', 'ð');

  /// Düzeltilmiş satır (dışlama yok sayılarak; görüntü için).
  String _patched(int i) {
    final e = _edits[i];
    if (e == null || e.fields.isEmpty) return _raw(i);
    return OpticalLineEdits.applyOne(
      widget.rawLines[i],
      widget.form,
      OpticalLineEdit(line: i, fingerprint: e.fingerprint, fields: e.fields),
    );
  }

  String _value(int i, String key, {bool original = false}) {
    final r = _refByKey[key];
    if (r == null) return '';
    final v = OpticalLineEdits.read(original ? _raw(i) : _patched(i), r.field);
    return _tr(r.isAnswer ? v : v.trim());
  }

  bool _isEdited(int i, String key) => _edits[i]?.fields.containsKey(key) ?? false;
  bool _isExcluded(int i) => _edits[i]?.excluded ?? false;
  bool _hasFieldEdits(int i) => _edits[i]?.fields.isNotEmpty ?? false;

  /// Yeni alan değerlerini orijinalle karşılaştırıp yalnızca farkları saklar.
  void _store(int i, Map<String, String> values, bool excluded) {
    final fields = <String, String>{};
    values.forEach((k, raw) {
      final r = _refByKey[k];
      if (r == null) {
        // Bu oturumda gösterilmeyen alandaki eski düzeltme korunur.
        if (_edits[i]?.fields.containsKey(k) ?? false) fields[k] = raw;
        return;
      }
      final v = _toFile(raw);
      final orig = OpticalLineEdits.read(_raw(i), r.field);
      final same = r.isAnswer
          ? orig.trimRight() == v.trimRight()
          : orig.trim() == v.trim();
      if (!same) fields[k] = r.isAnswer ? v : v.trim();
    });
    setState(() {
      final e = OpticalLineEdit(
        line: i,
        fingerprint: OpticalLineEdits.fingerprint(widget.rawLines[i]),
        fields: fields,
        excluded: excluded,
      );
      if (e.isEmpty) {
        _edits.remove(i);
      } else {
        _edits[i] = e;
      }
      _dirty = true;
    });
  }

  void _setField(int i, String key, String value) {
    final values = {...?_edits[i]?.fields, key: value};
    _store(i, values, _isExcluded(i));
  }

  void _toggleExcluded(int i) =>
      _store(i, {...?_edits[i]?.fields}, !_isExcluded(i));

  List<int> get _visible {
    final q = StudentMatcher.normalizeTurkishForSearch(_query);
    return _rows.where((i) {
      if (_filter == _Filter.edited && !_hasFieldEdits(i)) return false;
      if (_filter == _Filter.excluded && !_isExcluded(i)) return false;
      if (q.isEmpty) return true;
      return StudentMatcher.normalizeTurkishForSearch(_patched(i)).contains(q) ||
          '${i + 1}' == _query.trim();
    }).toList();
  }

  void _save() {
    final list = _edits.values.where((e) => !e.isEmpty).toList()
      ..sort((a, b) => a.line.compareTo(b.line));
    Navigator.of(context).pop(list);
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kaydedilmemiş düzeltmeler'),
        content: const Text('Yaptığınız düzeltmeler kaydedilmedi. Çıkılsın mı?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kaydetmeden çık', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Tek karakter genişliği (gerçek yazı tipiyle ölçülür; taşmayı önler).
  double get _charW {
    final tp = TextPainter(
      text: TextSpan(text: 'MMMMMMMMMM', style: _mono),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width / 10;
    tp.dispose();
    return w < 7 ? 8.5 : w;
  }

  /// Alanları renklendirilmiş satır (düzeltilen alanlar vurgulu).
  TextSpan _richLine(int i, String fileText, {bool markEdits = true}) {
    final text = _tr(fileText);
    final segs = _refs.where((r) => r.field.start > 0).toList()
      ..sort((a, b) => a.field.start.compareTo(b.field.start));
    final spans = <TextSpan>[];
    var pos = 0; // 0-based
    for (final r in segs) {
      final s = r.field.start - 1;
      final e = (s + r.field.length).clamp(0, text.length);
      if (s >= text.length) break;
      if (s < pos) continue; // çakışan alanları atla
      if (s > pos) spans.add(TextSpan(text: text.substring(pos, s)));
      final edited = markEdits && _isEdited(i, r.key);
      spans.add(TextSpan(
        text: text.substring(s, e),
        style: TextStyle(
          backgroundColor: edited ? const Color(0xFFFFB300) : _fieldColor[r.key],
          fontWeight: edited ? FontWeight.w800 : null,
          color: edited ? Colors.black : null,
          decoration: edited ? TextDecoration.underline : null,
          decorationThickness: 2,
        ),
      ));
      pos = e;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    return TextSpan(style: _mono, children: spans);
  }

  // ───────────── düzenleme penceresi ─────────────

  Future<void> _openEdit(int i) async {
    final controllers = <String, TextEditingController>{
      for (final r in _refs)
        r.key: TextEditingController(
          text: r.isAnswer
              ? _value(i, r.key).replaceAll(' ', _blank)
              : _value(i, r.key),
        ),
    };
    var excluded = _isExcluded(i);
    final sessionSubs = widget.sessionSubjects.toSet();
    final name = _value(i, 'studentName');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          InputDecoration deco(OpticalFieldRef r, String orig, {Widget? suffix}) {
            final changed = r.isAnswer
                ? controllers[r.key]!.text.replaceAll(_blank, ' ').trimRight() !=
                    orig.trimRight()
                : controllers[r.key]!.text.trim() != orig.trim();
            return InputDecoration(
              isDense: true,
              filled: true,
              fillColor: changed ? _editBg : Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              counterText: '',
              labelText: r.label,
              labelStyle: const TextStyle(fontSize: 13),
              helperText: r.isAnswer
                  ? 'Orijinal: ${orig.replaceAll(' ', _blank)}'
                  : 'Orijinal: ${orig.isEmpty ? '—' : orig}  •  sütun ${r.field.start}–${r.field.end}',
              helperStyle: (r.isAnswer ? _mono : const TextStyle())
                  .copyWith(fontSize: 11, color: _muted),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: changed ? _editBorder : _line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _primary, width: 1.6),
              ),
              suffixIcon: suffix,
            );
          }

          Widget generalField(OpticalFieldRef r) {
            final c = controllers[r.key]!;
            final orig = _value(i, r.key, original: true);
            final isBooklet = r.key == 'bookletType' && widget.booklets.isNotEmpty;
            return SizedBox(
              width: r.key == 'studentName' ? 400 : 192,
              child: TextField(
                controller: c,
                maxLength: r.field.length,
                onChanged: (_) => setD(() {}),
                decoration: deco(
                  r,
                  orig,
                  suffix: isBooklet
                      ? PopupMenuButton<String>(
                          tooltip: 'Kitapçık seç',
                          icon: const Icon(Icons.arrow_drop_down),
                          onSelected: (v) => setD(() => c.text = v),
                          itemBuilder: (_) => [
                            for (final b in widget.booklets)
                              PopupMenuItem(value: b, child: Text('$b kitapçığı')),
                          ],
                        )
                      : null,
                ),
              ),
            );
          }

          Widget answerField(OpticalFieldRef r) {
            final c = controllers[r.key]!;
            final orig = _value(i, r.key, original: true);
            final outOfSession = sessionSubs.isNotEmpty && !sessionSubs.contains(r.label);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 170,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.label,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13, color: _ink)),
                          Text(
                            outOfSession
                                ? 'Bu oturumda değerlendirilmiyor'
                                : '${r.field.length} soru • sütun ${r.field.start}–${r.field.end}',
                            style: TextStyle(
                                fontSize: 11,
                                color: outOfSession ? Colors.orange.shade800 : _muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: c,
                      maxLength: r.field.length,
                      style: _mono.copyWith(letterSpacing: 1.5),
                      onChanged: (_) => setD(() {}),
                      decoration: deco(r, orig).copyWith(labelText: null),
                    ),
                  ),
                ],
              ),
            );
          }

          final general = _refs.where((r) => !r.isAnswer).toList();
          final answers = _refs.where((r) => r.isAnswer).toList();

          Widget sectionTitle(String t, IconData icon) => Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 12),
                child: Row(children: [
                  Icon(icon, size: 18, color: _primary),
                  const SizedBox(width: 8),
                  Text(t,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
                  const SizedBox(width: 12),
                  const Expanded(child: Divider(color: _line)),
                ]),
              );

          return Dialog(
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980, maxHeight: 820),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Başlık
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 18, 12, 18),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: _line)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Satır ${i + 1}',
                              style: const TextStyle(
                                  color: _primary, fontWeight: FontWeight.w700, fontSize: 12)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            name.isEmpty ? 'Adsız kâğıt' : name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700, color: _ink),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Kapat',
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  // İçerik
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _rawBox(i, 'Dosyadaki orijinal satır', _raw(i), markEdits: false),
                          if (_hasFieldEdits(i))
                            _rawBox(i, 'Düzeltilmiş satır', _patched(i)),
                          const SizedBox(height: 12),
                          Material(
                            color: excluded ? _exclBg : _surface,
                            borderRadius: BorderRadius.circular(10),
                            child: SwitchListTile(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              value: excluded,
                              activeThumbColor: _exclInk,
                              onChanged: (v) => setD(() => excluded = v),
                              secondary: Icon(Icons.block,
                                  color: excluded ? _exclInk : _muted),
                              title: const Text('Bu kâğıdı değerlendirmeden çıkar',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              subtitle: const Text('Çift okunan veya hatalı kâğıtlar için.',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ),
                          sectionTitle('Öğrenci bilgileri', Icons.badge_outlined),
                          Wrap(spacing: 12, runSpacing: 14, children: general.map(generalField).toList()),
                          if (answers.isNotEmpty) ...[
                            sectionTitle('Cevaplar  ($_blank = boş)', Icons.checklist_rtl),
                            ...answers.map(answerField),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Alt çubuk
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
                    decoration: const BoxDecoration(
                      color: _surface,
                      border: Border(top: BorderSide(color: _line)),
                    ),
                    child: Row(
                      children: [
                        if (_edits.containsKey(i))
                          TextButton.icon(
                            onPressed: () => Navigator.pop(ctx, 'reset'),
                            icon: const Icon(Icons.restore, size: 18),
                            label: const Text('Orijinale döndür'),
                            style: TextButton.styleFrom(foregroundColor: _exclInk),
                          ),
                        const Spacer(),
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          ),
                          child: const Text('İptal'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: () => Navigator.pop(ctx, 'apply'),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Uygula'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _primary,
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                          ),
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
    );

    if (result == 'reset') {
      setState(() {
        _edits.remove(i);
        _dirty = true;
      });
    } else if (result == 'apply') {
      final values = <String, String>{
        for (final r in _refs)
          r.key: r.isAnswer
              ? controllers[r.key]!.text.replaceAll(_blank, ' ')
              : controllers[r.key]!.text,
      };
      _store(i, values, excluded);
    }
    for (final c in controllers.values) {
      c.dispose();
    }
  }

  Widget _rawBox(int i, String label, String text, {bool markEdits = true}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: _muted, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _line),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText.rich(_richLine(i, text, markEdits: markEdits)),
              ),
            ),
          ],
        ),
      );

  // ───────────── görünüm ─────────────

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final editedCount = _edits.values.where((e) => e.fields.isNotEmpty).length;
    final excludedCount = _edits.values.where((e) => e.excluded).length;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: _surface,
        appBar: _appBar(editedCount + excludedCount),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _infoBanner(),
            _toolbar(editedCount, excludedCount, visible.length),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _line),
                ),
                clipBehavior: Clip.antiAlias,
                child: visible.isEmpty
                    ? _empty()
                    : _rawView
                        ? _rawList(visible)
                        : _studentTable(visible),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(int changes) {
    final parts = widget.title.split(' • ');
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      shape: const Border(bottom: BorderSide(color: _line)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            parts.length > 1 ? 'Okunan Veri  •  ${parts.first}' : 'Okunan Veri',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _ink),
          ),
          Text(
            parts.length > 1 ? parts.sublist(1).join(' • ') : widget.title,
            style: const TextStyle(fontSize: 12, color: _muted),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            selectedBackgroundColor: _primary.withValues(alpha: 0.1),
            selectedForegroundColor: _primary,
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.table_rows_outlined, size: 18), label: Text('Öğrenci listesi')),
            ButtonSegment(value: true, icon: Icon(Icons.data_object, size: 18), label: Text('Ham dosya')),
          ],
          selected: {_rawView},
          onSelectionChanged: (s) => setState(() => _rawView = s.first),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: FilledButton.icon(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(
              _dirty && changes > 0 ? 'Kaydet ($changes)' : 'Kaydet',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoBanner() => Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _primary.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.info_outline, size: 18, color: _primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 13, color: _ink),
                    children: const [
                      TextSpan(text: 'Orijinal dosya değiştirilmez. ', style: TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: 'Düzeltmeler sistemde ayrıca saklanır; sonuçlara yansıması için kaydettikten sonra '),
                      TextSpan(text: '"Sınavı Değerlendir"', style: TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: 'e basın.'),
                    ],
                  ),
                ),
              ),
            ]),
            if (_stale > 0) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange.shade800),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$_stale eski düzeltme bu dosyayla eşleşmiyor (dosya değişmiş). Kaydettiğinizde bunlar silinecek.',
                    style: TextStyle(fontSize: 13, color: Colors.orange.shade900),
                  ),
                ),
              ]),
            ],
          ],
        ),
      );

  Widget _toolbar(int edited, int excluded, int shown) {
    Widget filter(_Filter f, String label, int count, Color color) {
      final sel = _filter == f;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _filter = f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: sel ? color : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sel ? color : _line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : _ink)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: sel ? Colors.white.withValues(alpha: 0.25) : _surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$count',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: sel ? Colors.white : _muted)),
              ),
            ]),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          SizedBox(
            width: 360,
            height: 42,
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.zero,
                prefixIcon: const Icon(Icons.search, size: 20, color: _muted),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() {
                          _searchCtrl.clear();
                          _query = '';
                        }),
                      ),
                hintText: 'Ad, numara, TC veya satır no ara…',
                hintStyle: const TextStyle(fontSize: 14, color: _muted),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _primary, width: 1.5),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(width: 16),
          filter(_Filter.all, 'Tümü', _rows.length, _primary),
          filter(_Filter.edited, 'Düzeltilen', edited, _editBorder),
          filter(_Filter.excluded, 'Çıkarılan', excluded, _exclInk),
          const Spacer(),
          Text('$shown kâğıt gösteriliyor',
              style: const TextStyle(fontSize: 13, color: _muted)),
        ],
      ),
    );
  }

  Widget _empty() => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off, size: 40, color: _muted),
          SizedBox(height: 8),
          Text('Gösterilecek kâğıt yok.', style: TextStyle(color: _muted)),
        ]),
      );

  // ───────────── öğrenci tablosu ─────────────

  Widget _studentTable(List<int> visible) {
    final cols = <(String key, String label, double width)>[
      for (final c in const [
        ('studentNo', 'Öğrenci No', 120.0),
        ('identityNo', 'TC / Tel', 140.0),
        ('classLevel', 'Sınıf', 72.0),
        ('branch', 'Şube', 72.0),
        ('session', 'Oturum', 76.0),
      ])
        if (_refByKey.containsKey(c.$1)) c,
    ];
    final hasBooklet = _refByKey.containsKey('bookletType');
    const lineW = 72.0, nameMin = 240.0, statusW = 190.0, actionsW = 104.0;
    final bookletW = hasBooklet ? 160.0 : 0.0;
    final fixed = lineW + cols.fold<double>(0, (s, c) => s + c.$3) + bookletW + statusW + actionsW + 32;

    return LayoutBuilder(builder: (context, cons) {
      final tableW = cons.maxWidth < fixed + nameMin ? fixed + nameMin : cons.maxWidth;
      return Scrollbar(
        controller: _hScroll,
        thumbVisibility: tableW > cons.maxWidth,
        child: SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableW,
            child: Column(
              children: [
                // Başlık satırı
                Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    color: _surface,
                    border: Border(bottom: BorderSide(color: _line)),
                  ),
                  child: Row(children: [
                    _th('SATIR', lineW),
                    Expanded(child: _thText('AD SOYAD')),
                    for (final c in cols) _th(c.$2.toUpperCase(), c.$3),
                    if (hasBooklet) _th('KİTAPÇIK', bookletW),
                    _th('DURUM', statusW),
                    _th('', actionsW),
                  ]),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: visible.length,
                    itemExtent: _rowH,
                    itemBuilder: (context, idx) {
                      final i = visible[idx];
                      return _row(i, idx, cols, hasBooklet, lineW, bookletW, statusW, actionsW);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _thText(String t) => Text(t,
      style: const TextStyle(
          fontSize: 11.5, fontWeight: FontWeight.w700, color: _muted, letterSpacing: 0.6));
  Widget _th(String t, double w) => SizedBox(width: w, child: _thText(t));

  Widget _row(
    int i,
    int idx,
    List<(String, String, double)> cols,
    bool hasBooklet,
    double lineW,
    double bookletW,
    double statusW,
    double actionsW,
  ) {
    final excluded = _isExcluded(i);
    final edited = _hasFieldEdits(i);
    final name = _value(i, 'studentName');
    final hover = _hover == i;
    final bg = excluded
        ? _exclBg.withValues(alpha: 0.6)
        : hover
            ? _primary.withValues(alpha: 0.04)
            : idx.isOdd
                ? const Color(0xFFFBFBFC)
                : Colors.white;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = i),
      onExit: (_) => setState(() => _hover = _hover == i ? null : _hover),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openEdit(i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              bottom: const BorderSide(color: Color(0xFFF0F1F3)),
              left: BorderSide(
                width: 3,
                color: excluded ? _exclInk : edited ? _editBorder : Colors.transparent,
              ),
            ),
          ),
          child: Row(children: [
            SizedBox(
              width: lineW,
              child: Text('${i + 1}', style: _mono.copyWith(fontSize: 12, color: _muted)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _cellText(
                  name.isEmpty ? '(ad okunamadı)' : name,
                  edited: _isEdited(i, 'studentName'),
                  bold: true,
                  strike: excluded,
                  faded: name.isEmpty,
                ),
              ),
            ),
            for (final c in cols)
              SizedBox(
                width: c.$3,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _cellText(_value(i, c.$1), edited: _isEdited(i, c.$1), mono: true),
                ),
              ),
            if (hasBooklet) SizedBox(width: bookletW, child: _bookletToggle(i)),
            SizedBox(width: statusW, child: _status(i)),
            SizedBox(
              width: actionsW,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                _iconBtn(
                  excluded ? Icons.undo : Icons.block,
                  excluded ? 'Değerlendirmeye geri al' : 'Değerlendirmeden çıkar',
                  excluded ? Colors.green.shade700 : _exclInk,
                  () => _toggleExcluded(i),
                ),
                const SizedBox(width: 6),
                _iconBtn(Icons.edit_outlined, 'Tüm alanları düzenle', _primary, () => _openEdit(i)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _cellText(String v,
      {bool edited = false, bool bold = false, bool mono = false, bool strike = false, bool faded = false}) {
    final style = (mono ? _mono.copyWith(fontSize: 13) : const TextStyle(fontSize: 14)).copyWith(
      fontWeight: bold ? FontWeight.w600 : null,
      color: edited ? _editInk : faded ? _muted : _ink,
      decoration: strike ? TextDecoration.lineThrough : null,
      fontStyle: faded ? FontStyle.italic : null,
    );
    final text = Text(v.isEmpty ? '—' : v,
        style: v.isEmpty ? style.copyWith(color: const Color(0xFFC0C4CC)) : style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis);
    if (!edited) return Align(alignment: Alignment.centerLeft, child: text);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _editBg,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: _editBorder),
        ),
        child: text,
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tip, Color color, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      );

  /// Kitapçığı tek tıkla değiştirme (A | B | …).
  Widget _bookletToggle(int i) {
    final current = _value(i, 'bookletType');
    final edited = _isEdited(i, 'bookletType');
    final options = {...widget.booklets, if (current.isNotEmpty) current}.toList()..sort();
    if (options.isEmpty) return _cellText(current, edited: edited, mono: true);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: edited ? _editBg : _surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: edited ? _editBorder : _line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final b in options)
            Tooltip(
              message: b == current ? '$b kitapçığı (seçili)' : '$b kitapçığı yap',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: b == current ? null : () => _setField(i, 'bookletType', b),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 30,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: b == current ? (edited ? _editBorder : _primary) : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(b,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: b == current ? Colors.white : _muted,
                      )),
                ),
              ),
            ),
          if (current.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text('boş', style: TextStyle(fontSize: 11, color: _exclInk)),
            ),
        ]),
      ),
    );
  }

  Widget _badge(String t, Color bg, Color fg, {IconData? icon}) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Text(t, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
        ]),
      );

  Widget _status(int i) {
    final answers = _refs.where((r) => r.isAnswer && _isEdited(i, r.key)).map((r) => r.label).toList();
    final infoEdited = _edits[i]?.fields.keys.where((k) => !k.startsWith(OpticalLineEdits.subjPrefix)).length ?? 0;
    final children = <Widget>[
      if (_isExcluded(i)) _badge('Çıkarıldı', _exclBg, _exclInk, icon: Icons.block),
      if (infoEdited > 0) _badge('Bilgi', _editBg, _editInk, icon: Icons.edit),
      if (answers.isNotEmpty)
        Tooltip(
          message: 'Cevabı düzeltilen: ${answers.join(', ')}',
          child: _badge('${answers.length} ders', _editBg, _editInk, icon: Icons.checklist),
        ),
    ];
    if (children.isEmpty) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text('Orijinal', style: TextStyle(fontSize: 12, color: Color(0xFFB0B5BD))),
      );
    }
    return Align(alignment: Alignment.centerLeft, child: Row(mainAxisSize: MainAxisSize.min, children: children));
  }

  // ───────────── ham dosya görünümü ─────────────

  Widget _rawList(List<int> visible) {
    var maxLen = 0;
    for (final i in visible) {
      final l = _patched(i).length;
      if (l > maxLen) maxLen = l;
    }
    final cw = _charW;
    const gutter = 64.0;
    final contentW = gutter + 16 + maxLen * cw + 48;

    // Sütun cetveli: 10'un katlarında onlar basamağı, 5'lerde nokta.
    final ruler = StringBuffer();
    for (var p = 1; p <= maxLen; p++) {
      if (p % 10 == 0) {
        ruler.write(((p ~/ 10) % 10).toString());
      } else if (p % 5 == 0) {
        ruler.write('·');
      } else {
        ruler.write(' ');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _legend(),
        const Divider(height: 1, color: _line),
        Expanded(
          child: LayoutBuilder(builder: (context, cons) {
            final w = contentW < cons.maxWidth ? cons.maxWidth : contentW;
            return Scrollbar(
              controller: _rawHScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _rawHScroll,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: w,
                  child: Column(children: [
                    Container(
                      height: 26,
                      color: _surface,
                      child: Row(children: [
                        const SizedBox(width: gutter),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(ruler.toString(),
                              style: _mono.copyWith(fontSize: 13, color: _muted),
                              softWrap: false,
                              overflow: TextOverflow.clip),
                        ),
                      ]),
                    ),
                    const Divider(height: 1, color: _line),
                    Expanded(
                      child: ListView.builder(
                        itemCount: visible.length,
                        itemExtent: _rawRowH,
                        itemBuilder: (context, idx) {
                          final i = visible[idx];
                          final excluded = _isExcluded(i);
                          final edited = _hasFieldEdits(i);
                          return InkWell(
                            onTap: () => _openEdit(i),
                            hoverColor: _primary.withValues(alpha: 0.05),
                            child: Container(
                              decoration: BoxDecoration(
                                color: excluded
                                    ? _exclBg
                                    : edited
                                        ? _editBg.withValues(alpha: 0.5)
                                        : null,
                                border: Border(
                                  left: BorderSide(
                                    width: 3,
                                    color: excluded ? _exclInk : edited ? _editBorder : Colors.transparent,
                                  ),
                                ),
                              ),
                              child: Row(children: [
                                Container(
                                  width: gutter - 3,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 10),
                                  color: _surface,
                                  child: Text('${i + 1}',
                                      style: _mono.copyWith(fontSize: 12, color: _muted)),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Opacity(
                                    opacity: excluded ? 0.55 : 1,
                                    child: Text.rich(
                                      _richLine(i, _patched(i)),
                                      softWrap: false,
                                      overflow: TextOverflow.clip,
                                      maxLines: 1,
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
                  ]),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _legendChip(String text, Color color, {bool strong = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              color: strong ? Colors.black : _ink,
              decoration: strong ? TextDecoration.underline : null,
            )),
      );

  Widget _legend() {
    final sorted = _refs.where((r) => r.field.start > 0).toList()
      ..sort((a, b) => a.field.start.compareTo(b.field.start));
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Text('Alanlar:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _muted)),
          ),
          for (final r in sorted)
            _legendChip('${r.label}  ${r.field.start}–${r.field.end}', _fieldColor[r.key]!),
          const SizedBox(width: 8),
          _legendChip('Düzeltilen alan', const Color(0xFFFFB300), strong: true),
        ],
      ),
    );
  }
}
