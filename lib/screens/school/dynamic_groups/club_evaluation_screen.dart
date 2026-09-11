import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import '../../../models/school/dynamic_course_group_model.dart';
import '../../../services/dynamic_group_service.dart';

const Color _clubColor = Color(0xFF059669);
const Color _clubLightColor = Color(0xFFD1FAE5);

class ClubEvaluationScreen extends StatefulWidget {
  final DynamicCourseGroup group;
  final String institutionId;
  final String schoolTypeId;
  final String termId;

  const ClubEvaluationScreen({
    super.key,
    required this.group,
    required this.institutionId,
    required this.schoolTypeId,
    required this.termId,
  });

  @override
  State<ClubEvaluationScreen> createState() => _ClubEvaluationScreenState();
}

class _ClubEvaluationScreenState extends State<ClubEvaluationScreen> {
  final DynamicGroupService _groupService = DynamicGroupService();
  String? _selectedSubGroupId;
  bool _loading = false;
  List<Map<String, dynamic>> _students = [];
  Map<String, Map<String, dynamic>> _evaluationsByStudentId = {};

  @override
  void initState() {
    super.initState();
    if (widget.group.subGroups.isNotEmpty) {
      _selectedSubGroupId = widget.group.subGroups.first.id;
      _loadStudentsAndEvaluations();
    }
  }

  Future<void> _loadStudentsAndEvaluations() async {
    if (_selectedSubGroupId == null) return;
    setState(() => _loading = true);

    try {
      final sub = widget.group.subGroups.firstWhere((s) => s.id == _selectedSubGroupId);

      final students = await _groupService.loadStudentsForSubGroup(
        subGroup: sub,
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
      );

      final evals = await _groupService.loadClubEvaluations(
        termId: widget.termId,
        groupId: widget.group.id,
        subGroupId: _selectedSubGroupId!,
      );

      if (mounted) {
        setState(() {
          _students = students;
          _evaluationsByStudentId = evals;
        });
      }
    } catch (e) {
      debugPrint('Error loading evaluation data: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openEvaluationDialog(Map<String, dynamic> student) {
    final sId = student['id'].toString();
    final fullName = '${student['firstName'] ?? ''} ${student['lastName'] ?? ''}'.trim();
    final className = (student['className'] ?? '-').toString();

    final existing = _evaluationsByStudentId[sId] ?? {};

    int attendanceScore = existing['attendanceScore'] ?? 5;
    int interestScore = existing['interestScore'] ?? 5;
    int teamworkScore = existing['teamworkScore'] ?? 5;
    int developmentScore = existing['developmentScore'] ?? 5;
    final noteCtrl = TextEditingController(text: existing['note'] ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$fullName Değerlendirmesi', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        Text('Şube: $className', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildRatingRow('Katılım ve Devamlılık', attendanceScore, (val) => setDlgState(() => attendanceScore = val)),
                      const SizedBox(height: 10),
                      _buildRatingRow('İlgi ve İstek', interestScore, (val) => setDlgState(() => interestScore = val)),
                      const SizedBox(height: 10),
                      _buildRatingRow('Takım Çalışması ve Uyum', teamworkScore, (val) => setDlgState(() => teamworkScore = val)),
                      const SizedBox(height: 10),
                      _buildRatingRow('Yetenek ve Gelişim', developmentScore, (val) => setDlgState(() => developmentScore = val)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: noteCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Öğretmen Görüşü / Sosyal Etkinlik Notu',
                          hintText: 'Öğrencinin kulüpteki performansı hakkında kısa açıklama...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600),
                  onPressed: () async {
                    final data = {
                      'attendanceScore': attendanceScore,
                      'interestScore': interestScore,
                      'teamworkScore': teamworkScore,
                      'developmentScore': developmentScore,
                      'note': noteCtrl.text.trim(),
                      'evaluatedAt': DateTime.now().toIso8601String(),
                    };

                    await _groupService.saveClubEvaluation(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                      termId: widget.termId,
                      groupId: widget.group.id,
                      subGroupId: _selectedSubGroupId!,
                      studentId: sId,
                      evaluationData: data,
                    );

                    if (!mounted) return;
                    setState(() {
                      _evaluationsByStudentId[sId] = data;
                    });

                    Navigator.pop(context);
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildRatingRow(String label, int currentScore, ValueChanged<int> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        Row(
          children: List.generate(5, (index) {
            final star = index + 1;
            return IconButton(
              iconSize: 22,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: Icon(
                star <= currentScore ? Icons.star_rounded : Icons.star_outline_rounded,
                color: star <= currentScore ? Colors.amber : Colors.grey.shade400,
              ),
              onPressed: () => onChanged(star),
            );
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: '${widget.group.name} - Değerlendirme',
        subtitle: 'Öğrenci Kulüp Kazanım ve Takip Paneli',
      ),
      body: Column(
        children: [
          // Branş / Alt Grup Seçici
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.white,
            child: Row(
              children: [
                const Text('Kulüp Branşı: ', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _selectedSubGroupId,
                  items: widget.group.subGroups.map((sub) {
                    return DropdownMenuItem<String>(
                      value: sub.id,
                      child: Text('${sub.name} (${sub.studentIds.length} Öğrenci)'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedSubGroupId = val);
                      _loadStudentsAndEvaluations();
                    }
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _students.isEmpty
                    ? const Center(child: Text('Bu branşa atanmış öğrenci bulunmuyor.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _students.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final s = _students[index];
                          final sId = s['id'].toString();
                          final fullName = '${s['firstName'] ?? ''} ${s['lastName'] ?? ''}'.trim();
                          final number = (s['studentNumber'] ?? s['number'] ?? '-').toString();
                          final className = (s['className'] ?? '-').toString();

                          final eval = _evaluationsByStudentId[sId];
                          final isEvaluated = eval != null;

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isEvaluated ? _clubLightColor : Colors.grey.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: isEvaluated ? _clubLightColor : Colors.grey.shade100,
                                  child: Icon(
                                    isEvaluated ? Icons.check_circle_rounded : Icons.person_outline_rounded,
                                    color: isEvaluated ? _clubColor : Colors.grey.shade500,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                      Text('No: $number | Şube: $className', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                      if (isEvaluated && (eval['note'] ?? '').toString().isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            '"${eval['note']}"',
                                            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.indigo.shade800),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: isEvaluated ? _clubLightColor : Colors.indigo.shade50,
                                    foregroundColor: isEvaluated ? _clubColor : Colors.indigo.shade800,
                                  ),
                                  icon: Icon(isEvaluated ? Icons.edit_note_rounded : Icons.star_outline_rounded, size: 18),
                                  label: Text(isEvaluated ? 'Düzenle' : 'Değerlendir'),
                                  onPressed: () => _openEvaluationDialog(s),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
