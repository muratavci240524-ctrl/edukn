import 'package:flutter/material.dart';
import '../../../../models/assessment/outcome_list_model.dart';
import '../../../../services/assessment_service.dart';

class OutcomeMatchingScreen extends StatefulWidget {
  final Map<String, List<OutcomeItem>> allOutcomes; // Key: BranchName
  final String institutionId;
  final String classLevel;
  final String initialBranchName;

  const OutcomeMatchingScreen({
    Key? key,
    required this.allOutcomes,
    required this.institutionId,
    required this.classLevel,
    required this.initialBranchName,
  }) : super(key: key);

  @override
  _OutcomeMatchingScreenState createState() => _OutcomeMatchingScreenState();
}

class _OutcomeMatchingScreenState extends State<OutcomeMatchingScreen> {
  final AssessmentService _service = AssessmentService();
  bool _isLoading = true;

  // Data
  List<OutcomeList> _availableLists = [];

  // State
  late String _currentBranch;
  String? _selectedListId;
  List<OutcomeItem> _masterOutcomes = [];

  // Matches state: BranchName -> {Index -> MasterItem}
  final Map<String, Map<int, OutcomeItem>> _allConfirmedMatches = {};

  // Selection state
  int? _selectedLeftIndex;

  // Search state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _currentBranch = widget.initialBranchName;
    // Ensure current branch exists in map, if not, pick first
    if (!widget.allOutcomes.containsKey(_currentBranch) &&
        widget.allOutcomes.isNotEmpty) {
      _currentBranch = widget.allOutcomes.keys.first;
    }
    _loadMasterData();
  }

  Future<void> _loadMasterData() async {
    try {
      final stream = _service.getOutcomeLists(widget.institutionId);
      final allLists = await stream.first;

      if (mounted) {
        setState(() {
          _availableLists = allLists;
          _isLoading = false;
        });

        _autoSelectMasterListForCurrentBranch();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  void _onBranchChanged(String? newBranch) {
    if (newBranch == null || newBranch == _currentBranch) return;

    setState(() {
      _currentBranch = newBranch;
      _selectedLeftIndex = null; // Reset selection
      // No need to clear matches, they are stored in _allConfirmedMatches per branch
    });

    _autoSelectMasterListForCurrentBranch();
  }

  void _autoSelectMasterListForCurrentBranch() {
    if (_availableLists.isEmpty) return;

    // Try to find a default match for the current branch
    OutcomeList? bestMatch;
    try {
      bestMatch = _availableLists.firstWhere(
        (list) =>
            list.classLevel == widget.classLevel &&
            list.branchName == _currentBranch,
      );
    } catch (_) {}

    if (bestMatch == null) {
      try {
        bestMatch = _availableLists.firstWhere(
          (list) => list.branchName == _currentBranch,
        );
      } catch (_) {}
    }

    if (bestMatch != null) {
      _onMasterListChanged(bestMatch.id);
    } else {
      // Prepare blank state if no list found (though we might keep previous if appropriate, but safer to clear)
      setState(() {
        _selectedListId = null;
        _masterOutcomes = [];
      });
    }
  }

  void _onMasterListChanged(String? listId) {
    if (listId == null) return;
    final selectedList = _availableLists.firstWhere(
      (l) => l.id == listId,
      orElse: () => _availableLists.first,
    );

    setState(() {
      _selectedListId = listId;
      _masterOutcomes = selectedList.outcomes;
    });

    _runAutoMatch();
  }

  void _runAutoMatch() {
    final currentList = widget.allOutcomes[_currentBranch] ?? [];
    if (currentList.isEmpty) return;

    final branchMatches = _allConfirmedMatches.putIfAbsent(
      _currentBranch,
      () => {},
    );

    for (int i = 0; i < currentList.length; i++) {
      final current = currentList[i];
      if (branchMatches.containsKey(i)) continue;

      bool matched = false;

      // 1. Exact Text Match (OLD RULE - PRIMARY)
      String currentClean = _normalizeText(_stripCode(current.description));
      if (currentClean.isNotEmpty) {
        try {
          final textMatch = _masterOutcomes.firstWhere(
            (m) => _normalizeText(_stripCode(m.description)) == currentClean,
          );
          branchMatches[i] = textMatch;
          matched = true;
        } catch (_) {}
      }

      if (matched) continue;

      // 2. Exact K12 Code Match
      if (current.k12Code.isNotEmpty) {
        try {
          final masterMatch = _masterOutcomes.firstWhere(
            (m) => m.k12Code == current.k12Code,
          );
          branchMatches[i] = masterMatch;
          matched = true;
        } catch (_) {}
      }

      if (matched) continue;

      // 3. Kazanım Kodu (Code) Match or Greedy Parent Match (FALLBACK)
      if (current.code.isNotEmpty) {
        String currentNorm = _normalizeKodu(current.code);
        if (currentNorm.isNotEmpty) {
          // Greedy search: Start from full code, keep removing last parts until match found
          // e.g. 8.1.2.1.2 -> 8.1.2.1 -> 8.1.2 -> 8.1
          List<String> parts = currentNorm.split('.');
          while (parts.isNotEmpty) {
            String testCode = parts.join('.');
            try {
              final masterMatch = _masterOutcomes.firstWhere(
                (m) => m.code.isNotEmpty && _normalizeKodu(m.code) == testCode,
              );
              branchMatches[i] = masterMatch;
              matched = true;
              break; // Found it!
            } catch (_) {}
            parts.removeLast();
          }
        }
      }

      if (matched) continue;

      // 2. Exact Description Similarity Match (Lowered threshold to 80%)
      double bestScore = 0;
      OutcomeItem? bestMaster;

      for (var master in _masterOutcomes) {
        double score = _calculateSimilarity(current, master);

        if (score > bestScore) {
          bestScore = score;
          bestMaster = master;
        }
      }

      // Automatically match if score is 80% or higher
      if (bestMaster != null && bestScore >= 0.8) {
        branchMatches[i] = bestMaster;
      }
    }
    setState(() {});
  }

  List<MapEntry<OutcomeItem, double>> _getSuggestionsForSelected() {
    // If there is a search query, show search results
    if (_searchQuery.isNotEmpty) {
      List<MapEntry<OutcomeItem, double>> results = [];
      String query = _searchQuery.toLowerCase();
      for (var master in _masterOutcomes) {
        double score = 0;
        if (master.description.toLowerCase().contains(query)) score += 1.0;
        if (master.code.toLowerCase().contains(query)) score += 2.0;
        if (master.k12Code.toLowerCase().contains(query)) score += 2.0;

        if (score > 0) {
          results.add(MapEntry(master, score));
        }
      }
      results.sort((a, b) => b.value.compareTo(a.value));
      return results;
    }

    if (_selectedLeftIndex == null) {
      // If no selection and no search, show full list (capped)
      return _masterOutcomes.take(100).map((e) => MapEntry(e, 0.0)).toList();
    }

    final currentList = widget.allOutcomes[_currentBranch] ?? [];
    if (_selectedLeftIndex! >= currentList.length) return [];

    final currentItem = currentList[_selectedLeftIndex!];

    List<MapEntry<OutcomeItem, double>> scored = [];

    for (var master in _masterOutcomes) {
      double score = _calculateSimilarity(currentItem, master);

      // Boost score for Perfect Text Match (Highest)
      String curClean = _normalizeText(_stripCode(currentItem.description));
      String mastClean = _normalizeText(_stripCode(master.description));
      if (curClean.isNotEmpty && curClean == mastClean) {
        score = 3.0;
      }
      // Boost score for K12 Match
      else if (currentItem.k12Code.isNotEmpty &&
          currentItem.k12Code == master.k12Code) {
        score = 2.5;
      }
      // Boost score for Kazanım Kodu Match
      else if (currentItem.code.isNotEmpty && master.code.isNotEmpty) {
        String curNorm = _normalizeKodu(currentItem.code);
        String mastNorm = _normalizeKodu(master.code);
        if (curNorm == mastNorm) {
          score = 1.9;
        } else if (curNorm.startsWith(mastNorm + ".")) {
          // Greedy score: The more parts matched, the higher the score (max 1.89)
          int mastParts = mastNorm.split('.').length;
          int curParts = curNorm.split('.').length;
          double greedyBoost = (mastParts / curParts) * 0.09;
          score = 1.8 + greedyBoost;
        }
      }

      scored.add(MapEntry(master, score));
    }

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(50).toList();
  }

  String _normalizeKodu(String code) {
    if (code.isEmpty) return code;
    // T.8.1.1.2 -> 8.1.1.2
    // 8.1.1.2. -> 8.1.1.2
    final match = RegExp(r'\d[\d\.]*').firstMatch(code);
    if (match != null) {
      String ext = match.group(0)!;
      while (ext.isNotEmpty && ext.endsWith('.')) {
        ext = ext.substring(0, ext.length - 1);
      }
      return ext;
    }
    return code;
  }

  double _calculateSimilarity(OutcomeItem item1, OutcomeItem item2) {
    // 3. Tokenize
    Set<String> tokenize(String s) {
      // 1. Remove punctuation
      String cleaned = s.replaceAll(
        RegExp(
          r'[.,;:\-()""'
          '\’\‘\“\”\!]',
        ),
        ' ',
      );

      // 2. Multi-language lowercase normalization
      cleaned = cleaned.toLowerCase();

      // Normalize Turkish-specific confusion to support both TR and EN
      cleaned = cleaned
          .replaceAll('ı', 'i')
          .replaceAll('ü', 'u')
          .replaceAll('ö', 'o')
          .replaceAll('ş', 's')
          .replaceAll('ç', 'c')
          .replaceAll('ğ', 'g');

      return cleaned
          .trim()
          .split(RegExp(r'\s+'))
          .where((e) => e.isNotEmpty)
          .toSet();
    }

    String s1 = "${item1.k12Code} ${item1.code} ${item1.description}".trim();
    String s2 = "${item2.k12Code} ${item2.code} ${item2.description}".trim();

    var set1 = tokenize(s1);
    var set2 = tokenize(s2);

    if (set1.isEmpty && set2.isEmpty) return 1.0;
    if (set1.isEmpty || set2.isEmpty) return 0.0;

    var intersection = set1.intersection(set2).length;
    var union = set1.union(set2).length;
    double score = union == 0 ? 0 : intersection / union;

    // Fallback: If description parts match exactly after stripping codes, prioritze it (User Request)
    String desc1 = _stripCode(item1.description);
    String desc2 = _stripCode(item2.description);

    if (desc1.isNotEmpty && _normalizeText(desc1) == _normalizeText(desc2)) {
      return 1.0; // Perfect text match regardless of leading codes
    }

    return score;
  }

  // Advanced recursive stripCode: Removes multiples like "E8.5.SP1. E8.5.SP1. Text"
  String _stripCode(String s) {
    String result = s.trim();
    final regex = RegExp(
      r'^\p{L}*\.?[0-9]+(\.[\p{L}0-9]+)*[.\s]+',
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

  // Normalize TR chars and strip punctuation for perfect matching
  String _normalizeText(String s) {
    String n = s
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g');
    // Remove all punctuation to prevent `'` vs `’` mismatches
    n = n.replaceAll(RegExp(r'[.,;:\-()""\’\‘\“\”\!' + r"']"), '');
    // Remove extra spaces
    return n.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  void _toggleMatch(OutcomeItem masterItem) {
    if (_selectedLeftIndex == null) return;

    final branchMatches = _allConfirmedMatches.putIfAbsent(
      _currentBranch,
      () => {},
    );
    final currentMatch = branchMatches[_selectedLeftIndex!];

    bool isSame =
        currentMatch != null &&
        currentMatch.code == masterItem.code &&
        currentMatch.description == masterItem.description;

    setState(() {
      if (isSame) {
        branchMatches.remove(_selectedLeftIndex!);
      } else {
        branchMatches[_selectedLeftIndex!] = masterItem;

        // Auto-advance
        final currentList = widget.allOutcomes[_currentBranch] ?? [];
        if (_selectedLeftIndex! < currentList.length - 1) {
          _selectedLeftIndex = _selectedLeftIndex! + 1;
          if (currentList[_selectedLeftIndex!].depth == 1) {
            if (_selectedLeftIndex! < currentList.length - 1) {
              _selectedLeftIndex = _selectedLeftIndex! + 1;
            }
          }
        }
      }
    });
  }

  void _finish() {
    // Apply matches to all branches
    Map<String, List<OutcomeItem>> finalResults = {};

    widget.allOutcomes.forEach((branch, outcomes) {
      List<OutcomeItem> updatedList = List.from(outcomes);
      final matches = _allConfirmedMatches[branch];
      if (matches != null) {
        matches.forEach((index, matchedItem) {
          if (index < updatedList.length) {
            updatedList[index] = OutcomeItem(
              code: matchedItem.code,
              description: matchedItem.description,
              depth: updatedList[index].depth,
            );
          }
        });
      }
      finalResults[branch] = updatedList;
    });

    Navigator.pop(context, finalResults);
  }

  bool _isMobileView = false;
  bool _showMobileSuggestions = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _isMobileView = constraints.maxWidth < 700;

        // If we are on mobile and have a selection, we might want to show suggestions
        Widget content;
        if (_isMobileView) {
          if (_showMobileSuggestions && _selectedLeftIndex != null) {
            content = _buildRightPanel(isMobile: true);
          } else {
            content = _buildLeftPanel(isMobile: true);
          }
        } else {
          // Desktop: Side by Side
          content = Row(
            children: [
              Expanded(flex: 1, child: _buildLeftPanel()),
              Expanded(flex: 1, child: _buildRightPanel()),
            ],
          );
        }

        return Scaffold(
          backgroundColor: Colors.grey[50],
          appBar: AppBar(
            title: Text(
              _isMobileView && _showMobileSuggestions
                  ? 'Eşleşme Seç'
                  : 'Kazanım Eşleştirme',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            elevation: 0,
            leading: (_isMobileView && _showMobileSuggestions)
                ? IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () =>
                        setState(() => _showMobileSuggestions = false),
                  )
                : const BackButton(color: Colors.white),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (value) {
                  if (value == 'auto_match') {
                    _runAutoMatch();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Otomatik eşleştirme çalıştırıldı.'),
                      ),
                    );
                  }
                },
                itemBuilder: (BuildContext context) {
                  return [
                    const PopupMenuItem<String>(
                      value: 'auto_match',
                      child: Row(
                        children: [
                          Icon(Icons.auto_fix_high, color: Colors.teal),
                          SizedBox(width: 8),
                          Text('Otomatik Eşle (Yenile)'),
                        ],
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _finish,
            label: Text('KAYDET'),
            icon: Icon(Icons.check),
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
          body: _isLoading
              ? Center(child: CircularProgressIndicator())
              : content,
        );
      },
    );
  }

  Widget _buildLeftPanel({bool isMobile = false}) {
    final currentList = widget.allOutcomes[_currentBranch] ?? [];
    final branchMatches = _allConfirmedMatches[_currentBranch] ?? {};

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: isMobile
            ? null
            : Border(right: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          // Stylized Dropdown-like Header for Current List
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YÜKLENEN LİSTE',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                    letterSpacing: 1.1,
                  ),
                ),
                SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _currentBranch,
                      items: widget.allOutcomes.keys.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(
                            value,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blueGrey.shade800,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: _onBranchChanged,
                      icon: Icon(Icons.arrow_drop_down, color: Colors.grey),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: currentList.length,
              separatorBuilder: (c, i) => Divider(height: 1),
              itemBuilder: (context, index) {
                final item = currentList[index];
                final isSelected = _selectedLeftIndex == index;
                final isMatched = branchMatches.containsKey(index);
                final matchedItem = branchMatches[index];

                return Material(
                  color: isSelected
                      ? Colors.teal.shade50
                      : (isMatched
                            ? Colors.green.shade50
                            : (item.depth == 1
                                  ? Colors.grey[100]
                                  : Colors.white)),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedLeftIndex = index;
                        if (_isMobileView) {
                          _showMobileSuggestions = true;
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 12.0,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isMatched
                                ? Icons.check_circle
                                : (item.depth == 1
                                      ? Icons.folder_outlined
                                      : Icons.circle_outlined),
                            color: isMatched ? Colors.green : Colors.grey[400],
                            size: 20,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (item.code.isNotEmpty ||
                                    item.k12Code.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        if (item.code.isNotEmpty)
                                          Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: Colors.blue.shade100,
                                              ),
                                            ),
                                            child: Text(
                                              item.code,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue.shade800,
                                              ),
                                            ),
                                          ),
                                        if (item.code.isNotEmpty &&
                                            item.k12Code.isNotEmpty)
                                          SizedBox(width: 4),
                                        if (item.k12Code.isNotEmpty)
                                          Text(
                                            'K12: ${item.k12Code}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                Text(
                                  item.description.isNotEmpty
                                      ? item.description
                                      : (item.code.isNotEmpty
                                            ? 'Kod: ${item.code}'
                                            : (item.k12Code.isNotEmpty
                                                  ? 'K12: ${item.k12Code}'
                                                  : '-')),
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 13,
                                    fontWeight: (item.depth == 1 || isSelected)
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                if (isMatched) ...[
                                  SizedBox(height: 4),
                                  Container(
                                    padding: EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Eşleşen: ${matchedItem?.description}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green[800],
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: isSelected ? Colors.teal : Colors.grey[300],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel({bool isMobile = false}) {
    final suggestions = _getSuggestionsForSelected();
    final branchMatches = _allConfirmedMatches[_currentBranch] ?? {};

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EŞLEŞME ÖNERİLERİ & ARAMA',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                  letterSpacing: 1.1,
                ),
              ),
              SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Kazanım, kod veya K12 ara...',
                  prefixIcon: Icon(Icons.search, color: Colors.teal),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) {
                  setState(() => _searchQuery = val);
                },
              ),
              SizedBox(height: 12),
              if (_availableLists.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedListId,
                      hint: Text('Referans Liste Seçiniz'),
                      onChanged: _onMasterListChanged,
                      items: _availableLists.map((list) {
                        return DropdownMenuItem<String>(
                          value: list.id,
                          child: Text(
                            list.name.isNotEmpty
                                ? list.name
                                : '${list.classLevel} - ${list.branchName}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                )
              else
                Text(
                  'Kayıtlı kazanım listesi bulunamadı.',
                  style: TextStyle(color: Colors.red),
                ),
            ],
          ),
        ),
        Expanded(
          child:
              (suggestions.isEmpty &&
                  _searchQuery.isEmpty &&
                  _selectedLeftIndex == null)
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.touch_app, size: 64, color: Colors.grey[300]),
                      SizedBox(height: 16),
                      Text(
                        'Soldan bir kazanım seçiniz.',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: suggestions.length,
                  itemBuilder: (context, index) {
                    final entry = suggestions[index];
                    final outcome = entry.key;
                    final score = entry.value;
                    final percentage = (score * 100).toInt();

                    Color scoreColor = percentage > 80
                        ? Colors.green
                        : (percentage > 50 ? Colors.orange : Colors.grey);

                    final currentMatch = _selectedLeftIndex != null
                        ? branchMatches[_selectedLeftIndex!]
                        : null;
                    final bool isThisMatched =
                        currentMatch != null &&
                        currentMatch.code == outcome.code &&
                        currentMatch.description == outcome.description;

                    return Card(
                      elevation: 2,
                      margin: EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isThisMatched
                            ? BorderSide(color: Colors.green, width: 2)
                            : BorderSide.none,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scoreColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: scoreColor.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Text(
                                    percentage > 180
                                        ? 'KOD EŞLEŞMESİ'
                                        : (percentage > 100
                                              ? 'K12 EŞLEŞMESİ'
                                              : '%$percentage Benzerlik'),
                                    style: TextStyle(
                                      color: scoreColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                if (isThisMatched)
                                  Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Text(
                                      'EŞLEŞTİRİLDİ',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                Spacer(),
                                if (outcome.code.isNotEmpty)
                                  Text(
                                    outcome.code,
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(
                              outcome.description,
                              style: TextStyle(fontSize: 14, height: 1.3),
                            ),
                            SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () => _toggleMatch(outcome),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: isThisMatched
                                      ? Colors.red.shade50
                                      : Colors.transparent,
                                  foregroundColor: isThisMatched
                                      ? Colors.red
                                      : Colors.teal,
                                  side: BorderSide(
                                    color: isThisMatched
                                        ? Colors.red
                                        : Colors.teal,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  isThisMatched
                                      ? 'EŞLEŞMEYİ KALDIR'
                                      : 'BU KAZANIMLA EŞLE',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
