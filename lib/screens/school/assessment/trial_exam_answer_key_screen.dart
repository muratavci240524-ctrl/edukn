import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import '../../../../models/assessment/exam_type_model.dart';
import '../../../../models/assessment/outcome_list_model.dart';
import '../../../../services/assessment_service.dart';
import 'outcome_matching_screen.dart';

class TrialExamAnswerKeyScreen extends StatefulWidget {
  final int bookletCount;
  final ExamType examType;
  final Map<String, Map<String, String>> initialAnswerKeys;
  final Map<String, Map<String, List<String>>> initialOutcomes;
  final Map<String, Map<String, String>> initialMapping;

  const TrialExamAnswerKeyScreen({
    Key? key,
    required this.bookletCount,
    required this.examType,
    required this.initialAnswerKeys,
    required this.initialOutcomes,
    this.initialMapping = const {},
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
  final Map<String, Map<String, TextEditingController>> _keyControllers = {};
  final Map<String, Map<String, TextEditingController>> _conversionControllers = {};
  final Map<String, TextEditingController> _bulkControllers = {};

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
      _bulkControllers.putIfAbsent(booklet, () => TextEditingController());
      _keyControllers.putIfAbsent(booklet, () => {});
      _conversionControllers.putIfAbsent(booklet, () => {});
      _answerKeys.putIfAbsent(booklet, () => {});
      _outcomes.putIfAbsent(booklet, () => {}); // Ensure initial map exists
      _k12Codes.putIfAbsent(booklet, () => {});
      _kazanimCodes.putIfAbsent(booklet, () => {});

      final bookletMapping = widget.initialMapping[booklet] ?? {};

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
          
          final currentMapping = bookletMapping[subject.branchName] ?? '';
          _conversionControllers[booklet]![subject.branchName] = TextEditingController(
            text: currentMapping,
          );
          _conversionControllers[booklet]![subject.branchName]!.addListener(() {
            _applyConversion(booklet, subject.branchName, _conversionControllers[booklet]![subject.branchName]!.text);
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
    for (var booklet in _conversionControllers.values) {
      for (var ctrl in booklet.values) {
        ctrl.dispose();
      }
    }
    for (var ctrl in _bulkControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _applyConversion(String booklet, String branchName, String conversionText) {
    if (booklet == 'A') return;
    
    // Parse conversion string: Support both '4, 3, 2' and '1(4), 2(3), 3(2)' formats
    List<int> mapping = [];
    if (conversionText.contains('(')) {
      final RegExp regexParentheses = RegExp(r'\((\d+)\)');
      mapping = regexParentheses.allMatches(conversionText).map((m) => int.parse(m.group(1)!)).toList();
    } else {
      final RegExp regexNumbers = RegExp(r'\d+');
      mapping = regexNumbers.allMatches(conversionText).map((m) => int.parse(m.group(0)!)).toList();
    }
    
    final subject = widget.examType.subjects.firstWhere((s) => s.branchName == branchName);
    final int qCount = subject.questionCount;
    
    String answerA = _answerKeys['A']![branchName] ?? '';
    List<String> outcomesA = _outcomes['A']![branchName] ?? [];
    List<String> k12A = _k12Codes['A']![branchName] ?? [];
    List<String> kazanimA = _kazanimCodes['A']![branchName] ?? [];
    
    // Pad A's data to ensure we don't get out of bounds
    answerA = answerA.padRight(qCount, ' ');
    if (outcomesA.length < qCount) outcomesA.addAll(List.filled(qCount - outcomesA.length, ''));
    if (k12A.length < qCount) k12A.addAll(List.filled(qCount - k12A.length, ''));
    if (kazanimA.length < qCount) kazanimA.addAll(List.filled(qCount - kazanimA.length, ''));
    
    String newAnswerB = '';
    List<String> newOutcomesB = List.filled(qCount, '');
    List<String> newK12B = List.filled(qCount, '');
    List<String> newKazanimB = List.filled(qCount, '');
    
    for (int i = 0; i < mapping.length && i < qCount; i++) {
      int mappedIndex = mapping[i] - 1; // 1-based to 0-based
      if (mappedIndex >= 0 && mappedIndex < qCount) {
        newAnswerB += answerA[mappedIndex];
        newOutcomesB[i] = outcomesA[mappedIndex];
        newK12B[i] = k12A[mappedIndex];
        newKazanimB[i] = kazanimA[mappedIndex];
      } else {
        newAnswerB += ' ';
      }
    }
    
    // Pad remaining
    if (newAnswerB.length < qCount) newAnswerB = newAnswerB.padRight(qCount, ' ');
    
    // Update internal state without triggering controller listener loops
    _answerKeys[booklet]![branchName] = newAnswerB;
    _outcomes[booklet]![branchName] = newOutcomesB;
    _k12Codes[booklet]![branchName] = newK12B;
    _kazanimCodes[booklet]![branchName] = newKazanimB;
    
    // Update visual textfield for answer key if needed (though we might hide it)
    if (_keyControllers[booklet]![branchName]!.text != newAnswerB) {
      _keyControllers[booklet]![branchName]!.value = TextEditingValue(
        text: newAnswerB,
        selection: TextSelection.collapsed(offset: newAnswerB.length),
      );
    }
    
    setState(() {}); // Trigger UI update for read-only preview
  }

  void _onSave() {
    // Collect mappings
    Map<String, Map<String, String>> bookletMapping = {};
    _conversionControllers.forEach((booklet, subjects) {
      bookletMapping[booklet] = {};
      subjects.forEach((subj, ctrl) {
        bookletMapping[booklet]![subj] = ctrl.text;
      });
    });

    Navigator.pop(context, {
      'answerKeys': _answerKeys,
      'outcomes': _outcomes,
      'bookletMapping': bookletMapping,
    });
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
          orderedBranchNames: widget.examType.subjects.map((s) => s.branchName).toList(),
          institutionId: widget.examType.institutionId,
          classLevel: widget.examType.gradeLevel,
          initialBranchName: initialBranch,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        // 1. Build Mapping Dictionary
        final Map<String, OutcomeItem> rawToStandardMap = {};

        result.forEach((branch, newItems) {
          final originalItems = originalBookletState[branch] ?? [];
          for (
            int i = 0;
            i < newItems.length && i < originalItems.length;
            i++
          ) {
            String raw = normalize(originalItems[i]);
            OutcomeItem standardItem = newItems[i];
            
            if (raw.isNotEmpty) {
              rawToStandardMap[raw] = standardItem;
            }
          }

          // Update current booklet maps
          _outcomes[booklet]![branch] = newItems.map((e) => e.description).toList();
          _k12Codes[booklet]![branch] = newItems.map((e) => e.k12Code).toList();
          _kazanimCodes[booklet]![branch] = newItems.map((e) => e.code).toList();
        });

        // 2. Propagate to OTHER booklets
        _outcomes.forEach((otherBooklet, branchMap) {
          if (otherBooklet == booklet) return;

          branchMap.forEach((branch, itemList) {
            for (int i = 0; i < itemList.length; i++) {
              String raw = itemList[i];
              String norm = normalize(raw);
              if (rawToStandardMap.containsKey(norm)) {
                itemList[i] = rawToStandardMap[norm]!.description;
                // Also update other maps for consistency
                if (_k12Codes[otherBooklet] != null && _k12Codes[otherBooklet]![branch] != null) {
                  _k12Codes[otherBooklet]![branch]![i] = rawToStandardMap[norm]!.k12Code;
                }
                if (_kazanimCodes[otherBooklet] != null && _kazanimCodes[otherBooklet]![branch] != null) {
                  _kazanimCodes[otherBooklet]![branch]![i] = rawToStandardMap[norm]!.code;
                }
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
          Map<String, Map<String, List<int>>> tempMapping = {};

          List<String> bookletNames = List.generate(
            widget.bookletCount,
            (index) => String.fromCharCode(65 + index),
          );

          for (var b in bookletNames) {
            tempAnswers[b] = {};
            tempOutcomes[b] = {};
            tempK12[b] = {};
            tempKazanimKod[b] = {};
            tempMapping[b] = {};
            for (var s in widget.examType.subjects) {
              tempAnswers[b]![s.branchName] = List.filled(s.questionCount, ' ');
              tempOutcomes[b]![s.branchName] = List.filled(s.questionCount, '');
              tempK12[b]![s.branchName] = List.filled(s.questionCount, '');
              tempKazanimKod[b]![s.branchName] = List.filled(s.questionCount, '');
              tempMapping[b]![s.branchName] = List.filled(s.questionCount, 0);
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
              if (outcome.toLowerCase() == 'null') outcome = '';
            }

            String k12 = '';
            if (row.length > k12ColIndex) {
              k12 = row[k12ColIndex]?.value.toString().trim() ?? '';
              if (k12.toLowerCase() == 'null') k12 = '';
            }

            String kazanimKod = '';
            if (row.length > kazanimKodColIndex) {
              kazanimKod =
                  row[kazanimKodColIndex]?.value.toString().trim() ?? '';
              if (kazanimKod.toLowerCase() == 'null') kazanimKod = '';
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
                tempKazanimKod[bookletChar]![subject.branchName]![qNoOther - 1] =
                    kazanimKod;
                tempMapping[bookletChar]![subject.branchName]![qNoOther - 1] = qNoA;
              }
            }
            processedRows++;
          }

          setState(() {
            for (var b in bookletNames) {
              List<String> formattedBulkParts = [];
              
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
                    
                if (b != 'A') {
                   List<int> mapping = tempMapping[b]![s.branchName]!;
                   List<String> formattedParts = [];
                   for (int i = 0; i < mapping.length; i++) {
                     if (mapping[i] > 0) {
                        formattedParts.add('${i + 1}(${mapping[i]})');
                     } else {
                        formattedParts.add('${i + 1}(?)');
                     }
                   }
                   String sliceStr = formattedParts.join(',  ');
                   
                   if (_conversionControllers[b]![s.branchName] != null) {
                      _conversionControllers[b]![s.branchName]!.text = sliceStr;
                   }
                   formattedBulkParts.add('[${s.branchName}]\n$sliceStr');
                } else {
                   String spacedSlice = keyString.split('').join(' ');
                   formattedBulkParts.add('[${s.branchName}]\n$spacedSlice');
                }
              }
              
              if (_bulkControllers[b] != null) {
                 _bulkControllers[b]!.text = formattedBulkParts.join('\n\n');
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

          // Auto-trigger fetch if there are K12 codes but no descriptions
          bool hasK12ButNoDesc = false;
          _k12Codes['A']?.forEach((branch, codes) {
             final descs = _outcomes['A']?[branch] ?? [];
             if (codes.any((c) => c.isNotEmpty) && descs.any((d) => d.isEmpty || d.toLowerCase() == 'null')) {
               hasK12ButNoDesc = true;
             }
          });

          if (hasK12ButNoDesc) {
            _autoFetchDescriptionsFromK12(silent: true);
          }
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
              if (value == 'autofetch') {
                _autoFetchDescriptionsFromK12();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'autofetch',
                child: ListTile(
                  leading: Icon(Icons.auto_fix_high, color: Colors.teal),
                  title: Text('K12\'den Metinleri Getir'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'match',
                child: ListTile(
                  leading: Icon(Icons.compare_arrows, color: Colors.orange),
                  title: Text('Kazanım Eşleştirme Ekranı'),
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
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        _buildBulkPasteCard(booklet),
        ...widget.examType.subjects.map((subject) {
          if (booklet == 'A') {
            return _buildSubjectCard(booklet, subject);
          } else {
            return _buildConversionCard(booklet, subject);
          }
        }).toList(),
      ],
    );
  }

  Widget _buildBulkPasteCard(String booklet) {
    final bool isA = booklet == 'A';
    int totalQuestions = widget.examType.subjects.fold(0, (sum, s) => sum + s.questionCount);
    
    return Card(
      elevation: 4,
      margin: EdgeInsets.only(bottom: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.indigo.shade200, width: 2),
      ),
      color: Colors.indigo.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flash_on, color: Colors.orange.shade700, size: 28),
                SizedBox(width: 8),
                Text(
                  'Hızlı Toplu Yapıştırma ($totalQuestions Soru)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade900,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              isA 
                ? 'Tüm derslerin cevaplarını peş peşe buraya yapıştırın. Sistem derslerin soru sayılarına göre otomatik olarak dağıtacaktır.'
                : 'Tüm derslerin dönüşüm numaralarını virgüllü veya boşluklu olarak buraya yapıştırın. Sistem otomatik olarak dağıtacaktır.',
              style: TextStyle(fontSize: 13, color: Colors.indigo.shade700),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _bulkControllers[booklet],
              maxLines: null,
              minLines: 2,
              decoration: InputDecoration(
                hintText: isA ? 'Örn: ADDCBBAA...' : 'Örn: 4, 3, 2, 1, 6...',
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: Tooltip(
                  message: 'Yapıştırdığınız anda dağıtılır',
                  child: Icon(Icons.auto_awesome, color: Colors.indigo),
                ),
              ),
              onChanged: (val) {
                // To avoid jumping cursor during normal typing, we only format 
                // if they pasted a large chunk or it ends with newline/space
                if (val.trim().isNotEmpty) {
                  _handleBulkPaste(booklet, val);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleBulkPaste(String booklet, String text) {
    if (booklet == 'A') {
      // Ignore text inside brackets [Ders Adı] so "TÜRKÇE" doesn't parse 'E' as answer
      String textWithoutTags = text.replaceAll(RegExp(r'\[.*?\]'), '');
      String cleanText = textWithoutTags.toUpperCase().replaceAll(RegExp(r'[^A-EXS#]'), '');
      
      int currentIndex = 0;
      List<String> formattedBulkParts = [];
      
      for (var subject in widget.examType.subjects) {
        int qCount = subject.questionCount;
        if (currentIndex < cleanText.length) {
          int end = currentIndex + qCount;
          if (end > cleanText.length) end = cleanText.length;
          String slice = cleanText.substring(currentIndex, end);
          
          if (_keyControllers[booklet]![subject.branchName]!.text != slice) {
            _keyControllers[booklet]![subject.branchName]!.value = TextEditingValue(
              text: slice,
              selection: TextSelection.collapsed(offset: slice.length),
            );
          }
          
          // Format with spaces for readability: A D D C B B
          String spacedSlice = slice.split('').join(' ');
          formattedBulkParts.add('[${subject.branchName}]\n$spacedSlice');
          
          currentIndex += qCount;
        }
      }
      
      // Update the bulk text field to show the formatted branch summary
      String newBulkText = formattedBulkParts.join('\n\n');
      // Only update if it's a significant change to avoid cursor locking on manual typing
      if (!text.contains('[') && cleanText.length > 5) {
        _bulkControllers[booklet]!.value = TextEditingValue(
          text: newBulkText,
          selection: TextSelection.collapsed(offset: newBulkText.length),
        );
      }

    } else {
      // It's a comma/space/newline separated list of numbers for Conversion
      List<String> numbers = [];
      if (text.contains('(')) {
        // If it's already formatted as 1(4), 2(3), we extract the target numbers inside ()
        final RegExp regexParentheses = RegExp(r'\((\d+)\)');
        numbers = regexParentheses.allMatches(text).map((m) => m.group(1)!).toList();
      } else {
        // Raw numbers
        final RegExp regexNumbers = RegExp(r'\d+');
        numbers = regexNumbers.allMatches(text).map((m) => m.group(0)!).toList();
      }
      
      int currentIndex = 0;
      List<String> formattedBulkParts = [];
      
      for (var subject in widget.examType.subjects) {
        int qCount = subject.questionCount;
        if (currentIndex < numbers.length) {
          int end = currentIndex + qCount;
          if (end > numbers.length) end = numbers.length;
          List<String> slice = numbers.sublist(currentIndex, end);
          
          // Format elegantly as 1(4), 2(3), 3(2)...
          List<String> formattedParts = [];
          for (int i = 0; i < slice.length; i++) {
             formattedParts.add('${i + 1}(${slice[i]})');
          }
          String sliceStr = formattedParts.join(',  ');
          
          if (_conversionControllers[booklet]![subject.branchName]!.text != sliceStr) {
            _conversionControllers[booklet]![subject.branchName]!.value = TextEditingValue(
              text: sliceStr,
              selection: TextSelection.collapsed(offset: sliceStr.length),
            );
          }
          
          formattedBulkParts.add('[${subject.branchName}]\n$sliceStr');
          currentIndex += qCount;
        }
      }
      
      // Update the bulk text field to show the formatted branch summary
      String newBulkText = formattedBulkParts.join('\n\n');
      if (!text.contains('[') && numbers.length > 5) {
        _bulkControllers[booklet]!.value = TextEditingValue(
          text: newBulkText,
          selection: TextSelection.collapsed(offset: newBulkText.length),
        );
      }
    }
  }

  Widget _buildConversionCard(String booklet, ExamSubject subject) {
    final conversionController = _conversionControllers[booklet]![subject.branchName]!;
    final currentAnswerKey = _answerKeys[booklet]?[subject.branchName] ?? '';

    return Card(
      elevation: 3,
      margin: EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Title & Info
            Row(
              children: [
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
                Expanded(
                  child: Text(
                    '$booklet Kitapçığındaki soruların, A Kitapçığında kaçıncı soruya denk geldiğini sırasıyla yazınız. (Örn: 4, 3, 2, 1, 6...)',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            
            // Conversion TextField
            TextField(
              controller: conversionController,
              decoration: InputDecoration(
                hintText: 'Örn: 1(4), 2(3), 3(2)... veya yapıştırın',
                filled: true,
                fillColor: Colors.teal.shade50,
                prefixIcon: Icon(Icons.transform, color: Colors.teal),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.teal.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.teal, width: 2),
                ),
                suffixIcon: IconButton(
                  icon: Icon(Icons.auto_fix_high, color: Colors.indigo),
                  tooltip: 'Düzenle (1(4) Formatına Çevir)',
                  onPressed: () {
                    final val = conversionController.text;
                    if (!val.contains('(')) {
                      final RegExp regexNumbers = RegExp(r'\d+');
                      final numbers = regexNumbers.allMatches(val).map((m) => m.group(0)!).toList();
                      if (numbers.isNotEmpty) {
                        List<String> formattedParts = [];
                        for (int i = 0; i < numbers.length; i++) {
                          formattedParts.add('${i + 1}(${numbers[i]})');
                        }
                        final newText = formattedParts.join(',  ');
                        conversionController.value = TextEditingValue(
                          text: newText,
                          selection: TextSelection.collapsed(offset: newText.length),
                        );
                      }
                    }
                  },
                ),
              ),
              onChanged: (val) {
                // Sadece kullanıcı uzun bir boşluklu metin yapıştırdığında otomatik formatı tetikleyelim.
                // Manuel yazarken imleç zıplamasını engellemek için.
                if (!val.contains('(') && val.length > 5 && val.contains(' ') && val.endsWith(' ')) {
                   final RegExp regexNumbers = RegExp(r'\d+');
                   final numbers = regexNumbers.allMatches(val).map((m) => m.group(0)!).toList();
                   if (numbers.length > 2) {
                     List<String> formattedParts = [];
                     for (int i = 0; i < numbers.length; i++) {
                       formattedParts.add('${i + 1}(${numbers[i]})');
                     }
                     final newText = formattedParts.join(',  ');
                     conversionController.value = TextEditingValue(
                       text: newText,
                       selection: TextSelection.collapsed(offset: newText.length),
                     );
                   }
                }
              },
            ),
            
            SizedBox(height: 16),
            // Read-Only Generated Answer Key Preview
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Otomatik Oluşturulan Cevap Anahtarı ($booklet)',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    currentAnswerKey.isEmpty ? 'Henüz dönüşüm girilmedi.' : currentAnswerKey,
                    style: TextStyle(
                      fontFamily: 'Monospace',
                      letterSpacing: 2.0,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: currentAnswerKey.isEmpty ? Colors.grey : Colors.indigo.shade800,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Kazanımlar da A kitapçığından otomatik olarak aktarılmaktadır.',
                    style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
                      final k12Code = (_k12Codes[booklet]?[subject.branchName] ?? [])[qIndex];
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
                          // K12 Code Field (Smaller)
                          Container(
                            width: 80,
                            child: TextFormField(
                              initialValue: k12Code,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: 'K12...',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                              ),
                              onChanged: (val) {
                                _k12Codes[booklet]![subject.branchName]![qIndex] = val;
                                // Auto-lookup if K12 is entered
                                if (val.isNotEmpty) {
                                   _lookupFromK12(booklet, subject.branchName, qIndex, val);
                                }
                              },
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          // Kazanım Description Field
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
                                _outcomes[booklet]![subject.branchName]![qIndex] = val;
                                // Could auto-lookup K12 if description is unique, but K12-first is safer
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

  Future<void> _autoFetchDescriptionsFromK12({bool silent = false}) async {
    if (!mounted) return;
    
    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('K12 kodları üzerinden metinler getiriliyor...')),
      );
    }

    try {
      final assessmentService = AssessmentService();
      final allMasterLists = await assessmentService.getOutcomeLists(widget.examType.institutionId).first;
      
      bool updated = false;
      
      // We'll map K12 -> OutcomeItem for all relevant master lists
      final Map<String, OutcomeItem> masterMap = {};
      for (var list in allMasterLists) {
        // Filter by grade level
        bool relevantClass = list.classLevel.contains(widget.examType.gradeLevel.replaceAll(RegExp(r'[^0-9]'), ''));
        if (relevantClass) {
          for (var item in list.outcomes) {
            if (item.k12Code.isNotEmpty) {
              masterMap[item.k12Code] = item;
            }
          }
        }
      }

      setState(() {
        _outcomes.forEach((booklet, branchMap) {
          branchMap.forEach((branch, itemList) {
            final k12List = _k12Codes[booklet]?[branch] ?? [];
            for (int i = 0; i < itemList.length; i++) {
              // If description is empty or 'null', and we have a K12 code
              if ((itemList[i].isEmpty || itemList[i].toLowerCase() == 'null') && i < k12List.length) {
                final k12 = k12List[i];
                if (k12.isNotEmpty && masterMap.containsKey(k12)) {
                  itemList[i] = masterMap[k12]!.description;
                  if (_kazanimCodes[booklet] != null && _kazanimCodes[booklet]![branch] != null) {
                    _kazanimCodes[booklet]![branch]![i] = masterMap[k12]!.code;
                  }
                  updated = true;
                }
              }
            }
          });
        });
      });

      if (updated) {
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kazanım metinleri başarıyla güncellendi.'), backgroundColor: Colors.green),
          );
        }
      } else if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('K12 kodlarıyla eşleşen yeni metin bulunamadı.')),
        );
      }
    } catch (e) {
      print('Auto-fetch error: $e');
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata oluştu: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _lookupFromK12(String booklet, String branch, int index, String k12) async {
    // This is a simplified version of the auto-fetch logic for a single item
    // It uses the already loaded master lists if possible, or fetches them
    try {
      final assessmentService = AssessmentService();
      final allMasterLists = await assessmentService.getOutcomeLists(widget.examType.institutionId).first;
      
      for (var list in allMasterLists) {
        for (var item in list.outcomes) {
          if (item.k12Code == k12) {
             setState(() {
               _outcomes[booklet]![branch]![index] = item.description;
               if (_kazanimCodes[booklet] != null && _kazanimCodes[booklet]![branch] != null) {
                  _kazanimCodes[booklet]![branch]![index] = item.code;
               }
             });
             return;
          }
        }
      }
    } catch (e) {
      print('Lookup error: $e');
    }
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
