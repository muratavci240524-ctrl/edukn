import 'package:flutter/material.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import 'evaluation_models.dart';

class UnmatchedStudentsDialog extends StatefulWidget {
  final List<StudentResult> results;
  final List<Map<String, dynamic>> allSystemStudents;
  final List<TrialExamSession> sessions;
  final Function(
    StudentResult original,
    Map<String, dynamic> matchedSystemStudent,
  )
  onMatch;

  const UnmatchedStudentsDialog({
    Key? key,
    required this.results,
    required this.allSystemStudents,
    required this.sessions,
    required this.onMatch,
  }) : super(key: key);

  @override
  _UnmatchedStudentsDialogState createState() =>
      _UnmatchedStudentsDialogState();
}

class _UnmatchedStudentsDialogState extends State<UnmatchedStudentsDialog>
    with SingleTickerProviderStateMixin {
  late List<StudentResult> _unmatchedList;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _filterList();
    int length = widget.sessions.isEmpty ? 1 : widget.sessions.length;
    _tabController = TabController(length: length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _filterList() {
    _unmatchedList = widget.results.where((s) => !s.isMatched).toList();
  }

  List<StudentResult> _getUnmatchedForSession(int sessionNumber) {
    if (widget.sessions.isEmpty) return _unmatchedList;
    return _unmatchedList
        .where((s) => s.participatedSessions.contains(sessionNumber))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> tabs = [];
    List<Widget> tabViews = [];

    if (widget.sessions.isEmpty) {
      tabs.add(Tab(text: "Tüm Liste"));
      tabViews.add(_buildList(_unmatchedList));
    } else {
      for (var session in widget.sessions) {
        tabs.add(Tab(text: "${session.sessionNumber}. Oturum"));
        tabViews.add(
          _buildList(_getUnmatchedForSession(session.sessionNumber)),
        );
      }
    }

    // Alttan açılan menü (bottom sheet) içeriği
    return Material(
      color: Colors.white,
      child: Column(
        children: [
          // Premium Header
          Container(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Eşleşmeyen Öğrenciler',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                            fontFamily: 'GoogleFonts.inter', // Assuming usage
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '${_unmatchedList.length} öğrenci sistemle eşleşmedi',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.grey.shade400),
                      onPressed: () => Navigator.pop(context),
                      splashRadius: 20,
                    ),
                  ],
                ),
                SizedBox(height: 16),
                TabBar(
                  controller: _tabController,
                  labelColor: Colors.indigo,
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: Colors.indigo,
                  indicatorWeight: 3,
                  labelStyle: TextStyle(fontWeight: FontWeight.w600),
                  tabs: tabs,
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: Container(
              color: Colors.grey.shade50,
              child: TabBarView(controller: _tabController, children: tabViews),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<StudentResult> list) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 48,
                color: Colors.green.shade400,
              ),
            ),
            SizedBox(height: 16),
            Text(
              "Bu oturumda eşleşmeyen öğrenci yok",
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final student = list[index];
        return Card(
          elevation: 0,
          margin: EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    student.booklet.isNotEmpty ? student.booklet : "?",
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.name.isNotEmpty ? student.name : "İsimsiz",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (student.studentNo.isNotEmpty)
                            _buildTag("No: ${student.studentNo}", Colors.blue),
                          if (student.tcNo.isNotEmpty)
                            _buildTag("TC: ${student.tcNo}", Colors.blueGrey),
                          if (student.classLevel.isNotEmpty ||
                              student.branch.isNotEmpty)
                            _buildTag(
                              "${student.classLevel}-${student.branch}",
                              Colors.purple,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _openMatchDialog(student),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.indigo.shade50,
                    foregroundColor: Colors.indigo,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: Icon(Icons.link, size: 18),
                  label: Text("Eşle"),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTag(String text, MaterialColor color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.shade100),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color.shade700,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _openMatchDialog(StudentResult student) {
    // Identify currently matched IDs to show status
    final matchedIds = widget.results
        .where((r) => r.isMatched && r.systemStudentId != null)
        .map((r) => r.systemStudentId!)
        .toSet();

    showDialog(
      context: context,
      builder: (context) => _SystemStudentSearchDialog(
        targetStudent: student,
        candidates: widget.allSystemStudents,
        matchedIds: matchedIds,
        onSelect: (selectedSystemStudent) {
          widget.onMatch(student, selectedSystemStudent);
          setState(() {
            _filterList(); // Re-filter to remove matched
          });
          Navigator.pop(context); // Close match dialog
        },
      ),
    );
  }
}

class _SystemStudentSearchDialog extends StatefulWidget {
  final StudentResult? targetStudent;
  final List<Map<String, dynamic>> candidates;
  final Set<String> matchedIds;
  final Function(Map<String, dynamic>) onSelect;

  const _SystemStudentSearchDialog({
    Key? key,
    this.targetStudent,
    required this.candidates,
    required this.matchedIds,
    required this.onSelect,
  }) : super(key: key);

  @override
  __SystemStudentSearchDialogState createState() =>
      __SystemStudentSearchDialogState();
}

class __SystemStudentSearchDialogState
    extends State<_SystemStudentSearchDialog> {
  String _searchQuery = "";
  List<Map<String, dynamic>> _filteredList = [];

  @override
  void initState() {
    super.initState();
    _filteredList = List.from(widget.candidates);
    _sortList();
  }

  void _sortList() {
    _filteredList.sort((a, b) {
      if (widget.targetStudent != null) {
        final scoreA = StudentMatcher.scoreCandidate(a, widget.targetStudent!);
        final scoreB = StudentMatcher.scoreCandidate(b, widget.targetStudent!);
        if (scoreA != scoreB) {
          return scoreB.compareTo(scoreA); // En yüksek eşleşme skoru en üstte
        }
      }
      final nameA = (a['fullName'] ?? a['name'] ?? '').toString();
      final nameB = (b['fullName'] ?? b['name'] ?? '').toString();
      return nameA.compareTo(nameB);
    });
  }

  void _search(String query) {
    setState(() {
      _searchQuery = StudentMatcher.normalizeTurkishForSearch(query);
      if (_searchQuery.isEmpty) {
        _filteredList = List.from(widget.candidates);
      } else {
        _filteredList = widget.candidates.where((s) {
          final name = StudentMatcher.normalizeTurkishForSearch(
            (s['fullName'] ?? s['name'] ?? '').toString(),
          );
          final no = (s['studentNo'] ?? s['studentNumber'] ?? '')
              .toString()
              .toLowerCase();
          final tc = (s['tcNo'] ?? '').toString();
          final branch = (s['className'] ?? s['branch'] ?? '')
              .toString()
              .toLowerCase();
          return name.contains(_searchQuery) ||
              no.contains(_searchQuery) ||
              tc.contains(_searchQuery) ||
              branch.contains(_searchQuery);
        }).toList();
      }
      _sortList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Öğrenci Seç",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      "${_filteredList.length} Öğrenci",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                if (widget.targetStudent != null) ...[
                  SizedBox(height: 10),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.indigo.shade100),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_search,
                          size: 20,
                          color: Colors.indigo.shade700,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Optik Kayıt: ${widget.targetStudent!.name} (No: ${widget.targetStudent!.studentNo.isNotEmpty ? widget.targetStudent!.studentNo : '-'}, Şube: ${widget.targetStudent!.branch.isNotEmpty ? widget.targetStudent!.branch : '-'})",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.indigo.shade900,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: 12),
                TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: "İsim, Numara veya TC ile ara...",
                    prefixIcon: Icon(Icons.search, color: Colors.indigo),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.indigo.shade200,
                        width: 2,
                      ),
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onChanged: _search,
                ),
              ],
            ),
          ),
          Flexible(
            child: Container(
              height: 420, // Fixed height for consistency
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade100),
                  bottom: BorderSide(color: Colors.grey.shade100),
                ),
              ),
              child: _filteredList.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 40, color: Colors.grey.shade300),
                          SizedBox(height: 8),
                          Text(
                            "Sonuç bulunamadı",
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: _filteredList.length,
                      separatorBuilder: (c, i) =>
                          Divider(height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (context, index) {
                        final s = _filteredList[index];
                        final isMatched = widget.matchedIds.contains(s['id']);
                        final isRecommended = widget.targetStudent != null &&
                            StudentMatcher.scoreCandidate(s, widget.targetStudent!) >= 100;

                        final branchText = (s['className'] ?? s['branch'] ?? s['classLevel'] ?? '').toString();
                        final noText = (s['studentNo'] ?? s['studentNumber'] ?? '').toString();
                        final tcText = (s['tcNo'] ?? '').toString();

                        return ListTile(
                          tileColor: isRecommended ? Colors.amber.shade50.withValues(alpha: 0.3) : null,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 4,
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  s['fullName'] ?? s['name'] ?? 'İsimsiz',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              if (isRecommended)
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  margin: EdgeInsets.only(left: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.amber.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.star,
                                        size: 12,
                                        color: Colors.amber.shade900,
                                      ),
                                      SizedBox(width: 3),
                                      Text(
                                        "Önerilen",
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber.shade900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            "No: ${noText.isNotEmpty ? noText : '-'}"
                            "${branchText.isNotEmpty ? ' | Şube: $branchText' : ''}"
                            "${tcText.isNotEmpty && !tcText.startsWith('ENC:') ? ' | TC: $tcText' : ''}",
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                          trailing: isMatched
                              ? Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.green.shade100,
                                    ),
                                  ),
                                  child: Text(
                                    "EŞLEŞMİŞ",
                                    style: TextStyle(
                                      color: Colors.green.shade700,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey.shade400,
                                ),
                          onTap: () {
                            widget.onSelect(s);
                          },
                        );
                      },
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'İptal',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

