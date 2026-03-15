void main() {
  String normalize(String s) {
    String n = s
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g');
    n = n.replaceAll(RegExp(r'[.,;:\-()\\"\’\‘\“\”\!\x27]'), '');
    return n.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String stripCode(String s) {
    String result = s.trim();
    // Allow any letter (including unicode) for the prefix: İTA.8.2.2
    final regex = RegExp(
      r'^\p{L}*\.?[0-9]+(\.[A-Z0-9]+)*[.\s]+',
      caseSensitive: false,
      unicode: true,
    );

    while (true) {
      String stripped = result.replaceFirst(regex, '').trim();
      if (stripped == result) break;
      result = stripped;
    }
    return result;
  }

  String t1 =
      "Birinci Dünya Savaşı'nda Osmanlı Devleti'nin durumu hakkında çıkarımlarda bulunur.";
  String t2 =
      "İTA.8.2.2 Birinci Dünya Savaşı’nda Osmanlı Devleti’nin durumu hakkında çıkarımlarda bulunur.";

  print(normalize(stripCode(t1)));
  print(normalize(stripCode(t2)));
  print(normalize(stripCode(t1)) == normalize(stripCode(t2)));
}
