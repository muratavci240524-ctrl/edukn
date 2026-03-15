import 'package:flutter/material.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import 'evaluation_models.dart';

class AbsentStudentsDialog extends StatefulWidget {
  final Map<String, dynamic> systemStudentsMap;
  final List<StudentResult> results;
  final List<TrialExamSession> sessions;

  const AbsentStudentsDialog({
    Key? key,
    required this.systemStudentsMap,
    required this.results,
    required this.sessions,
  }) : super(key: key);

  @override
  _AbsentStudentsDialogState createState() => _AbsentStudentsDialogState();
}

class _AbsentStudentsDialogState extends State<AbsentStudentsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.sessions.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getAbsentForSession(int sessionNumber) {
    final List<Map<String, dynamic>> absent = [];

    widget.systemStudentsMap.forEach((sysId, sysData) {
      // Find matches
      final match = widget.results.firstWhere(
        (r) => r.isMatched && r.systemStudentId == sysId,
        orElse: () => StudentResult(
          studentNo: '',
          name: '',
          tcNo: '',
          classLevel: '',
          branch: '',
        ), // Dummy
      );

      bool isParticipated = false;
      if (match.systemStudentId != null) {
        // Found a matched result for this student
        if (match.participatedSessions.contains(sessionNumber)) {
          isParticipated = true;
        }
      }

      if (!isParticipated) {
        absent.add(sysData);
      }
    });

    return absent;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        height: 600,
        width: 500,
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              "Katılmayan Öğrenciler",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.red.shade700,
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.black87,
                tabs: widget.sessions
                    .map((s) => Tab(text: "${s.sessionNumber}. Oturum"))
                    .toList(),
              ),
            ),
            SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: widget.sessions.map((session) {
                  final absentList = _getAbsentForSession(
                    session.sessionNumber,
                  );
                  if (absentList.isEmpty) {
                    return Center(
                      child: Text("Bu oturumda eksik öğrenci yok."),
                    );
                  }
                  return ListView.separated(
                    itemCount: absentList.length,
                    separatorBuilder: (c, i) => Divider(),
                    itemBuilder: (context, index) {
                      final s = absentList[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red.shade100,
                          child: Text(
                            "${index + 1}",
                            style: TextStyle(
                              color: Colors.red.shade800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        title: Text(
                          "${s['fullName'] ?? s['name']} ${s['surname'] ?? ''}",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          "No: ${s['studentNo']} - Şube: ${s['className'] ?? s['branch'] ?? '-'}",
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
            ),
            SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Kapat"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
