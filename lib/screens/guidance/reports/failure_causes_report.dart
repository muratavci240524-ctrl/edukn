import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:flutter/gestures.dart'; // For ScrollBehavior
import 'package:excel/excel.dart' hide Border; // For Excel Export
import 'package:file_saver/file_saver.dart'; // For saving file
import 'dart:typed_data'; // For Bytes

class FailureCausesReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const FailureCausesReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<FailureCausesReport> createState() => _FailureCausesReportState();
}

class _FailureCausesReportState extends State<FailureCausesReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadFilterData();
  }

  // Filters
  String _selectedScope = 'institution'; // institution, branch, student
  String? _selectedBranch;
  String? _selectedStudent;
  bool _filtersExpanded = true;

  // Data for filters
  bool _isLoadingFilterData = false;
  List<Map<String, dynamic>> _branches = [];
  Map<String, Map<String, dynamic>> _userDetails =
      {}; // userId -> {branch: '...', schoolType: '...'}

  Future<void> _loadFilterData() async {
    setState(() => _isLoadingFilterData = true);
    try {
      final instId = widget.survey.institutionId;

      // 1. Fetch Branches
      final branchesSnapshot = await FirebaseFirestore.instance
          .collection('branches')
          .where('institutionId', isEqualTo: instId)
          .get();

      _branches = branchesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'],
          'schoolTypeId': data['schoolTypeId'],
        };
      }).toList();

      // 2. Fetch User Details
      // We need to know the branch of each respondent
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: instId)
          .where(
            'role',
            isEqualTo: 'Öğrenci',
          ) // Optimization: Only fetch students
          .get();

      for (var doc in usersSnapshot.docs) {
        final data = doc.data();
        _userDetails[doc.id] = {
          'branch': data['branch'],
          'schoolType': data['schoolType'],
          'firstName': data['firstName'], // Optional: for better matching
        };
      }
    } catch (e) {
      print('Filter data load error: $e');
    }
    if (mounted) setState(() => _isLoadingFilterData = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.survey.sections.isEmpty ||
        widget.survey.sections.first.questions.isEmpty) {
      return Center(child: Text('Anket içeriği hatalı.'));
    }

    final mainQuestion = widget.survey.sections.first.questions.first;
    final options = mainQuestion.options;

    // Apply Filters to Responses
    List<Map<String, dynamic>> filteredResponses = widget.responses.where((r) {
      if (_selectedScope == 'institution') return true;

      final uid = r['userId'].toString();
      // If filtering by student
      if (_selectedScope == 'student') {
        return _selectedStudent == null || uid == _selectedStudent;
      }

      // If filtering by branch
      if (_selectedScope == 'branch') {
        // We need to know if this user is in the selected branch
        final userBranch = _userDetails[uid]?['branch'];
        return _selectedBranch == null || userBranch == _selectedBranch;
      }

      return true;
    }).toList();

    return Column(
      children: [
        // STYLISH FILTER BAR
        Container(
          margin: EdgeInsets.all(16),
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Rapor Filtreleri',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.indigo,
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        setState(() => _filtersExpanded = !_filtersExpanded),
                    icon: Icon(
                      _filtersExpanded
                          ? Icons.filter_list_off
                          : Icons.filter_list,
                      color: Colors.indigo,
                    ),
                    tooltip: _filtersExpanded
                        ? 'Filtreleri Gizle'
                        : 'Filtreleri Göster',
                  ),
                ],
              ),
              if (_filtersExpanded) ...[
                Divider(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 500;

                    if (isMobile) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildScopeFilter(),
                          SizedBox(height: 16),
                          _buildSubFilter(),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: _buildScopeFilter()),
                        SizedBox(width: 16),
                        Expanded(flex: 3, child: _buildSubFilter()),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),

        LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 450;
            return Container(
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: isMobile,
                      labelColor: Colors.indigo,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Colors.indigo,
                      tabAlignment: isMobile ? TabAlignment.start : null,
                      padding: EdgeInsets.zero,
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 12 : 14,
                      ),
                      tabs: [
                        Tab(text: 'Sıralı Analiz'),
                        Tab(text: 'Döküm Tablosu'),
                        Tab(text: 'Analiz Özeti'),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: TextButton.icon(
                      onPressed: () => _exportToExcel(options, mainQuestion.id),
                      icon: Icon(Icons.download_rounded, size: 18),
                      label: Text(
                        'Excel',
                        style: TextStyle(fontSize: isMobile ? 12 : 14),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        Expanded(
          child: ScrollConfiguration(
            behavior: MyCustomScrollBehavior(),
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildGeneralAnalysis(
                  options,
                  mainQuestion.id,
                  filteredResponses,
                ),
                _buildTallySheet(options, mainQuestion.id, filteredResponses),
                _buildSummaryAnalysis(
                  options,
                  mainQuestion.id,
                  filteredResponses,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScopeFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Kapsam',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedScope,
              isExpanded: true,
              items: [
                DropdownMenuItem(
                  value: 'institution',
                  child: Row(
                    children: [
                      Icon(Icons.school, size: 18, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text('Genel (Tüm Kurum)'),
                    ],
                  ),
                ),
                DropdownMenuItem(
                  value: 'branch',
                  child: Row(
                    children: [
                      Icon(Icons.class_, size: 18, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Şube Bazlı'),
                    ],
                  ),
                ),
                DropdownMenuItem(
                  value: 'student',
                  child: Row(
                    children: [
                      Icon(Icons.person, size: 18, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Öğrenci Bazlı'),
                    ],
                  ),
                ),
              ],
              onChanged: (val) {
                if (val != null)
                  setState(() {
                    _selectedScope = val;
                    _selectedBranch = null; // Reset sub-filters
                    _selectedStudent = null;
                  });
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubFilter() {
    if (_selectedScope == 'institution') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bilgi',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Container(
            constraints: BoxConstraints(minHeight: 48),
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Tüm kurum verileri gösteriliyor',
              style: TextStyle(color: Colors.indigo),
            ),
          ),
        ],
      );
    }

    if (_selectedScope == 'branch') {
      // BRANCH DROPDOWN (Need data)
      // For now using placeholder items if empty, waiting for real data impl.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Şube Seç',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedBranch,
                isExpanded: true,
                hint: Text('Şube seçiniz...'),
                items: _branches
                    .map(
                      (b) => DropdownMenuItem(
                        value: b['id'].toString(),
                        child: Text(b['name']),
                      ),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedBranch = val),
              ),
            ),
          ),
        ],
      );
    }

    if (_selectedScope == 'student') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Öğrenci Seç',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedStudent,
                isExpanded: true,
                hint: Text('Öğrenci arayın veya seçin...'),
                // In real usage this should be a Searchable Dropdown or Autocomplete
                items: [
                  DropdownMenuItem(value: null, child: Text('Tüm Öğrenciler')),
                  ...widget.userNames.entries.map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ),
                ],
                onChanged: (val) => setState(() => _selectedStudent = val),
              ),
            ),
          ),
        ],
      );
    }

    return SizedBox();
  }

  // Update methods to accept responses list
  Widget _buildGeneralAnalysis(
    List<String> options,
    String questionId,
    List<Map<String, dynamic>> dataSources,
  ) {
    // Use dataSources instead of widget.responses

    // 1. Calculate frequencies
    Map<int, int> counts = {};
    for (int i = 0; i < options.length; i++) counts[i] = 0;

    for (var resp in dataSources) {
      final answers = resp['answers'] as Map<String, dynamic>?;
      if (answers == null) continue;

      final userSelection = answers[questionId];
      if (userSelection is List) {
        for (var selectedOption in userSelection) {
          final idx = options.indexOf(selectedOption.toString());
          if (idx != -1) {
            counts[idx] = (counts[idx] ?? 0) + 1;
          }
        }
      }
    }

    final totalRespondents = dataSources.length;
    final total = totalRespondents == 0 ? 1 : totalRespondents;

    // ... rest of method using 'counts' and 'total'
    // Copy-paste existing logic but use locals

    final sortedIndices = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));

    return ListView(
      padding: EdgeInsets.all(24),
      children: [
        _buildHeaderCard('Analiz Sonuçları'),
        SizedBox(height: 16),
        ...sortedIndices.map((idx) {
          // ... same visualization logic
          final count = counts[idx]!;
          final percent = (count / total * 100);
          final optionText = options[idx];
          final itemNumber = idx + 1;
          return Card(
            margin: EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.indigo.shade100),
                        ),
                        child: Text(
                          '$itemNumber',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          optionText,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$count Kişi',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '%${percent.toStringAsFixed(1)}',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: count / total,
                      backgroundColor: Colors.grey[100],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        percent > 50
                            ? Colors.red
                            : (percent > 25 ? Colors.orange : Colors.green),
                      ),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildTallySheet(
    List<String> options,
    String questionId,
    List<Map<String, dynamic>> dataSources,
  ) {
    // Use dataSources instead of widget.responses
    // ... logic ...
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      padding: EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          child: Table(
            defaultColumnWidth: FixedColumnWidth(40),
            columnWidths: {0: FixedColumnWidth(200)},
            border: TableBorder.all(color: Colors.grey.shade300),
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.indigo.shade50),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Öğrenci Adı',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  ...List.generate(
                    options.length,
                    (index) => Container(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      alignment: Alignment.center,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              ...dataSources.map((resp) {
                final uid = resp['userId'].toString();
                final name = widget.userNames[uid] ?? 'Bilinmeyen';
                final answers = resp['answers'] as Map<String, dynamic>?;
                final userSelection = (answers?[questionId] as List?) ?? [];
                final selectedIndices = userSelection
                    .map((s) => options.indexOf(s.toString()))
                    .toSet();

                return TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        name,
                        style: TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...List.generate(options.length, (index) {
                      final isSelected = selectedIndices.contains(index);
                      return Container(
                        height: 35,
                        alignment: Alignment.center,
                        color: isSelected ? Colors.red.withOpacity(0.1) : null,
                        child: isSelected
                            ? Icon(Icons.close, color: Colors.red, size: 16)
                            : null,
                      );
                    }),
                  ],
                );
              }).toList(),
              // Totals Row
              TableRow(
                decoration: BoxDecoration(color: Colors.grey.shade100),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'TOPLAM',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  ...List.generate(options.length, (index) {
                    int sum = 0;
                    for (var r in dataSources) {
                      final a = (r['answers']?[questionId] as List?) ?? [];
                      if (a.contains(options[index])) sum++;
                    }
                    return Container(
                      height: 35,
                      alignment: Alignment.center,
                      child: Text(
                        '$sum',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportToExcel(List<String> options, String questionId) async {
    try {
      var excel = Excel.createExcel();

      // Common Styles
      CellStyle headerStyle = CellStyle(
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
        backgroundColorHex: ExcelColor.fromHexString(
          '#E8EAF6',
        ), // indigo shade 50
      );

      CellStyle centerStyle = CellStyle(
        horizontalAlign: HorizontalAlign.Center,
      );
      CellStyle boldStyle = CellStyle(bold: true);

      // 1. SHEET: QUESTION LIST (Soru Listesi)
      Sheet qSheet = excel['Soru Listesi'];
      qSheet.appendRow([TextCellValue('No'), TextCellValue('Soru / Neden')]);
      for (int i = 0; i < options.length; i++) {
        qSheet.appendRow([IntCellValue(i + 1), TextCellValue(options[i])]);
      }

      // 2. SHEET: TALLY SHEET (Döküm Tablosu)
      Sheet tSheet = excel['Döküm Tablosu'];

      // Apply Filters as in UI
      List<Map<String, dynamic>> filteredResponses = widget.responses.where((
        r,
      ) {
        if (_selectedScope == 'institution') return true;
        final uid = r['userId'].toString();
        if (_selectedScope == 'student') {
          return _selectedStudent == null || uid == _selectedStudent;
        }
        if (_selectedScope == 'branch') {
          final userBranch = _userDetails[uid]?['branch'];
          return _selectedBranch == null || userBranch == _selectedBranch;
        }
        return true;
      }).toList();

      // Header Row: Student Name, 1, 2, 3..., Total
      List<CellValue> headerNamesArr = [TextCellValue('Öğrenci Adı')];
      for (int i = 1; i <= options.length; i++) {
        headerNamesArr.add(IntCellValue(i));
      }
      headerNamesArr.add(TextCellValue('TOPLAM'));
      tSheet.appendRow(headerNamesArr);

      // Apply header styling
      for (int i = 0; i < headerNamesArr.length; i++) {
        var cell = tSheet.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
        );
        cell.cellStyle = headerStyle;
      }

      // Data Rows
      for (int rIndex = 0; rIndex < filteredResponses.length; rIndex++) {
        var resp = filteredResponses[rIndex];
        final uid = resp['userId'].toString();
        final name = widget.userNames[uid] ?? 'Bilinmeyen';
        final answers = resp['answers'] as Map<String, dynamic>?;
        final userSelection = (answers?[questionId] as List?) ?? [];

        final selectedIndices = userSelection
            .map((s) => options.indexOf(s.toString()))
            .toSet();

        List<CellValue> rowData = [TextCellValue(name)];
        int totalSelected = 0;

        for (int i = 0; i < options.length; i++) {
          if (selectedIndices.contains(i)) {
            rowData.add(TextCellValue('X'));
            totalSelected++;
          } else {
            rowData.add(TextCellValue(''));
          }
        }
        rowData.add(IntCellValue(totalSelected));
        tSheet.appendRow(rowData);

        // Center alignment for the markers and totals
        for (int i = 1; i < rowData.length; i++) {
          var cell = tSheet.cell(
            CellIndex.indexByColumnRow(columnIndex: i, rowIndex: rIndex + 1),
          );
          cell.cellStyle = centerStyle;
        }
      }

      // Totals Row (Matching UI)
      int lastRowIdx = tSheet.maxRows;
      List<CellValue> totalsRowArr = [TextCellValue('GENEL TOPLAM')];
      int grandTotal = 0;
      for (int i = 0; i < options.length; i++) {
        int sum = 0;
        for (var r in filteredResponses) {
          final a = (r['answers']?[questionId] as List?) ?? [];
          if (a.contains(options[i])) sum++;
        }
        totalsRowArr.add(IntCellValue(sum));
        grandTotal += sum;
      }
      totalsRowArr.add(IntCellValue(grandTotal));
      tSheet.appendRow(totalsRowArr);

      // Apply bold and center to last row
      for (int i = 0; i < totalsRowArr.length; i++) {
        var cell = tSheet.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: lastRowIdx),
        );
        cell.cellStyle = i == 0
            ? boldStyle
            : CellStyle(bold: true, horizontalAlign: HorizontalAlign.Center);
      }

      // 3. SHEET: SUMMARY ANALYSIS (Analiz Özeti)
      Sheet sSheet = excel['Analiz Özeti'];
      List<CellValue> sHeader = [
        TextCellValue('No'),
        TextCellValue('Başarısızlık Nedeni'),
        TextCellValue('Frekans (Kişi)'),
        TextCellValue('Puan (Her Cevap 1 Puan)'),
        TextCellValue('Yüzde (%)'),
      ];
      sSheet.appendRow(sHeader);
      for (int i = 0; i < sHeader.length; i++) {
        sSheet
                .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
                .cellStyle =
            headerStyle;
      }

      final totalRespondents = filteredResponses.length == 0
          ? 1
          : filteredResponses.length;
      for (int i = 0; i < options.length; i++) {
        int count = 0;
        for (var r in filteredResponses) {
          final a = (r['answers']?[questionId] as List?) ?? [];
          if (a.contains(options[i])) count++;
        }
        double percent = (count / totalRespondents) * 100;

        sSheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue(options[i]),
          IntCellValue(count),
          IntCellValue(count), // 1 point each
          TextCellValue('%${percent.toStringAsFixed(1)}'),
        ]);

        // Center alignment for numeric columns
        for (int col in [0, 2, 3, 4]) {
          sSheet
                  .cell(
                    CellIndex.indexByColumnRow(
                      columnIndex: col,
                      rowIndex: i + 1,
                    ),
                  )
                  .cellStyle =
              centerStyle;
        }
      }

      // Delete default Sheet1 if exists
      excel.delete('Sheet1');
      excel.delete('Sayfa1');

      // Save
      var fileBytes = excel.save();
      if (fileBytes != null) {
        await FileSaver.instance.saveFile(
          name: 'basarisizlik_nedenleri_rapor',
          bytes: Uint8List.fromList(fileBytes),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Excel başarıyla indirildi.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Widget _buildSummaryAnalysis(
    List<String> options,
    String questionId,
    List<Map<String, dynamic>> dataSources,
  ) {
    final totalRespondents = dataSources.length == 0 ? 1 : dataSources.length;

    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        _buildHeaderCard('Analiz Özeti'),
        SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 4),
                    ],
                  ),
                  child: DataTable(
                    headingRowColor: MaterialStateProperty.all(
                      Colors.indigo.shade50,
                    ),
                    dataRowMaxHeight: 60,
                    columns: const [
                      DataColumn(
                        label: Text(
                          'No',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Neden',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Frekans',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Puan',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Yüzde',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    rows: List.generate(options.length, (index) {
                      int count = 0;
                      for (var r in dataSources) {
                        final a = (r['answers']?[questionId] as List?) ?? [];
                        if (a.contains(options[index])) count++;
                      }
                      double percent = (count / totalRespondents) * 100;

                      return DataRow(
                        cells: [
                          DataCell(Text('${index + 1}')),
                          DataCell(
                            Container(
                              width:
                                  500, // Increased for better layout coverage
                              child: Text(options[index], softWrap: true),
                            ),
                          ),
                          DataCell(Center(child: Text('$count'))),
                          DataCell(
                            Center(child: Text('$count')),
                          ), // Each is 1 point
                          DataCell(Text('%${percent.toStringAsFixed(1)}')),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHeaderCard(String title) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.indigo, Colors.blue]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.analytics, color: Colors.white),
          SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// Custom scroll behavior for mouse dragging
class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
  };
}
