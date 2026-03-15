import 'package:flutter/material.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import 'evaluation_models.dart';

class MatchedStudentsDialog extends StatefulWidget {
  final List<StudentResult> results;
  final List<TrialExamSession> sessions;
  final Function(StudentResult result) onUnmatch;

  const MatchedStudentsDialog({
    Key? key,
    required this.results,
    required this.sessions,
    required this.onUnmatch,
  }) : super(key: key);

  @override
  _MatchedStudentsDialogState createState() => _MatchedStudentsDialogState();
}

class _MatchedStudentsDialogState extends State<MatchedStudentsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // If no sessions, default to 1 tab
    int length = widget.sessions.isEmpty ? 1 : widget.sessions.length;
    _tabController = TabController(length: length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<StudentResult> _getMatchedForSession(int sessionNumber) {
    if (widget.sessions.isEmpty)
      return widget.results.where((s) => s.isMatched).toList();

    return widget.results
        .where(
          (s) => s.isMatched && s.participatedSessions.contains(sessionNumber),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    // Determine tabs
    List<Widget> tabs = [];
    List<Widget> tabViews = [];

    if (widget.sessions.isEmpty) {
      tabs.add(Tab(text: "Tüm Liste"));
      tabViews.add(
        _buildStudentList(widget.results.where((s) => s.isMatched).toList()),
      );
    } else {
      for (var session in widget.sessions) {
        tabs.add(Tab(text: "${session.sessionNumber}. Oturum"));
        tabViews.add(
          _buildStudentList(_getMatchedForSession(session.sessionNumber)),
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
          // Header
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
                          'Eşleşen Öğrenciler',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Sistemle başarıyla eşleşen öğrenciler',
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
                  labelColor: Colors.green.shade700,
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: Colors.green.shade600,
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

  Widget _buildStudentList(List<StudentResult> list) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey.shade300),
            SizedBox(height: 16),
            Text(
              "Bu oturumda eşleşen öğrenci yok.",
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final s = list[index];
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
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    s.booklet.isNotEmpty ? s.booklet : "A",
                    style: TextStyle(
                      color: Colors.green.shade800,
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
                        s.name,
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
                          if (s.studentNo.isNotEmpty)
                            _buildTag("No: ${s.studentNo}", Colors.blue),
                          if (s.branch.isNotEmpty)
                            _buildTag("Şube: ${s.branch}", Colors.purple),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _confirmUnmatch(s),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red.shade700,
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: Icon(Icons.link_off, size: 16),
                  label: Text("Ayır"),
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

  void _confirmUnmatch(StudentResult student) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Eşleşmeyi Kaldır"),
        content: Text(
          "${student.name} öğrencisinin eşleşmesi kaldırılacak. Bu işlem geri alınamaz.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("İptal"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close confirm
              widget.onUnmatch(student);
              setState(
                () {},
              ); // Re-render list if needed, though parent handles it usually
            },
            child: Text("Kaldır", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
