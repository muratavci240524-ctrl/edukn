import '../models/assessment/optical_form_model.dart';
import '../models/assessment/trial_exam_model.dart';

/// Optik form üzerindeki tek bir alan (düzenleyicide bir sütun).
class OpticalFieldRef {
  /// Kalıcı anahtar (OpticalLineEdit.fields anahtarı).
  final String key;
  final String label;
  final OpticalField field;

  /// true: ders cevap alanı (boşluklar anlamlıdır, kırpılmaz).
  final bool isAnswer;

  const OpticalFieldRef(this.key, this.label, this.field, {this.isAnswer = false});
}

/// Okunan TXT/DAT satırlarına, ham dosyaya dokunmadan düzeltme uygular.
///
/// Mantık: her düzeltme, satırın ilgili sütun aralığını (optik formdaki
/// başlangıç/uzunluk) yeni değerle değiştirir. Böylece mevcut okuma /
/// değerlendirme kodu hiç değişmeden düzeltilmiş satırı okur.
class OpticalLineEdits {
  OpticalLineEdits._();

  static const subjPrefix = 'subj:';

  /// Satır sonundaki '\r' karakterini atar (Windows satır sonu).
  static String clean(String line) =>
      line.endsWith('\r') ? line.substring(0, line.length - 1) : line;

  /// Orijinal satırın parmak izi (uzunluk + FNV-1a 32 bit).
  static String fingerprint(String rawLine) {
    final l = clean(rawLine);
    var h = 0x811c9dc5;
    for (final c in l.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return '${l.length}-${h.toRadixString(16)}';
  }

  /// Formdaki tanımlı (uzunluğu > 0) tüm alanlar, düzenleyici sırasıyla.
  static List<OpticalFieldRef> fieldsOf(OpticalForm f) {
    final out = <OpticalFieldRef>[
      OpticalFieldRef('studentName', 'Ad Soyad', f.studentNameField),
      OpticalFieldRef('studentNo', 'Öğrenci No', f.studentNo),
      OpticalFieldRef('identityNo', 'TC / Tel', f.identityNo),
      OpticalFieldRef('classLevel', 'Sınıf', f.classLevel),
      OpticalFieldRef('branch', 'Şube', f.branch),
      OpticalFieldRef('bookletType', 'Kitapçık', f.bookletType),
      OpticalFieldRef('session', 'Oturum', f.session),
      OpticalFieldRef('institutionCode', 'Kurum Kodu', f.institutionCode),
      for (final e in f.subjectFields.entries)
        OpticalFieldRef('$subjPrefix${e.key}', e.key, e.value, isAnswer: true),
    ];
    return out.where((r) => r.field.length > 0).toList();
  }

  static int _startIdx(OpticalField f) => f.start > 0 ? f.start - 1 : 0;

  /// Alanın ham değeri (kırpılmadan, alan uzunluğuna tamamlanmış).
  static String read(String line, OpticalField f) {
    final l = clean(line);
    final s = _startIdx(f);
    if (l.length <= s) return ''.padRight(f.length);
    final e = s + f.length;
    return (l.length >= e ? l.substring(s, e) : l.substring(s)).padRight(f.length);
  }

  /// Alanı yeni değerle yazar; değer alan uzunluğuna göre tamamlanır/kesilir.
  static String write(String line, OpticalField f, String value) {
    var l = clean(line);
    final s = _startIdx(f);
    final e = s + f.length;
    if (l.length < e) l = l.padRight(e);
    final v = value.length > f.length ? value.substring(0, f.length) : value.padRight(f.length);
    return l.substring(0, s) + v + l.substring(e);
  }

  /// Düzeltmeyi tek satıra uygular (dışlanan satır için boş döner).
  static String applyOne(String rawLine, OpticalForm form, OpticalLineEdit edit) {
    if (edit.excluded) return '';
    var l = clean(rawLine);
    final refs = {for (final r in fieldsOf(form)) r.key: r};
    edit.fields.forEach((k, v) {
      final r = refs[k];
      if (r != null) l = write(l, r.field, v);
    });
    return l;
  }

  /// Geçerli (parmak izi tutan) düzeltmeler: satır indeksi -> düzeltme.
  static Map<int, OpticalLineEdit> validEdits(
    List<String> rawLines,
    List<OpticalLineEdit> edits,
  ) {
    final out = <int, OpticalLineEdit>{};
    for (final e in edits) {
      if (e.line < 0 || e.line >= rawLines.length || e.isEmpty) continue;
      if (fingerprint(rawLines[e.line]) != e.fingerprint) continue;
      out[e.line] = e;
    }
    return out;
  }

  /// Dosyayla eşleşmeyen (dosya değiştiği için uygulanamayan) düzeltme sayısı.
  static int staleCount(List<String> rawLines, List<OpticalLineEdit> edits) =>
      edits.where((e) => !e.isEmpty).length - validEdits(rawLines, edits).length;

  /// Tüm satırlara düzeltmeleri uygular. Liste uzunluğu korunur; düzeltme
  /// olmayan satırlar AYNEN kalır (mevcut okuma davranışı değişmez).
  static List<String> apply(
    List<String> rawLines,
    OpticalForm form,
    List<OpticalLineEdit> edits,
  ) {
    if (edits.isEmpty) return rawLines;
    final valid = validEdits(rawLines, edits);
    if (valid.isEmpty) return rawLines;
    final out = List<String>.from(rawLines);
    valid.forEach((i, e) => out[i] = applyOne(rawLines[i], form, e));
    return out;
  }
}
