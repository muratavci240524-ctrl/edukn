import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import '../../../../models/assessment/exam_type_model.dart';
import '../../../../models/assessment/outcome_list_model.dart';
import 'outcome_matching_screen.dart';

class TrialExamAnswerKeyScreen extends StatefulWidget {
  final int bookletCount;
  final ExamType examType;
  final Map<String, Map<String, String>> initialAnswerKeys;
  final Map<String, Map<String, List<String>>> initialOutcomes;

  const TrialExamAnswerKeyScreen({
    Key? key,
    required this.bookletCount,
    required this.examType,
    required this.initialAnswerKeys,
    required this.initialOutcomes,
  }) : super(key: key);

  @override
  State<TrialExamAnswerKeyScreen> createState() =>
      _TrialExamAnswerKeyScreenState();
}

class _TrialExamAnswerKeyScreenState extends State<TrialExamAnswerKeyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Data State
  late Map<String, Map<String, String>> _answerKeys;
  late Map<String, Map<String, List<String>>> _outcomes;
  late Map<String, Map<String, List<String>>>
  _k12Codes; // New state for K12 Codes
  late Map<String, Map<String, List<String>>>
  _kazanimCodes; // New state for Kazanım Codes

  // Controllers are transient, we will rebuild them from state when needed or keep a cache
  // Caching controllers for performance
  final Map<String, Map<String, TextEditingController>> _keyControllers = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.bookletCount, vsync: this);

    // Robust Deep Copy & Casting used to prevent LinkedMap<dynamic, dynamic> errors
    _answerKeys = {};
    if (widget.initialAnswerKeys.isNotEmpty) {
      widget.initialAnswerKeys.forEach((booklet, subjects) {
        _answerKeys[booklet.toString()] = {};
        subjects.forEach((subject, value) {
          _answerKeys[booklet.toString()]![subject.toString()] = value
              .toString();
        });
      });
    }

    _outcomes = {};
    if (widget.initialOutcomes.isNotEmpty) {
      widget.initialOutcomes.forEach((booklet, subjects) {
        _outcomes[booklet.toString()] = {};
        subjects.forEach((subject, value) {
          if (value is List) {
            _outcomes[booklet.toString()]![subject.toString()] = value
                .map((e) => e.toString())
                .toList();
          }
        });
      });
    }

    _k12Codes = {};
    _kazanimCodes = {};
    // Initialize K12 Codes structure (empty initially)
    _initializeControllers();
  }

  void _initializeControllers() {
    List<String> bookletNames = List.generate(
      widget.bookletCount,
      (index) => String.fromCharCode(65 + index),
    );

    for (var booklet in bookletNames) {
      _keyControllers.putIfAbsent(booklet, () => {});
      _answerKeys.putIfAbsent(booklet, () => {});
      _outcomes.putIfAbsent(booklet, () => {}); // Ensure initial map exists
      _k12Codes.putIfAbsent(booklet, () => {});
      _kazanimCodes.putIfAbsent(booklet, () => {});

      for (var subject in widget.examType.subjects) {
        String currentKey = _answerKeys[booklet]?[subject.branchName] ?? '';

        if (!_keyControllers[booklet]!.containsKey(subject.branchName)) {
          _keyControllers[booklet]![subject.branchName] = TextEditingController(
            text: currentKey,
          );
          _keyControllers[booklet]![subject.branchName]!.addListener(() {
            _answerKeys[booklet]![subject.branchName] =
                _keyControllers[booklet]![subject.branchName]!.text;
            setState(() {}); // Rebuild for counter
          });
        } else {
          _keyControllers[booklet]![subject.branchName]!.text = currentKey;
        }

        // Initialize outcomes list if missing
        if (!_outcomes[booklet]!.containsKey(subject.branchName)) {
          _outcomes[booklet]![subject.branchName] = List.filled(
            subject.questionCount,
            '',
          );
        }
        if (!_k12Codes[booklet]!.containsKey(subject.branchName)) {
          _k12Codes[booklet]![subject.branchName] = List.filled(
            subject.questionCount,
            '',
          );
        }
        if (!_kazanimCodes[booklet]!.containsKey(subject.branchName)) {
          _kazanimCodes[booklet]![subject.branchName] = List.filled(
            subject.questionCount,
            '',
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var booklet in _keyControllers.values) {
      for (var ctrl in booklet.values) {
        ctrl.dispose();
      }
    }
    super.dispose();
  }

  void _onSave() {
    Navigator.pop(context, {'answerKeys': _answerKeys, 'outcomes': _outcomes});
  }

  Future<void> _matchSubjectOutcomes(String booklet) async {
    // Helper for normalization
    String normalize(String s) {
      return s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase().trim();
    }

    // Capture original state for mapping
    final originalBookletState = <String, List<String>>{};
    if (_outcomes[booklet] != null) {
      _outcomes[booklet]!.forEach(
        (k, v) => originalBookletState[k] = List.from(v),
      );
    }

    // Prepare Maps
    // Prepare Maps
    final outcomesMap = <String, List<OutcomeItem>>{};
    final bookletOutcomes = _outcomes[booklet] ?? {};
    final bookletK12 = _k12Codes[booklet] ?? {};
    final bookletKazanimKod = _kazanimCodes[booklet] ?? {};

    bookletOutcomes.forEach((key, val) {
      final k12List = bookletK12[key] ?? [];
      final kazanimKodList = bookletKazanimKod[key] ?? [];
      outcomesMap[key] = List.generate(val.length, (index) {
        String desc = val[index];
        String k12 = (index < k12List.length) ? k12List[index] : '';
        String kazanimKod = (index < kazanimKodList.length)
            ? kazanimKodList[index]
            : '';
        return OutcomeItem(code: kazanimKod, description: desc, k12Code: k12);
      });
    });

    // Determine initial branch
    String initialBranch = widget.examType.subjects.isNotEmpty
        ? widget.examType.subjects.first.branchName
        : '';

    final result = await Navigator.push<Map<String, List<OutcomeItem>>>(
      context,
      MaterialPageRoute(
        builder: (context) => OutcomeMatchingScreen(
          allOutcomes: outcomesMap,
          institutionId: widget.examType.institutionId,
          classLevel: widget.examType.gradeLevel,
          initialBranchName: initialBranch,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        // 1. Build Mapping Dictionary
        final Map<String, String> rawToStandardMap = {};

        result.forEach((branch, newItems) {
          final originalItems = originalBookletState[branch] ?? [];
          for (
            int i = 0;
            i < newItems.length && i < originalItems.length;
            i++
          ) {
            String raw = normalize(originalItems[i]);
            String standard = newItems[i].description;
            if (raw.isNotEmpty) {
              rawToStandardMap[raw] = standard;
            }
          }

          // Update current booklet
          _outcomes[booklet]![branch] = newItems
              .map((e) => e.description)
              .toList();
        });

        // 2. Propagate to OTHER booklets
        _outcomes.forEach((otherBooklet, branchMap) {
          if (otherBooklet == booklet) return;

          branchMap.forEach((branch, itemList) {
            for (int i = 0; i < itemList.length; i++) {
              String raw = itemList[i];
              String norm = normalize(raw);
              if (rawToStandardMap.containsKey(norm)) {
                itemList[i] = rawToStandardMap[norm]!;
              }
            }
          });
        });
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eşleşmeler tüm kitapçıklara uygulandı.')),
      );
    }
  }

  Future<void> _downloadExampleExcel() async {
    var excel = Excel.createExcel();
    Sheet sheet = excel['Sheet1'];

    // Header Row construction
    // Requested Order: Ders | Soru No (A) | Soru No (B)... | Cevap (A) | Kazanım
    List<String> headers = ['Ders', 'Soru No (A)'];

    // Add columns for other booklets
    for (int i = 1; i < widget.bookletCount; i++) {
      headers.add('Soru No (${String.fromCharCode(65 + i)})');
    }

    headers.add('Cevap (A)');
    headers.add('Kazanım');
    headers.add('K12 Kodu');
    headers.add('Kazanım Kodu');

    sheet.appendRow(headers.map((e) => TextCellValue(e)).toList());

    // Fill with empty template rows
    for (var subject in widget.examType.subjects) {
      for (int i = 1; i <= subject.questionCount; i++) {
        List<CellValue> row = [];
        row.add(TextCellValue(subject.branchName)); // Ders
        row.add(IntCellValue(i)); // Soru No A

        // Other Booklets (default to same number)
        for (int k = 1; k < widget.bookletCount; k++) {
          row.add(IntCellValue(i));
        }

        row.add(TextCellValue('')); // Cevap A (Empty)
        row.add(TextCellValue('')); // Kazanım (Empty)
        row.add(TextCellValue('')); // K12 Kodu (Empty)
        row.add(TextCellValue('')); // Kazanım Kodu (Empty)
        sheet.appendRow(row);
      }
    }

    // Save
    var fileBytes = excel.save();
    if (fileBytes != null) {
      try {
        await FileSaver.instance.saveFile(
          name: 'cevap_anahtari_sablon',
          bytes: Uint8List.fromList(fileBytes),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Dosya indirildi/kaydedildi.')),
          );
        }
      } catch (e) {
        print('Save error: $e');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Kaydetme hatası: $e')));
        }
      }
    }
  }

  Future<void> _uploadExcel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result != null) {
        List<int> bytes;
        if (result.files.single.bytes != null) {
          bytes = result.files.single.bytes!;
        } else if (result.files.single.path != null) {
          bytes = File(result.files.single.path!).readAsBytesSync();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Dosya okunamadı (Bytes null).')),
          );
          return;
        }

        var excel = Excel.decodeBytes(bytes);
        int processedRows = 0;
        List<String> notFoundSubjects = [];

        for (var table in excel.tables.keys) {
          var sheet = excel.tables[table];
          if (sheet == null) continue;

          bool isHeader = true;

          // Temporary storage
          Map<String, Map<String, List<String>>> tempAnswers = {};
          Map<String, Map<String, List<String>>> tempOutcomes = {};
          Map<String, Map<String, List<String>>> tempK12 = {};
          Map<String, Map<String, List<String>>> tempKazanimKod = {};

          List<String> bookletNames = List.generate(
            widget.bookletCount,
            (index) => String.fromCharCode(65 + index),
          );

          for (var b in bookletNames) {
            tempAnswers[b] = {};
            tempOutcomes[b] = {};
            tempK12[b] = {};
            tempKazanimKod[b] = {};
            for (var s in widget.examType.subjects) {
              tempAnswers[b]![s.branchName] = List.filled(s.questionCount, ' ');
              tempOutcomes[b]![s.branchName] = List.filled(s.questionCount, '');
              tempK12[b]![s.branchName] = List.filled(s.questionCount, '');
              tempKazanimKod[b]![s.branchName] = List.filled(
                s.questionCount,
                '',
              );
            }
          }

          for (var row in sheet.rows) {
            if (isHeader) {
              isHeader = false;
              continue;
            }
            if (row.isEmpty) continue;
            if (row.length < widget.bookletCount + 3) continue;

            String subjectName = row[0]?.value.toString().trim() ?? '';
            if (subjectName.isEmpty) continue;

            var potentialSubjects = widget.examType.subjects.where(
              (s) =>
                  s.branchName.trim().toLowerCase() ==
                  subjectName.toLowerCase(),
            );

            if (potentialSubjects.isEmpty) {
              if (!notFoundSubjects.contains(subjectName)) {
                notFoundSubjects.add(subjectName);
              }
              continue;
            }

            var subject = potentialSubjects.first;
            int qNoA = int.tryParse(row[1]?.value.toString() ?? '0') ?? 0;
            if (qNoA < 1 || qNoA > subject.questionCount) continue;

            int answerColIndex = 1 + widget.bookletCount;
            int outcomeColIndex = answerColIndex + 1;
            int k12ColIndex = outcomeColIndex + 1;
            int kazanimKodColIndex = k12ColIndex + 1;

            if (row.length <= answerColIndex) continue;

            String answerA = (row[answerColIndex]?.value.toString() ?? ' ')
                .trim()
                .toUpperCase();
            if (answerA.isNotEmpty && answerA.length > 1) answerA = answerA[0];
            if (answerA.isEmpty) answerA = ' ';

            String outcome = '';
            if (row.length > outcomeColIndex) {
              outcome = row[outcomeColIndex]?.value.toString().trim() ?? '';
            }

            String k12 = '';
            if (row.length > k12ColIndex) {
              k12 = row[k12ColIndex]?.value.toString().trim() ?? '';
            }

            String kazanimKod = '';
            if (row.length > kazanimKodColIndex) {
              kazanimKod =
                  row[kazanimKodColIndex]?.value.toString().trim() ?? '';
            }

            // Fill (A)
            tempAnswers['A']![subject.branchName]![qNoA - 1] = answerA;
            tempOutcomes['A']![subject.branchName]![qNoA - 1] = outcome;
            tempK12['A']![subject.branchName]![qNoA - 1] = k12;
            tempKazanimKod['A']![subject.branchName]![qNoA - 1] = kazanimKod;

            // Other Booklets
            int otherBookletsCount = widget.bookletCount - 1;
            for (int i = 0; i < otherBookletsCount; i++) {
              int colIndex = 2 + i;
              if (row.length <= colIndex) break;

              int qNoOther =
                  int.tryParse(row[colIndex]?.value.toString() ?? '0') ?? 0;
              String bookletChar = String.fromCharCode(66 + i);

              if (qNoOther >= 1 && qNoOther <= subject.questionCount) {
                tempAnswers[bookletChar]![subject.branchName]![qNoOther - 1] =
                    answerA;
                tempOutcomes[bookletChar]![subject.branchName]![qNoOther - 1] =
                    outcome;
                tempK12[bookletChar]![subject.branchName]![qNoOther - 1] = k12;
                tempKazanimKod[bookletChar]![subject.branchName]![qNoOther -
                        1] =
                    kazanimKod;
              }
            }
            processedRows++;
          }

          setState(() {
            for (var b in bookletNames) {
              for (var s in widget.examType.subjects) {
                String keyString =
                    tempAnswers[b]?[s.branchName]?.join('') ?? '';
                if (keyString.length < s.questionCount) {
                  keyString = keyString.padRight(s.questionCount, ' ');
                }

                _answerKeys[b]![s.branchName] = keyString;
                if (_keyControllers[b]![s.branchName] != null) {
                  _keyControllers[b]![s.branchName]!.text = keyString;
                }

                _outcomes[b]![s.branchName] = tempOutcomes[b]![s.branchName]!;
                _k12Codes[b]![s.branchName] = tempK12[b]![s.branchName]!;
                _kazanimCodes[b]![s.branchName] =
                    tempKazanimKod[b]![s.branchName]!;
              }
            }
          });

          String msg = 'Yükleme başarılı.\n$processedRows satır işlendi.';
          if (notFoundSubjects.isNotEmpty) {
            msg += '\nEşleşmeyen Dersler: ${notFoundSubjects.join(", ")}';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: notFoundSubjects.isNotEmpty
                  ? Colors.orange
                  : Colors.green,
            ),
          );
          break;
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Excel yükleme hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Cevap Anahtarı ve Kazanımlar',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'download') _downloadExampleExcel();
              if (value == 'upload') _uploadExcel();
              if (value == 'match') {
                final String currentBooklet = String.fromCharCode(
                  65 + _tabController.index,
                );
                _matchSubjectOutcomes(currentBooklet);
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'match',
                child: ListTile(
                  leading: Icon(Icons.compare_arrows, color: Colors.orange),
                  title: Text('Kazanım Eşleştir'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'download',
                child: ListTile(
                  leading: Icon(Icons.download),
                  title: Text('Örnek Şablon İndir'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'upload',
                child: ListTile(
                  leading: Icon(Icons.upload_file),
                  title: Text('Excel Yükle'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: List.generate(widget.bookletCount, (index) {
            return Tab(
              child: Text(
                '${String.fromCharCode(65 + index)} Kitapçığı',
                style: const TextStyle(color: Colors.white),
              ),
            );
          }),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onSave,
        label: Text('KAYDET'),
        icon: Icon(Icons.check),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12.0),
            color: Colors.amber.shade50,
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade800),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Özel Durumlar: İptal için "X", Herkes için doğru ise "S", Herkes için boş ise "#" kullanınız.',
                    style: TextStyle(
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: List.generate(widget.bookletCount, (index) {
                final bookletChar = String.fromCharCode(65 + index);
                return _buildBookletView(bookletChar);
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookletView(String booklet) {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: widget.examType.subjects.length,
      itemBuilder: (context, index) {
        final subject = widget.examType.subjects[index];
        return _buildSubjectCard(booklet, subject);
      },
    );
  }

  Widget _buildSubjectCard(String booklet, ExamSubject subject) {
    final controller = _keyControllers[booklet]![subject.branchName]!;
    final outcomeList = _outcomes[booklet]?[subject.branchName] ?? [];

    // Ensure outcome list size matches question count
    if (outcomeList.length != subject.questionCount) {
      if (outcomeList.length < subject.questionCount) {
        outcomeList.addAll(
          List.filled(subject.questionCount - outcomeList.length, ''),
        );
      } else {
        outcomeList.removeRange(subject.questionCount, outcomeList.length);
      }
      _outcomes[booklet]![subject.branchName] = outcomeList;
    }

    return Card(
      elevation: 3,
      margin: EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Row 1: Title, Counter, Text Field
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Subject Name Badge
                Container(
                  width: 120,
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.indigo.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject.branchName,
                        style: TextStyle(
                          color: Colors.indigo.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '${subject.questionCount} Soru',
                        style: TextStyle(
                          color: Colors.indigo.shade400,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),

                // Answer Key Field
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Fancy Counter
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, child) {
                          int len = value.text.length;
                          int remaining = subject.questionCount - len;
                          Color color = remaining == 0
                              ? Colors.green
                              : (remaining < 0 ? Colors.red : Colors.grey);
                          return Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              remaining < 0
                                  ? 'Fazla: ${-remaining}'
                                  : (remaining == 0
                                        ? 'Tamamlandı'
                                        : 'Kalan: $remaining'),
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
                      SizedBox(height: 4),
                      TextField(
                        controller: controller,
                        maxLength: subject.questionCount,
                        style: TextStyle(
                          letterSpacing: 2.0,
                          fontFamily: 'Monospace',
                          fontWeight: FontWeight.bold,
                        ),
                        inputFormatters: [
                          UpperCaseTextFormatter(),
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-E XS#]'),
                          ),
                        ],
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'ABCD...',
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Colors.indigo,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            Divider(height: 24),

            // Kazanım Listesi Expander
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Icon(Icons.list_alt, size: 20, color: Colors.indigo),
                  SizedBox(width: 8),
                  Text(
                    'Kazanım Tablosu',
                    style: TextStyle(
                      color: Colors.indigo,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              children: [
                /* KAZANIM EŞLEŞTİR BUTTON REMOVED (Moved to AppBar) */
                Container(
                  height: 300, // Scrollable height
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.separated(
                    padding: EdgeInsets.all(8),
                    itemCount: subject.questionCount,
                    separatorBuilder: (c, i) => Divider(height: 1),
                    itemBuilder: (context, qIndex) {
                      return Row(
                        children: [
                          Container(
                            width: 30,
                            alignment: Alignment.center,
                            child: Text(
                              '${qIndex + 1}.',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              initialValue: outcomeList[qIndex],
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Kazanım giriniz...',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 12,
                                ),
                              ),
                              onChanged: (val) {
                                _outcomes[booklet]![subject
                                        .branchName]![qIndex] =
                                    val;
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
