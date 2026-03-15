import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../models/activity/activity_model.dart';
import '../../../../services/activity_service.dart';
import 'activity_evaluation_screen.dart';

class ActivityDetailScreen extends StatefulWidget {
  final ActivityObservation activity;

  const ActivityDetailScreen({Key? key, required this.activity})
    : super(key: key);

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Set<String> _participatedIds = {};

  // Cache student info
  Map<String, Map<String, dynamic>> _studentDetails = {};
  bool _isLoadingStudents = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _participatedIds = widget.activity.participatedStudentIds.toSet();
    _loadStudentDetails();
  }

  Future<void> _loadStudentDetails() async {
    if (widget.activity.targetStudentIds.isEmpty) {
      if (mounted) setState(() => _isLoadingStudents = false);
      return;
    }

    // Split into chunks of 10 for 'in' queries
    final chunks = <List<String>>[];
    for (var i = 0; i < widget.activity.targetStudentIds.length; i += 10) {
      chunks.add(
        widget.activity.targetStudentIds.sublist(
          i,
          i + 10 > widget.activity.targetStudentIds.length
              ? widget.activity.targetStudentIds.length
              : i + 10,
        ),
      );
    }

    for (var chunk in chunks) {
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (var doc in snapshot.docs) {
        _studentDetails[doc.id] = doc.data();
      }
    }

    if (mounted) setState(() => _isLoadingStudents = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.activity.title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.indigo,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.indigo,
          tabs: const [
            Tab(text: 'Genel Bilgi'),
            Tab(text: 'Katılımcı Durumu'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildInfoTab(), _buildParticipantsTab()],
      ),
    );
  }

  Widget _buildInfoTab() {
    final act = widget.activity;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            title: 'Etkinlik Detayları',
            children: [
              _buildInfoRow(
                'Tarih',
                '${act.date.day}.${act.date.month}.${act.date.year}',
              ),
              _buildInfoRow(
                'Tür',
                act.type == 'observation' ? 'Gözlem' : 'Etkinlik',
              ),
              _buildInfoRow('Sorumlu', act.responsibleTeacherName),
              const SizedBox(height: 8),
              const Text(
                'Açıklama:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (act.description.isNotEmpty)
                Text(act.description)
              else
                const Text(
                  'Açıklama yok',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            title: 'Değerlendirme Ayarları',
            children: [
              _buildInfoRow(
                'Durum',
                act.isEvaluationEnabled ? 'Aktif' : 'Kapalı',
              ),
              if (act.isEvaluationEnabled) ...[
                _buildInfoRow('Soru Sayısı', '${act.questions.length}'),
                // If we implemented viewing evaluators, list them here
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsTab() {
    if (_isLoadingStudents) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.activity.targetStudentIds.isEmpty) {
      return const Center(child: Text('Katılımcı bulunamadı'));
    }

    // Determine if we should show participation toggle
    final isActivity = widget.activity.type == 'activity';

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: widget.activity.targetStudentIds.length,
      itemBuilder: (context, index) {
        final studentId = widget.activity.targetStudentIds[index];
        final studentData = _studentDetails[studentId] ?? {};
        final studentName =
            studentData['fullName'] ?? studentData['name'] ?? 'Bilinmiyor';
        final className = studentData['className'] ?? '-';
        final number = studentData['studentNumber'] ?? '-';

        bool isParticipated = _participatedIds.contains(studentId);

        return Card(
          elevation: 1,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isParticipated
                  ? Colors.green.shade100
                  : Colors.indigo.shade50,
              child: Text(
                studentName.isNotEmpty ? studentName[0] : '?',
                style: TextStyle(
                  color: isParticipated ? Colors.green : Colors.indigo,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(studentName),
            subtitle: Text('$className - No: $number'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActivity)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Checkbox(
                        value: isParticipated,
                        activeColor: Colors.green,
                        onChanged: (val) =>
                            _toggleParticipation(studentId, val),
                      ),
                    ],
                  ),
                if (widget.activity.isEvaluationEnabled) ...[
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade50,
                      foregroundColor: Colors.indigo,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ActivityEvaluationScreen(
                            activity: widget.activity,
                            studentId: studentId,
                            studentName: studentName,
                          ),
                        ),
                      );
                    },
                    child: const Text('Değerlendir'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleParticipation(String studentId, bool? value) async {
    if (value == null) return;

    setState(() {
      if (value) {
        _participatedIds.add(studentId);
      } else {
        _participatedIds.remove(studentId);
      }
    });

    // Valid update to Firestore
    try {
      await ActivityService().updateParticipationStatus(
        widget.activity.id,
        _participatedIds.toList(),
      );
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() {
          if (value) {
            _participatedIds.remove(studentId);
          } else {
            _participatedIds.add(studentId);
          }
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }
}
