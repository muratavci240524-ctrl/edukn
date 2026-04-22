import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';

class ExcelService {
  /// Sınıf veya Öğretmen bazlı ders programını Excel formatında üretir.
  Future<void> exportScheduleToExcel({
    required String title,
    required List<String> days,
    required List<Map<String, dynamic>> lessonHours,
    required Map<String, dynamic> scheduleData, // Key: "day_hourIndex", Value: {lessonName, teacherName/className}
    required Map<String, String> institutionInfo,
    required String fileName,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Ders Programı'];
    excel.delete('Sheet1'); // Temiz başlangıç

    // Başlık Stilİ
    final cellStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      backgroundColorHex: ExcelColor.fromHexString('#4F46E5'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    );

    // Kurum Bilgileri
    sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
        CellIndex.indexByColumnRow(columnIndex: days.length, rowIndex: 0));
    var cellTitle = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
    cellTitle.value = TextCellValue('T.C. ${institutionInfo['city']?.toUpperCase() ?? ''} - ${institutionInfo['district']?.toUpperCase() ?? ''}');
    cellTitle.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center, bold: true);

    sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
        CellIndex.indexByColumnRow(columnIndex: days.length, rowIndex: 1));
    var cellSchool = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1));
    cellSchool.value = TextCellValue(institutionInfo['schoolName'] ?? '');
    cellSchool.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center, bold: true, fontSize: 14);

    sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2),
        CellIndex.indexByColumnRow(columnIndex: days.length, rowIndex: 2));
    var cellSub = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2));
    cellSub.value = TextCellValue(title);
    cellSub.cellStyle = CellStyle(
      horizontalAlign: HorizontalAlign.Center, 
      bold: true, 
      fontColorHex: ExcelColor.fromHexString('#4F46E5'),
    );

    // Header: Günler
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4)).value = TextCellValue('Saat / Gün');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4)).cellStyle = cellStyle;

    for (var i = 0; i < days.length; i++) {
      var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i + 1, rowIndex: 4));
      cell.value = TextCellValue(days[i]);
      cell.cellStyle = cellStyle;
    }

    // Satırlar: Ders Saatleri
    for (var h = 0; h < lessonHours.length; h++) {
      final hour = lessonHours[h];
      final timeStr = '${hour['startTime']} - ${hour['endTime']}';
      
      var timeCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 5 + h));
      timeCell.value = TextCellValue('${h + 1}. Ders\n$timeStr');
      timeCell.cellStyle = CellStyle(verticalAlign: VerticalAlign.Center, backgroundColorHex: ExcelColor.fromHexString('#F3F4F6'));

      for (var d = 0; d < days.length; d++) {
        final key = '${days[d]}_$h';
        final data = scheduleData[key];
        
        var dataCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: d + 1, rowIndex: 5 + h));
        if (data != null) {
          final lessonName = data['lessonName'] ?? '';
          final secondary = data['teacherName'] ?? data['className'] ?? '';
          dataCell.value = TextCellValue('$lessonName\n$secondary');
          dataCell.cellStyle = CellStyle(
            horizontalAlign: HorizontalAlign.Center,
            verticalAlign: VerticalAlign.Center,
          );
        } else {
          dataCell.value = TextCellValue('-');
        }
      }
    }

    // Export
    final bytes = excel.save();
    if (bytes != null) {
      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: Uint8List.fromList(bytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
    }
  }

  /// Çarşaf Liste Excel (Toplu Görünüm)
  Future<void> exportMasterScheduleToExcel({
    required List<String> days,
    required List<Map<String, dynamic>> lessonHours,
    required List<Map<String, dynamic>> rows, // List of {name, scheduleData}
    required Map<String, String> institutionInfo,
    required String typeLabel, // "Sınıflar" veya "Öğretmenler"
    required String fileName,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Çarşaf Liste'];
    excel.delete('Sheet1');

    // Başlık
    sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
        CellIndex.indexByColumnRow(columnIndex: days.length * lessonHours.length, rowIndex: 0));
    var titleCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
    titleCell.value = TextCellValue('Toplu Çarşaf Liste: $typeLabel');
    titleCell.cellStyle = CellStyle(bold: true, horizontalAlign: HorizontalAlign.Center, fontSize: 16);

    // Days Header Row
    int currentColumn = 1;
    for (var day in days) {
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: currentColumn, rowIndex: 2),
        CellIndex.indexByColumnRow(columnIndex: currentColumn + lessonHours.length - 1, rowIndex: 2)
      );
      var dayCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: currentColumn, rowIndex: 2));
      dayCell.value = TextCellValue(day);
      dayCell.cellStyle = CellStyle(bold: true, horizontalAlign: HorizontalAlign.Center, backgroundColorHex: ExcelColor.fromHexString('#E5E7EB'));
      
      // Hour Header Sub-Row
      for (var h = 0; h < lessonHours.length; h++) {
        var hCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: currentColumn + h, rowIndex: 3));
        hCell.value = TextCellValue('${h + 1}');
        hCell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center, fontSize: 8);
      }
      
      currentColumn += lessonHours.length;
    }

    // Row Data (Classes or Teachers)
    for (var r = 0; r < rows.length; r++) {
      final rowData = rows[r];
      final name = rowData['name'] as String;
      final schedule = rowData['scheduleData'] as Map<String, dynamic>;

      var nameCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4 + r));
      nameCell.value = TextCellValue(name);
      nameCell.cellStyle = CellStyle(bold: true);

      int colOffset = 1;
      for (var day in days) {
        for (var h = 0; h < lessonHours.length; h++) {
          final key = '${day}_$h';
          final data = schedule[key];
          var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colOffset + h, rowIndex: 4 + r));
          
          if (data != null) {
            final lessonName = data['lessonName'] ?? '';
            final secondary = data['teacherName'] ?? data['className'] ?? '';
            cell.value = TextCellValue('$lessonName\n$secondary');
            cell.cellStyle = CellStyle(fontSize: 8);
          } else {
            cell.value = TextCellValue('');
          }
        }
        colOffset += lessonHours.length;
      }
    }

    final bytes = excel.save();
    if (bytes != null) {
      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: Uint8List.fromList(bytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
    }
  }
}
