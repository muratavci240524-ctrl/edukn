import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';

import '../models/odak_models.dart';

/// Kapı listesini (sadece isimler) Excel olarak üretir ve indirir.
/// Her sınıf ayrı bir sayfadır; puan/yüzde/sıralama içermez.
class OdakExcelService {
  static String _trKey(String s) {
    const map = {
      'ç': 'c{', 'ğ': 'g{', 'ı': 'h{', 'ö': 'o{', 'ş': 's{', 'ü': 'u{',
    };
    final lower =
        s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
    final b = StringBuffer();
    for (final ch in lower.split('')) {
      b.write(map[ch] ?? ch);
    }
    return b.toString();
  }

  static String _sheetName(String s, Set<String> used) {
    var n = s.replaceAll(RegExp(r'[\\/*?:\[\]]'), ' ').trim();
    if (n.isEmpty) n = 'Sınıf';
    if (n.length > 28) n = n.substring(0, 28);
    var out = n;
    var i = 2;
    while (used.contains(out)) {
      out = '$n $i';
      i++;
    }
    used.add(out);
    return out;
  }

  static Future<void> saveDoorList({
    required List<OdakClassGroup> groups,
    required String examName,
    String? schoolName,
    Set<String> classIds = const {},
    String fileName = 'Kapi_Listesi',
  }) async {
    final selected =
        groups.where((g) => classIds.isEmpty || classIds.contains(g.id)).toList();
    final excel = Excel.createExcel();
    final used = <String>{};

    final titleStyle = CellStyle(
      bold: true,
      fontSize: 16,
      horizontalAlign: HorizontalAlign.Center,
      fontColorHex: ExcelColor.fromHexString('#0F766E'),
    );
    final subStyle = CellStyle(
      horizontalAlign: HorizontalAlign.Center,
      fontColorHex: ExcelColor.fromHexString('#6B7280'),
    );
    final headStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      backgroundColorHex: ExcelColor.fromHexString('#0F766E'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    );

    for (final g in selected) {
      final names = g.students.map((s) => s.student.name.trim()).toList()
        ..sort((a, b) => _trKey(a).compareTo(_trKey(b)));
      final sheet = excel[_sheetName(g.displayName ?? g.name, used)];

      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0));
      final t = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
      t.value = TextCellValue('${g.displayName ?? g.name} - Sınıf Listesi');
      t.cellStyle = titleStyle;

      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1));
      final sub = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1));
      sub.value = TextCellValue(
          '${schoolName == null || schoolName.isEmpty ? '' : '$schoolName - '}$examName - ${names.length} öğrenci');
      sub.cellStyle = subStyle;

      final h0 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3));
      h0.value = TextCellValue('No');
      h0.cellStyle = headStyle;
      final h1 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 3));
      h1.value = TextCellValue('Ad Soyad');
      h1.cellStyle = headStyle;

      for (var i = 0; i < names.length; i++) {
        final c0 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4 + i));
        c0.value = IntCellValue(i + 1);
        c0.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 4 + i)).value =
            TextCellValue(names[i]);
      }
      sheet.setColumnWidth(0, 8);
      sheet.setColumnWidth(1, 38);
    }
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

    final bytes = excel.save();
    if (bytes == null) throw Exception('Excel oluşturulamadı');
    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: Uint8List.fromList(bytes),
      ext: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }
}
