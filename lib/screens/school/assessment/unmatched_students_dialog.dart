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

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Premium Header
          Container(
            padding: EdgeInsets.fromLTRB(24, 20, 24, 0),
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
          Flexible(
            child: Container(
              color: Colors.grey.shade50,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.65,
              ),
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
  final List<Map<String, dynamic>> candidates;
  final Set<String> matchedIds;
  final Function(Map<String, dynamic>) onSelect;

  const _SystemStudentSearchDialog({
    Key? key,
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
      final nameA = (a['fullName'] ?? a['name'] ?? '').toString();
      final nameB = (b['fullName'] ?? b['name'] ?? '').toString();
      return nameA.compareTo(nameB);
    });
  }

  void _search(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredList = List.from(widget.candidates);
      } else {
        _filteredList = widget.candidates.where((s) {
          final name = (s['fullName'] ?? s['name'] ?? '')
              .toString()
              .toLowerCase();
          final no = (s['studentNo'] ?? '').toString();
          final tc = (s['tcNo'] ?? '').toString();
          return name.contains(_searchQuery) ||
              no.contains(_searchQuery) ||
              tc.contains(_searchQuery);
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
                Text(
                  "Öğrenci Seç",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
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
              height: 400, // Fixed height for consistency
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade100),
                  bottom: BorderSide(color: Colors.grey.shade100),
                ),
              ),
              child: _filteredList.isEmpty
                  ? Center(
                      child: Text(
                        "Sonuç bulunamadı",
                        style: TextStyle(color: Colors.grey),
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

                        return ListTile(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 4,
                          ),
                          title: Text(
                            s['fullName'] ?? s['name'] ?? 'İsimsiz',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            "No: ${s['studentNo']} | Şube: ${s['classLevel']}-${s['className'] ?? s['branch'] ?? '-'}",
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
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
                                  color: Colors.grey.shade300,
                                ),
                          onTap: () {
                            // If matched, user wants to merge specific session into this existing student
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
