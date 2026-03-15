import 'package:flutter/material.dart';

class ExamDetailTableScreen extends StatefulWidget {
  final String examName;
  final List<Map<String, dynamic>> results;
  final List<String> availableSubjects;

  const ExamDetailTableScreen({
    Key? key,
    required this.examName,
    required this.results,
    required this.availableSubjects,
  }) : super(key: key);

  @override
  _ExamDetailTableScreenState createState() => _ExamDetailTableScreenState();
}

class _ExamDetailTableScreenState extends State<ExamDetailTableScreen> {
  // Table View Settings
  bool _showColCorrect = false;
  bool _showColWrong = false;
  bool _showColEmpty = false;

  List<String> _selectedClasses = []; // Empty = All
  List<String> _selectedSubjects = []; // Empty = All

  // --- Helper Methods ---

  // --- Persistent Dropdown Helpers ---

  Widget _buildMultiSelectMenu({
    required String label,
    required IconData icon,
    required List<String> items,
    required List<String> selectedItems,
    required Function(List<String>) onChanged,
    required VoidCallback onForceRefresh, // New Param to force rebuild parent
  }) {
    return PopupMenuButton<String>(
      icon: Icon(
        icon,
        color: selectedItems.isNotEmpty ? Colors.indigo : Colors.grey.shade700,
      ),
      tooltip: '$label Filtrele',
      // We don't use onSelected because clicking items is handled inside.
      itemBuilder: (context) {
        // Initialize local state when menu opens to avoid stale closure values
        // If selectedItems is empty, it implies "All" in parent logic,
        // so we potentially need to start with all items checked visually?
        // Logic: filteredData where check checks `selectedClasses.contains`.
        // If empty, logic displays all.
        // So for the *Menu State*, we should likely treat Empty as "All Checkboxes Checked" or "None Checked"?
        // Previous logic: isAllSelected = selectedItems.isEmpty...
        // So we should initialize our temp list to be [items] if selectedItems is empty?
        // PROBABLY YES, so that unchecking one works correctly (removes from full list).

        List<String> tempSelectedItems;
        if (selectedItems.isEmpty) {
          tempSelectedItems = List.from(items);
        } else {
          tempSelectedItems = List.from(selectedItems);
        }

        return [
          PopupMenuItem(
            enabled: false, // Prevents menu from closing on tap
            child: Container(
              width: 300,
              height: 400, // Limit height
              child: StatefulBuilder(
                builder: (context, menuSetState) {
                  // Calculate "All" state based on our LOCAL temp list
                  bool isAllChecked = tempSelectedItems.length == items.length;

                  return Column(
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          "$label Seçimi",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ),
                      Divider(height: 1),
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            CheckboxListTile(
                              title: Text("Tümü"),
                              value: isAllChecked,
                              activeColor: Colors.indigo,
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (val) {
                                if (val == true) {
                                  // Select All -> fill temp list
                                  tempSelectedItems = List.from(items);
                                  // Parent usually expects [] for "All", but sending full list is also valid "All".
                                  // To be consistent with "Empty=All", we can send [];
                                  // But for local state, we need full list to show checks.
                                  // Let's send [] to parent if full.
                                  onChanged([]);
                                } else {
                                  // Unselect All -> Clear temp list
                                  tempSelectedItems.clear();
                                  // Parent expects non-empty to filter. Empty means all.
                                  // This is the tricky part.
                                  // If we want "None Selected" (show nothing), we need a way to say it.
                                  // If we pass an empty list, it shows ALL.
                                  // So technically we cannot show "Nothing".
                                  // Let's assume uncheck all means "Clear Filter" (Show All)?
                                  // Or we can pass a dummy value that matches nothing?
                                  // In this specific app, usually you wouldn't want to see "Nothing".
                                  // So Uncheck All -> Show All (reset) is a fine fallback.
                                  onChanged([]); // Reset
                                }
                                menuSetState(() {});
                                onForceRefresh();
                              },
                            ),
                            ...items.map((item) {
                              final isSelected = tempSelectedItems.contains(
                                item,
                              );

                              return CheckboxListTile(
                                title: Text(item),
                                value: isSelected,
                                activeColor: Colors.indigo,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                onChanged: (val) {
                                  if (val == true) {
                                    if (!tempSelectedItems.contains(item)) {
                                      tempSelectedItems.add(item);
                                    }
                                  } else {
                                    tempSelectedItems.remove(item);
                                  }

                                  // If effectively all are selected, we can send [] to parent
                                  // (if parent logic prefers [] for optimization/logic).
                                  if (tempSelectedItems.length ==
                                      items.length) {
                                    onChanged([]);
                                  } else {
                                    // If empty, parent treats as All.
                                    // If we *really* mean empty (user unchecked last item),
                                    // Parent will show All. This is acceptable UX (resetting).
                                    onChanged(tempSelectedItems);
                                  }

                                  menuSetState(() {});
                                  onForceRefresh(); // Update table BG
                                },
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ];
      },
    );
  }

  Widget _buildColumnVisibilityMenu() {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.view_column_outlined,
        color: (_showColCorrect || _showColWrong || _showColEmpty)
            ? Colors.indigo
            : Colors.grey.shade700,
      ),
      tooltip: 'Sütunları Göster/Gizle',
      itemBuilder: (context) {
        return [
          PopupMenuItem(
            enabled: false,
            child: Container(
              width: 200,
              child: StatefulBuilder(
                builder: (context, menuSetState) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Sütun Görünümü",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      Divider(),
                      CheckboxListTile(
                        title: Text("Doğru (D)"),
                        value: _showColCorrect,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (val) {
                          setState(() => _showColCorrect = val ?? false);
                          menuSetState(() {});
                        },
                      ),
                      CheckboxListTile(
                        title: Text("Yanlış (Y)"),
                        value: _showColWrong,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (val) {
                          setState(() => _showColWrong = val ?? false);
                          menuSetState(() {});
                        },
                      ),
                      CheckboxListTile(
                        title: Text("Boş (B)"),
                        value: _showColEmpty,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (val) {
                          setState(() => _showColEmpty = val ?? false);
                          menuSetState(() {});
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ];
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Filter by Class
    List<Map<String, dynamic>> filteredData = List.from(widget.results);
    if (_selectedClasses.isNotEmpty) {
      filteredData = filteredData
          .where((e) => _selectedClasses.contains(e['className']))
          .toList();
    }

    // Extract unique classes for filter
    final classes =
        widget.results
            .map((e) => e['className']?.toString() ?? '')
            .toSet()
            .toList()
          ..removeWhere((e) => e.isEmpty);
    classes.sort();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.examName),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Filter Bar (Icons Only)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Class Filter
                _buildMultiSelectMenu(
                  label: 'Şube',
                  icon: Icons.maps_home_work_outlined,
                  items: classes,
                  selectedItems: _selectedClasses,
                  onForceRefresh: () => setState(() {}),
                  onChanged: (list) {
                    setState(() {
                      if (list.length == classes.length) {
                        _selectedClasses = [];
                      } else {
                        _selectedClasses = list;
                      }
                    });
                  },
                ),
                SizedBox(width: 8),

                // Subject Filter
                _buildMultiSelectMenu(
                  label: 'Ders',
                  icon: Icons.menu_book_outlined,
                  items: widget.availableSubjects,
                  selectedItems: _selectedSubjects,
                  onForceRefresh: () => setState(() {}),
                  onChanged: (list) {
                    setState(() {
                      if (list.length == widget.availableSubjects.length) {
                        _selectedSubjects = [];
                      } else {
                        _selectedSubjects = list;
                      }
                    });
                  },
                ),
                SizedBox(width: 8),

                // Column Visibility (D/Y/B) - Custom Multi Select Logic
                _buildColumnVisibilityMenu(),
              ],
            ),
          ),

          // Table
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: PaginatedDataTable(
                  header: Text(
                    _selectedSubjects.isEmpty
                        ? 'Detaylı Sonuç Listesi (Tümü)'
                        : '${_selectedSubjects.length} Ders Gösteriliyor',
                  ),
                  headingRowHeight: 65,
                  columns: _buildColumns(),
                  source: _ResultsDataSource(
                    filteredData,
                    availableSubjects: widget.availableSubjects,
                    displayedSubjects: _selectedSubjects.isEmpty
                        ? widget.availableSubjects
                        : _selectedSubjects,
                    showCorrect: _showColCorrect,
                    showWrong: _showColWrong,
                    showEmpty: _showColEmpty,
                  ),
                  rowsPerPage: 24,
                  columnSpacing: 20,
                  showCheckboxColumn: false,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<DataColumn> _buildColumns() {
    List<DataColumn> cols = [
      DataColumn(label: Text('#')),
      DataColumn(label: Text('Ad Soyad')),
      DataColumn(label: Text('Sınıf')),
    ];

    // Determine which subjects to show
    List<String> textSubjects = _selectedSubjects.isEmpty
        ? widget.availableSubjects
        : _selectedSubjects;

    // Add columns for displayed subjects
    for (var subj in textSubjects) {
      cols.add(
        DataColumn(label: _buildStackedHeader(subj), tooltip: '$subj Detay'),
      );
    }

    // Global D/Y/B (Show only if showing ALL subjects, or ALWAYS? User probably wants to see totals for displayed subset)
    // Actually, normally 'Top D' / 'Top Net' refers to FULL exam totals.
    // If I filter Subject columns, user usually still wants accurate TOTALS (not just subset totals).
    // But if "Ders Filtrele" implies focusing on a subset, maybe partial totals?
    // Let's stick to GLOBAL totals for now (safe defaults).
    // Or, should I hide Global Totals if filtering?
    // The previous code had: if showAllSubjects { Show Global Totals } else { Show Net for that subject }.
    // Since we now support Multi-Subject, it acts more like "Hide some columns".
    // I will KEEP displaying Global Totals because that's what the data source computes usually.

    if (_showColCorrect)
      cols.add(
        DataColumn(
          label: Text('Top D', style: TextStyle(color: Colors.green)),
        ),
      );
    if (_showColWrong)
      cols.add(
        DataColumn(
          label: Text('Top Y', style: TextStyle(color: Colors.red)),
        ),
      );
    if (_showColEmpty)
      cols.add(
        DataColumn(
          label: Text('Top B', style: TextStyle(color: Colors.grey)),
        ),
      );

    // Toplam Net
    cols.add(
      DataColumn(
        label: Text('Top. Net', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );

    // Always Total Score at end
    cols.add(DataColumn(label: Text('Puan')));

    // New Ranks
    cols.add(
      DataColumn(
        label: Text(
          'Genel Sıra',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
    cols.add(
      DataColumn(
        label: Text('Şube Sıra', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );

    return cols;
  }

  Widget _buildStackedHeader(String subjectName) {
    bool anyDetail = _showColCorrect || _showColWrong || _showColEmpty;

    if (!anyDetail) {
      return Container(
        width: 50,
        child: Text(
          subjectName,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          subjectName,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showColCorrect)
              Container(
                width: 30,
                child: Center(
                  child: Text(
                    "D",
                    style: TextStyle(fontSize: 11, color: Colors.green),
                  ),
                ),
              ),
            if (_showColWrong)
              Container(
                width: 30,
                child: Center(
                  child: Text(
                    "Y",
                    style: TextStyle(fontSize: 11, color: Colors.red),
                  ),
                ),
              ),
            if (_showColEmpty)
              Container(
                width: 30,
                child: Center(
                  child: Text(
                    "B",
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ),
            Container(
              width: 40,
              child: Center(
                child: Text(
                  "N",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ResultsDataSource extends DataTableSource {
  final List<Map<String, dynamic>> results;
  final List<String> availableSubjects;
  final List<String> displayedSubjects; // New param
  final bool showCorrect;
  final bool showWrong;
  final bool showEmpty;

  _ResultsDataSource(
    this.results, {
    required this.availableSubjects,
    required this.displayedSubjects,
    this.showCorrect = false,
    this.showWrong = false,
    this.showEmpty = false,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= results.length) return null;
    final result = results[index];

    // Rank
    // User requested simple row index for #
    int displayIndex = index + 1;

    List<DataCell> cells = [
      DataCell(
        Container(
          padding: EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: displayIndex <= 3
                ? Colors.orange.shade100
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Text(
            displayIndex.toString(),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
      ),
      DataCell(Text(result['studentName']?.toString() ?? '-')),
      DataCell(Text(result['className']?.toString() ?? '-')),
    ];

    Map<String, dynamic> subjectsMap = {};
    if (result['subjects'] != null && result['subjects'] is Map) {
      subjectsMap = result['subjects'];
    }

    // Loop through DISPLAYED subjects only
    for (var subj in displayedSubjects) {
      String netVal = '-';
      String c = '-', w = '-', e = '-';

      if (subjectsMap.containsKey(subj) && subjectsMap[subj] is Map) {
        final sData = subjectsMap[subj];
        double n =
            num.tryParse(sData['net']?.toString() ?? '0')?.toDouble() ?? 0.0;
        netVal = n.toStringAsFixed(2);

        int ci = int.tryParse(sData['correct']?.toString() ?? '0') ?? 0;
        int wi = int.tryParse(sData['wrong']?.toString() ?? '0') ?? 0;
        int ei = int.tryParse(sData['empty']?.toString() ?? '0') ?? 0;

        c = ci.toString();
        w = wi.toString();
        e = ei.toString();
      }

      // Build Cell Content
      bool anyDetail = showCorrect || showWrong || showEmpty;
      if (!anyDetail) {
        cells.add(
          DataCell(
            Center(
              child: Text(
                netVal,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        );
      } else {
        cells.add(
          DataCell(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showCorrect)
                  Container(
                    width: 30,
                    child: Center(
                      child: Text(
                        c,
                        style: TextStyle(fontSize: 12, color: Colors.green),
                      ),
                    ),
                  ),
                if (showWrong)
                  Container(
                    width: 30,
                    child: Center(
                      child: Text(
                        w,
                        style: TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ),
                if (showEmpty)
                  Container(
                    width: 30,
                    child: Center(
                      child: Text(
                        e,
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ),
                Container(
                  width: 40,
                  child: Center(
                    child: Text(
                      netVal,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    // Global Totals (Calculated from result item directly for accuracy)

    // Note: If we want to recalculate totals based on filtered subjects, we could.
    // But typically "Total Net" means Exam Total.
    // I will use the pre-calculated 'totalNet' from the record.

    int globalCorrect = 0, globalWrong = 0, globalEmpty = 0;
    // Recalculate global D/Y/B for display?
    // If the data source has it, better. BUT 'subjectsMap' has details.
    // Let's iterate ALL available subjects to get Global D/Y/B sums correctly, regardless of display.
    for (var subj in availableSubjects) {
      if (subjectsMap.containsKey(subj) && subjectsMap[subj] is Map) {
        final sData = subjectsMap[subj];
        globalCorrect += int.tryParse(sData['correct']?.toString() ?? '0') ?? 0;
        globalWrong += int.tryParse(sData['wrong']?.toString() ?? '0') ?? 0;
        globalEmpty += int.tryParse(sData['empty']?.toString() ?? '0') ?? 0;
      }
    }

    if (showCorrect)
      cells.add(
        DataCell(
          Text(globalCorrect.toString(), style: TextStyle(color: Colors.green)),
        ),
      );
    if (showWrong)
      cells.add(
        DataCell(
          Text(globalWrong.toString(), style: TextStyle(color: Colors.red)),
        ),
      );
    if (showEmpty)
      cells.add(
        DataCell(
          Text(globalEmpty.toString(), style: TextStyle(color: Colors.grey)),
        ),
      );

    double totalNet =
        double.tryParse(result['totalNet']?.toString() ?? '0') ?? 0.0;
    cells.add(
      DataCell(
        Text(
          totalNet.toStringAsFixed(2),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );

    double score =
        double.tryParse(result['totalScore']?.toString() ?? '0') ?? 0.0;
    cells.add(
      DataCell(
        Text(
          score.toStringAsFixed(3),
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
        ),
      ),
    );

    // Genel Sıra
    cells.add(
      DataCell(
        Center(
          child: Text(
            result['rankGeneral']?.toString() ?? '-',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );

    // Şube Sıra
    cells.add(
      DataCell(Center(child: Text(result['rankBranch']?.toString() ?? '-'))),
    );

    return DataRow(cells: cells);
  }

  @override
  bool get isRowCountApproximate => false;
  @override
  int get rowCount => results.length;
  @override
  int get selectedRowCount => 0;
}
