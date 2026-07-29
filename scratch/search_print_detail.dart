import 'dart:io';

void main() async {
  final file = File(r"c:\Users\user\Desktop\eduKN\edukn\edukn21.11.2025\edukn\lib\screens\school\student_registration_screen.dart");
  final content = await file.readAsString();
  
  // Search for buttons or texts like 'sil', 'yazdir', 'yazdır', 'print'
  final lowercase = content.toLowerCase();
  
  final keywords = ["yazdır", "yazdir", "print", "sil", "delete"];
  for (var kw in keywords) {
    int count = 0;
    int index = lowercase.indexOf(kw);
    while (index != -1) {
      count++;
      index = lowercase.indexOf(kw, index + kw.length);
    }
    print("Keyword '$kw': $count occurrences");
    if (count > 0) {
      int idx = lowercase.indexOf(kw);
      int lineNo = 1;
      for (int i = 0; i < idx; i++) {
        if (content[i] == '\n') lineNo++;
      }
      print("  First occurrence around line $lineNo");
    }
  }
}
