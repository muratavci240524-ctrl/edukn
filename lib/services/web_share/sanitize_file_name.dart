/// Dosya adlarındaki Türkçe karakterleri ve geçersiz karakterleri
/// Web Share API, tarayıcı dosya indirme ve işletim sistemi standartlarına uygun
/// temiz ASCII formatına dönüştürür.
String sanitizeFileName(String fileName) {
  final lastDot = fileName.lastIndexOf('.');
  String base = lastDot != -1 ? fileName.substring(0, lastDot) : fileName;
  String ext = lastDot != -1 ? fileName.substring(lastDot) : '';

  base = base
      .replaceAll('ı', 'i')
      .replaceAll('I', 'I')
      .replaceAll('İ', 'I')
      .replaceAll('ş', 's')
      .replaceAll('Ş', 'S')
      .replaceAll('ğ', 'g')
      .replaceAll('Ğ', 'G')
      .replaceAll('ü', 'u')
      .replaceAll('Ü', 'U')
      .replaceAll('ö', 'o')
      .replaceAll('Ö', 'O')
      .replaceAll('ç', 'c')
      .replaceAll('Ç', 'C')
      .replaceAll('â', 'a')
      .replaceAll('Â', 'A')
      .replaceAll('î', 'i')
      .replaceAll('Î', 'I')
      .replaceAll('û', 'u')
      .replaceAll('Û', 'U');

  base = base.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
  base = base.replaceAll(RegExp(r'^_+|_+$'), '');
  if (base.isEmpty) base = 'dosya';

  ext = ext.toLowerCase().trim();
  if (ext.isNotEmpty && !ext.startsWith('.')) {
    ext = '.$ext';
  }
  return '$base$ext';
}
