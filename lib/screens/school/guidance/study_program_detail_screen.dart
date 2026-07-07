import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../services/guidance_service.dart';
import 'study_program_printing_helper.dart';

class StudyProgramDetailScreen extends StatefulWidget {
  final String institutionId;
  final Map<String, dynamic> program;

  const StudyProgramDetailScreen({
    Key? key,
    required this.institutionId,
    required this.program,
  }) : super(key: key);

  @override
  _StudyProgramDetailScreenState createState() =>
      _StudyProgramDetailScreenState();
}

class _StudyProgramDetailScreenState extends State<StudyProgramDetailScreen> {
  late Map<String, List<int>> _executionStatus;
  final _guidanceService = GuidanceService();
  bool _isSaving = false;

  final _evaluationController = TextEditingController();
  final _targetController = TextEditingController();
  late Map<String, dynamic> _priorityTasks;

  @override
  void initState() {
    super.initState();
    _initializeStatus();
    _evaluationController.text = widget.program['mentorEvaluation'] ?? '';
    _targetController.text = widget.program['weeklyTarget'] ?? '';
    _priorityTasks = Map<String, dynamic>.from(widget.program['priorityTasks'] ?? {});
  }

  @override
  void dispose() {
    _evaluationController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  void _initializeStatus() {
    if (widget.program['executionStatus'] != null) {
      _executionStatus = Map<String, List<int>>.from(
        (widget.program['executionStatus'] as Map).map(
          (k, v) => MapEntry(k.toString(), List<int>.from(v)),
        ),
      );
    } else {
      _executionStatus = {};
      final schedule = widget.program['schedule'] as Map<String, dynamic>;
      schedule.forEach((day, lessons) {
        _executionStatus[day] = List.filled((lessons as List).length, 0);
      });
    }
  }

  Future<void> _saveFullProgram() async {
    setState(() => _isSaving = true);
    try {
      // 1. Update executionStatus
      await _guidanceService.updateStudyProgramStatus(
        widget.institutionId,
        widget.program['id'],
        _executionStatus,
      );

      // 2. Fetch logged in user display name
      final user = FirebaseAuth.instance.currentUser;
      String mentorName = 'Mentör';
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        mentorName = doc.data()?['fullName'] ?? doc.data()?['name'] ?? user.displayName ?? 'Mentör';
      }

      // 3. Update evaluation, target, and priorities
      await _guidanceService.updateStudyProgramEvaluation(
        widget.institutionId,
        widget.program['id'],
        mentorEvaluation: _evaluationController.text.trim(),
        mentorEvaluationBy: mentorName,
        weeklyTarget: _targetController.text.trim(),
        priorityTasks: _priorityTasks,
      );

      // Keep local program model synchronized
      widget.program['executionStatus'] = _executionStatus;
      widget.program['mentorEvaluation'] = _evaluationController.text.trim();
      widget.program['mentorEvaluationBy'] = mentorName;
      widget.program['weeklyTarget'] = _targetController.text.trim();
      widget.program['priorityTasks'] = _priorityTasks;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Değişiklikler başarıyla kaydedildi.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydedilemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _rolloverProgram() async {
    final List<String> uncompleted = [];
    final schedule = widget.program['schedule'] as Map<String, dynamic>;

    _executionStatus.forEach((day, list) {
      final lessons = schedule[day] as List?;
      if (lessons != null) {
        for (int i = 0; i < list.length; i++) {
          if (i < lessons.length && (list[i] == 2 || list[i] == 3)) {
            uncompleted.add(lessons[i].toString().replaceAll('\n', ' '));
          }
        }
      }
    });

    if (uncompleted.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu haftaya ait eksik veya yapılamayan görev bulunamadı.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Gelecek Haftaya Aktar'),
        content: Text(
          'Yapılamayan/eksik ${uncompleted.length} adet görev, bir sonraki haftanın programına (Pazartesi gününe) aktarılarak yeni bir program oluşturulacak. Emin misiniz?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Aktar ve Oluştur'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      await _guidanceService.rolloverUncompletedTasks(
        widget.institutionId,
        widget.program,
        uncompleted,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Program başarıyla bir sonraki haftaya aktarıldı.')),
        );
        Navigator.pop(context); // Close detail screen
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Aktarım başarısız oldu: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _addNewTask(String day) {
    final textController = TextEditingController();
    bool isPriority = false;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('$day Gününe Görev Ekle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: textController,
              decoration: const InputDecoration(
                labelText: 'Yeni Görev Tanımı',
                hintText: 'Örn: Matematik 50 Soru',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            StatefulBuilder(
              builder: (ctx, setDialogState) => CheckboxListTile(
                title: const Text('🚨 Öncelikli Görev', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                value: isPriority,
                activeColor: Colors.red,
                onChanged: (val) {
                  setDialogState(() {
                    isPriority = val ?? false;
                  });
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () {
              if (textController.text.trim().isEmpty) return;
              setState(() {
                final schedule = widget.program['schedule'] as Map<String, dynamic>;
                final lessons = List<String>.from(schedule[day] ?? []);
                lessons.add(textController.text.trim());
                schedule[day] = lessons;
                _executionStatus[day]!.add(0);

                final int newIdx = lessons.length - 1;
                if (isPriority) {
                  _priorityTasks["${day}_$newIdx"] = true;
                }
              });
              _saveFullProgram();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  void _showTaskManagementSheet(String day, int index, String lessonText, int currentStatus) {
    final textController = TextEditingController(text: lessonText);
    bool isPriority = _priorityTasks["${day}_$index"] == true;
    int selectedStatus = currentStatus;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Görevi Düzenle ($day)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: textController,
                    decoration: const InputDecoration(
                      labelText: 'Görev Tanımı',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('🚨 Öncelikli Görev (LGS / Sınav Hedefi)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                    value: isPriority,
                    activeColor: Colors.red,
                    onChanged: (val) {
                      setSheetState(() {
                        isPriority = val ?? false;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Görev Durumu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatusSelectButton(setSheetState, 'Atandı', 0, Colors.grey, selectedStatus, (val) => selectedStatus = val),
                      _buildStatusSelectButton(setSheetState, 'Yapıldı', 1, Colors.green, selectedStatus, (val) => selectedStatus = val),
                      _buildStatusSelectButton(setSheetState, 'Eksik', 2, Colors.orange, selectedStatus, (val) => selectedStatus = val),
                      _buildStatusSelectButton(setSheetState, 'Yapılmadı', 3, Colors.red, selectedStatus, (val) => selectedStatus = val),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            final schedule = widget.program['schedule'] as Map<String, dynamic>;
                            final lessons = List<String>.from(schedule[day]);
                            lessons.removeAt(index);
                            schedule[day] = lessons;
                            _executionStatus[day]!.removeAt(index);

                            final newPriorities = <String, dynamic>{};
                            _priorityTasks.forEach((k, v) {
                              if (k.startsWith('${day}_')) {
                                final idx = int.parse(k.split('_')[1]);
                                if (idx > index) {
                                  newPriorities['${day}_${idx - 1}'] = v;
                                } else if (idx < index) {
                                  newPriorities[k] = v;
                                }
                              } else {
                                newPriorities[k] = v;
                              }
                            });
                            _priorityTasks = newPriorities;
                          });
                          _saveFullProgram();
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.delete, color: Colors.red),
                        label: const Text('Sil', style: TextStyle(color: Colors.red)),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('İptal'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                            onPressed: () {
                              setState(() {
                                final schedule = widget.program['schedule'] as Map<String, dynamic>;
                                final lessons = List<String>.from(schedule[day]);
                                lessons[index] = textController.text.trim();
                                schedule[day] = lessons;
                                _executionStatus[day]![index] = selectedStatus;
                                if (isPriority) {
                                  _priorityTasks["${day}_$index"] = true;
                                } else {
                                  _priorityTasks.remove("${day}_$index");
                                }
                              });
                              _saveFullProgram();
                              Navigator.pop(ctx);
                            },
                            child: const Text('Kaydet', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusSelectButton(
    StateSetter setSheetState,
    String label,
    int value,
    Color color,
    int currentSelected,
    ValueChanged<int> onSelected,
  ) {
    final isSelected = currentSelected == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSelected ? Colors.white : color, fontWeight: FontWeight.bold, fontSize: 11)),
      selected: isSelected,
      selectedColor: color,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withOpacity(0.5)),
      ),
      onSelected: (val) {
        if (val) {
          setSheetState(() {
            onSelected(value);
          });
        }
      },
    );
  }

  Color _getStatusColor(int status) {
    switch (status) {
      case 1:
        return Colors.green.shade50;
      case 2:
        return Colors.orange.shade50;
      case 3:
        return Colors.red.shade50;
      default:
        return Colors.white;
    }
  }

  Color _getStatusBorderColor(int status) {
    switch (status) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.red;
      default:
        return Colors.grey.shade300;
    }
  }

  IconData? _getStatusIcon(int status) {
    switch (status) {
      case 1:
        return Icons.check_circle;
      case 2:
        return Icons.warning_rounded;
      case 3:
        return Icons.cancel;
      default:
        return null;
    }
  }

  Map<String, int> _calculateStats() {
    int total = 0;
    int done = 0;
    int incomplete = 0;
    int missed = 0;

    _executionStatus.values.forEach((list) {
      total += list.length;
      done += list.where((s) => s == 1).length;
      incomplete += list.where((s) => s == 2).length;
      missed += list.where((s) => s == 3).length;
    });

    return {
      'total': total,
      'done': done,
      'incomplete': incomplete,
      'missed': missed,
      'percentage': total > 0
          ? ((done + (incomplete * 0.5)) / total * 100).round()
          : 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final schedule = widget.program['schedule'] as Map<String, dynamic>;
    final stats = _calculateStats();
    final studentName = widget.program['studentName'] ?? 'Öğrenci';
    final examName = widget.program['examName'] ?? 'Program';

    final days = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(studentName),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: () {
              StudyProgramPrintingHelper.generateBulkPdf(context, [
                widget.program,
              ]);
            },
          ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.indigo,
                  strokeWidth: 2,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Header Stats Summary
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.indigo.shade50,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        examName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text("Program Takip Özeti"),
                      if (widget.program['startDate'] != null ||
                          widget.program['createdAt'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            _formatDateRange(widget.program),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.indigo.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _buildStatBadge("Tamamlanan", stats['done']!, Colors.green),
                const SizedBox(width: 8),
                _buildStatBadge("Eksik", stats['incomplete']!, Colors.orange),
                const SizedBox(width: 8),
                _buildStatBadge("Yapılmadı", stats['missed']!, Colors.red),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.indigo,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "%${stats['percentage']}",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Weekly Target Input Card
                  _buildTargetCard(),
                  const SizedBox(height: 20),

                  // 2. Days Tasks Lists
                  ...days.map((day) {
                    if (!schedule.containsKey(day)) return const SizedBox.shrink();
                    final lessons = List<String>.from(schedule[day] ?? []);
                    return _buildDayCard(day, lessons);
                  }).toList(),

                  // 3. Weekly Mentor Evaluation Input Card
                  _buildEvaluationCard(),
                  const SizedBox(height: 24),

                  // 4. Next-Week Rollover Action Button
                  _buildRolloverActionBtn(),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.track_changes, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                const Text(
                  '🎯 Haftalık Hedef Belirle',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _targetController,
              decoration: const InputDecoration(
                hintText: 'Örn: Fen Bilimleri netini 15 üzerine çıkarmak ve paragraf çözmek',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              maxLines: 1,
              onChanged: (_) => _saveFullProgram(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEvaluationCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.rate_review_rounded, color: Colors.indigo.shade800),
                const SizedBox(width: 8),
                const Text(
                  '💬 Haftalık Mentör Değerlendirmesi',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _evaluationController,
              decoration: const InputDecoration(
                hintText: 'Bu hafta öğrenci hedeflerine nasıl yaklaştı? Eksik kalan çalışmalar neler?',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              maxLines: 4,
              onChanged: (_) => _saveFullProgram(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRolloverActionBtn() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _rolloverProgram,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange.shade800,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
        ),
        icon: const Icon(Icons.arrow_forward_rounded),
        label: const Text(
          'Eksik Görevleri Sonraki Haftaya Aktar',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildDayCard(String day, List<String> lessons) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Text(
                day,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.indigo),
              tooltip: 'Yeni Görev Ekle',
              onPressed: () => _addNewTask(day),
            ),
          ],
        ),
        if (lessons.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text('Planlanan çalışma bulunmuyor.', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 350,
              childAspectRatio: 2.2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: lessons.length,
            itemBuilder: (context, lessonIndex) {
              final lesson = lessons[lessonIndex];
              final status = _executionStatus[day]?[lessonIndex] ?? 0;
              final color = _getStatusColor(status);
              final borderColor = _getStatusBorderColor(status);
              final icon = _getStatusIcon(status);

              final bool isPriority = _priorityTasks["${day}_$lessonIndex"] == true;

              return InkWell(
                onTap: () => _showTaskManagementSheet(day, lessonIndex, lesson, status),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isPriority ? Colors.red.shade50.withOpacity(0.3) : color,
                    border: Border.all(
                      color: isPriority ? Colors.red.shade300 : borderColor,
                      width: isPriority ? 1.8 : 1.5,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isPriority) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '🚨 ÖNCELİKLİ GÖREV',
                            style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Row(
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 18, color: isPriority ? Colors.red.shade700 : borderColor),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              lesson.replaceAll('\n', ' '),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isPriority ? FontWeight.bold : FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 8),
        const Divider(),
      ],
    );
  }

  Widget _buildStatBadge(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  String _formatDateRange(Map<String, dynamic> data) {
    DateTime? parse(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final start = parse(data['startDate']) ?? parse(data['createdAt']);
    final end = parse(data['endDate']);
    String fmt(DateTime d) => "${d.day}.${d.month}.${d.year}";

    if (start != null) {
      return "${fmt(start)} ${end != null ? '- ' + fmt(end) : ''}";
    }
    return "";
  }
}
