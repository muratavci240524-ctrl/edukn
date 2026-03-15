import 'package:flutter/material.dart';
import '../../../../models/project_assignment_model.dart';
import '../../../../services/project_assignment_service.dart';
import 'project_assignment_dashboard_screen.dart';
import 'project_assignment_form_screen.dart';

class ProjectAssignmentListScreen extends StatelessWidget {
  final String institutionId;

  const ProjectAssignmentListScreen({Key? key, required this.institutionId})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (institutionId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Kurum bilgisi bulunamadı')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Proje Görevlendirmeleri',
          style: TextStyle(color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: StreamBuilder<List<ProjectAssignment>>(
        stream: ProjectAssignmentService().getProjectAssignments(institutionId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Hata: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final assignments = snapshot.data ?? [];

          if (assignments.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.assignment_outlined,
                    size: 64,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  const Text('Henüz proje görevlendirmesi oluşturulmamış'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProjectAssignmentFormScreen(
                            institutionId: institutionId,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Yeni Oluştur'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: assignments.length,
            itemBuilder: (context, index) {
              final assignment = assignments[index];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo.shade50,
                    child: const Icon(
                      Icons.folder_shared,
                      color: Colors.indigo,
                    ),
                  ),
                  title: Text(
                    assignment.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        'Dönem: ${assignment.termId.isEmpty ? "-" : assignment.termId}',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      Text(
                        '${assignment.topics.length} Konu • ${assignment.allocations.length} / ${assignment.targetStudentIds.length} Atama',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProjectAssignmentDashboardScreen(
                          assignment: assignment,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ProjectAssignmentFormScreen(institutionId: institutionId),
            ),
          );
        },
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.add),
      ),
    );
  }
}
