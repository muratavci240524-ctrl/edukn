import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/guidance/development_report/development_report_session_model.dart';
import '../../../services/development_report_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/guidance/development_report/development_criterion_model.dart';
import 'development_report_session_detail_screen.dart';
import 'development_report_export_dialogs.dart';

class DevelopmentReportManagementScreen extends StatefulWidget {
  final String institutionId;

  const DevelopmentReportManagementScreen({
    Key? key,
    required this.institutionId,
  }) : super(key: key);

  @override
  _DevelopmentReportManagementScreenState createState() =>
      _DevelopmentReportManagementScreenState();
}

class _DevelopmentReportManagementScreenState
    extends State<DevelopmentReportManagementScreen> {
  final DevelopmentReportService _service = DevelopmentReportService();

  // Simple student picker would be needed here.
  // For now, let's list latest reports and have a "Create New" FAB that asks for student ID (mock).

  String _formatTargetGroup(String group) {
    switch (group) {
      case 'student':
        return 'Öğrenci';
      case 'teacher':
        return 'Öğretmen';
      case 'personel':
      case 'personnel':
        return 'Personel';
      default:
        return group;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Gelişim Raporu Yönetimi"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: StreamBuilder<List<DevelopmentReportSession>>(
        stream: _service.getSessions(widget.institutionId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return Center(child: CircularProgressIndicator());

          final sessions = snapshot.data ?? [];
          if (sessions.isEmpty)
            return Center(child: Text("Rapor oturumu bulunamadı."));

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 900),
              child: ListView.builder(
                padding: EdgeInsets.all(16),
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                DevelopmentReportSessionDetailScreen(
                                  session: session,
                                  institutionId: widget.institutionId,
                                ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        session.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          _buildBadge(
                                            text: _formatTargetGroup(
                                              session.targetGroup,
                                            ),
                                            color: Colors.indigo,
                                          ),
                                          const SizedBox(width: 8),
                                          _buildBadge(
                                            text: session.isPublished
                                                ? "YAYINDA"
                                                : "TASLAK",
                                            color: session.isPublished
                                                ? Colors.green
                                                : Colors.orange,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                _buildSessionMenu(session),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    _buildStatItem(
                                      icon: Icons.person_outline_rounded,
                                      label: "Hedef",
                                      value: "${session.targetUserIds.length}",
                                      color: Colors.blue,
                                    ),
                                    const SizedBox(width: 16),
                                    _buildStatItem(
                                      icon: Icons.edit_note_rounded,
                                      label: "Değ.",
                                      value:
                                          "${session.assignedReviewerIds.length}",
                                      color: Colors.purple,
                                    ),
                                    const SizedBox(width: 16),
                                    _buildStatItem(
                                      icon: Icons.calendar_today_rounded,
                                      label: "Tarih",
                                      value: DateFormat(
                                        'dd.MM.yyyy',
                                      ).format(session.createdAt),
                                      color: Colors.grey,
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.file_download_outlined,
                                        size: 20,
                                      ),
                                      onPressed: () =>
                                          _showExportDialog(context, session),
                                      color: Colors.indigo,
                                      tooltip: "Rapor Al",
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(8),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        session.isPublished
                                            ? Icons.visibility_off_outlined
                                            : Icons.publish_rounded,
                                        size: 20,
                                      ),
                                      onPressed: () => _togglePublish(session),
                                      color: session.isPublished
                                          ? Colors.orange
                                          : Colors.green,
                                      tooltip: session.isPublished
                                          ? "Yayından Kaldır"
                                          : "Yayınla",
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(8),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: "create",
        child: const Icon(Icons.add),
        tooltip: "Yeni Rapor Oluştur",
        onPressed: () {
          _showCreateDialog();
        },
      ),
    );
  }

  Future<void> _togglePublish(DevelopmentReportSession session) async {
    try {
      final newStatus = !session.isPublished;
      await _service.updateSessionPublishStatus(session.id, newStatus);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus
                ? "Rapor başarıyla yayınlandı."
                : "Rapor yayından kaldırıldı.",
          ),
          backgroundColor: newStatus ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Bir hata oluştu: $e")));
    }
  }

  Widget _buildBadge({required String text, required Color color}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF334155),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionMenu(DevelopmentReportSession session) {
    return PopupMenuButton<String>(
      onSelected: (val) async {
        if (val == 'edit') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Düzenleme yakında eklenecek.")),
          );
        } else if (val == 'recalculate') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Analizler güncelleniyor, lütfen bekleyin..."),
            ),
          );
          try {
            await _service.recalculateSessionAnalysis(session.id);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Analizler başarıyla güncellendi."),
                backgroundColor: Colors.green,
              ),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Hata oluştu: $e"),
                backgroundColor: Colors.red,
              ),
            );
          }
        } else if (val == 'delete') {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text("Oturumu Sil"),
              content: Text("Bu oturumu silmek istediğinize emin misiniz?"),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text("İptal"),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text("Sil", style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
          if (confirm == true) {
            await _service.deleteSession(session.id);
          }
        }
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 20, color: Colors.blue),
              SizedBox(width: 12),
              Text("Düzenle", style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'recalculate',
          child: Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: 20, color: Colors.purple),
              SizedBox(width: 12),
              Text("Analizleri Yenile", style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red),
              SizedBox(width: 12),
              Text("Sil", style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.more_horiz, color: Colors.grey.shade600),
      ),
    );
  }

  void _showExportDialog(
    BuildContext context,
    DevelopmentReportSession session,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Rapor Al", style: TextStyle(color: Colors.indigo)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Lütfen almak istediğiniz rapor türünü seçin:"),
              SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  showDevelopmentReportIndividualExport(context, session);
                },
                icon: Icon(Icons.person),
                label: Text("Bireysel Rapor"),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 48),
                  backgroundColor: Colors.indigo.shade50,
                  foregroundColor: Colors.indigo.shade800,
                  elevation: 0,
                ),
              ),
              SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  showDevelopmentReportBulkExport(context, session);
                },
                icon: Icon(Icons.group),
                label: Text("Toplu Rapor"),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 48),
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("İptal"),
            ),
          ],
        );
      },
    );
  }

  void _showCreateDialog() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    if (isMobile) {
      Navigator.push(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => _CreateReportDialog(
            institutionId: widget.institutionId,
            service: _service,
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => _CreateReportDialog(
          institutionId: widget.institutionId,
          service: _service,
        ),
      );
    }
  }
}

class _CreateReportDialog extends StatefulWidget {
  final String institutionId;
  final DevelopmentReportService service;

  const _CreateReportDialog({
    Key? key,
    required this.institutionId,
    required this.service,
  }) : super(key: key);

  @override
  __CreateReportDialogState createState() => __CreateReportDialogState();
}

class __CreateReportDialogState extends State<_CreateReportDialog> {
  final _titleController = TextEditingController(
    text: "2024-2025 Güz - Gelişim Raporu",
  );

  String _targetGroup = 'student'; // 'student', 'teacher', 'personnel'

  // Student Filters
  List<Map<String, dynamic>> _classes = [];
  List<int> _grades = [];
  List<Map<String, dynamic>> _branches = [];
  List<int> _selectedGrades = [];
  List<String> _selectedClassIds = [];

  // Data
  List<Map<String, dynamic>> _targetUsers = [];
  List<String> _selectedTargetUserIds = [];

  List<Map<String, dynamic>> _availableReviewers = [];
  List<String> _selectedReviewerIds = [];

  bool _isLoadingFilters = false;
  bool _isLoadingTargets = false;
  bool _isLoadingReviewers = true;
  bool _isCreating = false;
  int _currentStep = 0;
  List<DevelopmentCriterion> _sessionCriteria = [];
  bool _isLoadingCriteria = false;

  final _criteriaService = DevelopmentReportService();

  @override
  void initState() {
    super.initState();
    _loadReviewers();
    _loadFiltersForTargetGroup();
  }

  Future<void> _loadReviewers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      final users = snapshot.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList();
      setState(() {
        _availableReviewers = users.where((u) {
          final r = u['role']?.toString().toLowerCase() ?? '';
          return [
            'ogretmen',
            'teacher',
            'mudur',
            'mudur_yardimcisi',
            'rehberlik',
            'personel',
          ].contains(r);
        }).toList();
        _availableReviewers.sort(
          (a, b) => (a['fullName'] ?? '').compareTo(b['fullName'] ?? ''),
        );
        _isLoadingReviewers = false;
      });
    } catch (e) {
      print("Error loading reviewers: $e");
      setState(() => _isLoadingReviewers = false);
    }
  }

  Future<void> _loadFiltersForTargetGroup() async {
    setState(() {
      _isLoadingFilters = true;
      _targetUsers = [];
      _selectedTargetUserIds = [];
      _selectedGrades = [];
      _selectedClassIds = [];
    });

    try {
      if (_targetGroup == 'student') {
        final snapshot = await FirebaseFirestore.instance
            .collection('classes')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('isActive', isEqualTo: true)
            .get();

        final classes = snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList();
        final grades =
            classes
                .map((c) => c['classLevel'] as int?)
                .where((l) => l != null)
                .map((l) => l!)
                .toSet()
                .toList()
              ..sort();

        setState(() {
          _classes = classes;
          _grades = grades;
          _isLoadingFilters = false;
        });
      } else {
        await _loadTargetUsersForNonStudents();
        setState(() => _isLoadingFilters = false);
      }
    } catch (e) {
      print("Error loading filters: $e");
      setState(() => _isLoadingFilters = false);
    }
  }

  Future<void> _loadTargetUsersForNonStudents() async {
    setState(() => _isLoadingTargets = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      final users = snapshot.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList();

      setState(() {
        if (_targetGroup == 'teacher') {
          _targetUsers = users.where((u) {
            final r = u['role']?.toString().toLowerCase() ?? '';
            return ['ogretmen', 'teacher'].contains(r);
          }).toList();
        } else if (_targetGroup == 'personnel') {
          _targetUsers = users.where((u) {
            final r = u['role']?.toString().toLowerCase() ?? '';
            return ![
              'ogretmen',
              'teacher',
              'ogrenci',
              'student',
              'veli',
              'parent',
            ].contains(r);
          }).toList();
        }
        _targetUsers.sort(
          (a, b) => (a['fullName'] ?? '').compareTo(b['fullName'] ?? ''),
        );
        _selectedTargetUserIds = [];
        _isLoadingTargets = false;
      });
    } catch (e) {
      print("Error target users: $e");
      setState(() => _isLoadingTargets = false);
    }
  }

  void _onGradesSelected(List<int> grades) {
    setState(() {
      _selectedGrades = grades;
      _selectedClassIds = [];
      _selectedTargetUserIds = [];
      _targetUsers = [];

      if (grades.isNotEmpty) {
        _branches =
            _classes
                .where((c) => grades.contains(c['classLevel'] as int))
                .toList()
              ..sort(
                (a, b) =>
                    (a['className'] ?? '').compareTo(b['className'] ?? ''),
              );
      } else {
        _branches = [];
      }
    });
  }

  Future<void> _onClassesSelected(List<String> classIds) async {
    setState(() {
      _selectedClassIds = classIds;
      _selectedTargetUserIds = [];
      _targetUsers = [];
    });

    if (classIds.isEmpty) return;

    setState(() => _isLoadingTargets = true);

    try {
      // firestore whereIn handles up to 10
      List<Map<String, dynamic>> allStudents = [];
      for (var i = 0; i < classIds.length; i += 10) {
        final chunk = classIds.sublist(
          i,
          i + 10 > classIds.length ? classIds.length : i + 10,
        );
        final snapshot = await FirebaseFirestore.instance
            .collection('students')
            .where('classId', whereIn: chunk)
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('isActive', isEqualTo: true)
            .get();

        allStudents.addAll(
          snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}),
        );
      }

      allStudents.sort(
        (a, b) => (a['fullName'] ?? '').compareTo(b['fullName'] ?? ''),
      );

      setState(() {
        _targetUsers = allStudents;
        _isLoadingTargets = false;
      });
    } catch (e) {
      print("Error loading students: $e");
      setState(() => _isLoadingTargets = false);
    }
  }

  void _openMultiSelectParams(
    String title,
    List<Map<String, dynamic>> items,
    List<String> selectedIds,
    Function(List<String>) onSaved, {
    String Function(Map<String, dynamic>)? groupBy,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        List<String> tempSelected = List.from(selectedIds);

        // Ensure proper grouping and sorting if groupBy is provided
        Map<String, List<Map<String, dynamic>>> groupedItems = {};
        if (groupBy != null) {
          for (var item in items) {
            final groupKey = groupBy(item);
            if (!groupedItems.containsKey(groupKey)) {
              groupedItems[groupKey] = [];
            }
            groupedItems[groupKey]!.add(item);
          }
        } else {
          groupedItems['Tümü'] = items;
        }

        final groupKeys = groupedItems.keys.toList()..sort();

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isAllSelected =
                tempSelected.length == items.length && items.isNotEmpty;
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: Colors.white,
              child: Container(
                width: 450,
                height: MediaQuery.of(context).size.height * 0.7,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 20,
                        right: 8,
                        top: 16,
                        bottom: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Text(
                            "${tempSelected.length} seçildi",
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Spacer(),
                          TextButton.icon(
                            icon: Icon(
                              isAllSelected ? Icons.deselect : Icons.select_all,
                              size: 18,
                            ),
                            label: Text(
                              isAllSelected ? "Tümünü Kaldır" : "Tümünü Seç",
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.indigo,
                            ),
                            onPressed: () {
                              setDialogState(() {
                                if (isAllSelected) {
                                  tempSelected.clear();
                                } else {
                                  tempSelected = items
                                      .map((e) => e['id'] as String)
                                      .toList();
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: groupKeys.length,
                        itemBuilder: (context, index) {
                          final group = groupKeys[index];
                          final groupItems = groupedItems[group]!;
                          final isGroupAllSelected = groupItems.every(
                            (e) => tempSelected.contains(e['id']),
                          );
                          final isGroupPartiallySelected =
                              !isGroupAllSelected &&
                              groupItems.any(
                                (e) => tempSelected.contains(e['id']),
                              );

                          Widget groupHeader = SizedBox.shrink();
                          if (groupBy != null) {
                            groupHeader = Container(
                              color: Colors.grey.shade100,
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      group,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo.shade900,
                                      ),
                                    ),
                                  ),
                                  Checkbox(
                                    value: isGroupAllSelected
                                        ? true
                                        : (isGroupPartiallySelected
                                              ? null
                                              : false),
                                    tristate: true,
                                    activeColor: Colors.indigo,
                                    onChanged: (val) {
                                      setDialogState(() {
                                        if (val == true || val == null) {
                                          for (var i in groupItems) {
                                            if (!tempSelected.contains(i['id']))
                                              tempSelected.add(
                                                i['id'] as String,
                                              );
                                          }
                                        } else {
                                          for (var i in groupItems) {
                                            tempSelected.remove(i['id']);
                                          }
                                        }
                                      });
                                    },
                                  ),
                                ],
                              ),
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              groupHeader,
                              ...groupItems.map((item) {
                                final isSelected = tempSelected.contains(
                                  item['id'],
                                );
                                return CheckboxListTile(
                                  activeColor: Colors.indigo,
                                  title: Text(
                                    item['fullName'] ??
                                        item['className'] ??
                                        item['name'] ??
                                        'İsimsiz',
                                    style: TextStyle(
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  value: isSelected,
                                  onChanged: (val) {
                                    setDialogState(() {
                                      if (val == true) {
                                        tempSelected.add(item['id']);
                                      } else {
                                        tempSelected.remove(item['id']);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ],
                          );
                        },
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              "İptal",
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ),
                          SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              onSaved(tempSelected);
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text("Seçimi Onayla"),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _loadSampleCriteria() async {
    setState(() => _isLoadingCriteria = true);
    try {
      final criteria = await _criteriaService
          .getCriteria(widget.institutionId)
          .first;
      setState(() {
        _sessionCriteria = List.from(criteria);
      });
    } catch (e) {
      print("Error loading sample criteria: $e");
    } finally {
      setState(() => _isLoadingCriteria = false);
    }
  }

  Future<void> _createSession() async {
    if (_currentStep == 0) {
      if (_titleController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Lütfen bir başlık girin.")),
        );
        return;
      }

      List<String> finalTargets = List.from(_selectedTargetUserIds);
      if (finalTargets.isEmpty) {
        if (_targetGroup == 'student' && _selectedClassIds.isEmpty) {
          if (_targetUsers.isNotEmpty)
            finalTargets = _targetUsers.map((e) => e['id'] as String).toList();
        } else {
          finalTargets = _targetUsers.map((e) => e['id'] as String).toList();
        }
      }

      if (finalTargets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Hedef kitlede seçili kişi yok.")),
        );
        return;
      }

      if (_selectedReviewerIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Değerlendirici seçilmedi.")),
        );
        return;
      }
      setState(() => _currentStep = 1);
      return;
    }

    if (_sessionCriteria.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("En az bir kriter eklemelisiniz.")),
      );
      return;
    }

    setState(() => _isCreating = true);
    try {
      List<String> finalTargets = List.from(_selectedTargetUserIds);
      if (finalTargets.isEmpty) {
        if (_targetGroup == 'student' && _selectedClassIds.isEmpty) {
          if (_targetUsers.isNotEmpty)
            finalTargets = _targetUsers.map((e) => e['id'] as String).toList();
        } else {
          finalTargets = _targetUsers.map((e) => e['id'] as String).toList();
        }
      }

      final session = DevelopmentReportSession(
        id: '',
        institutionId: widget.institutionId,
        title: _titleController.text.trim(),
        targetGroup: _targetGroup,
        schoolYear: "2024-2025",
        assignedReviewerIds: _selectedReviewerIds,
        targetUserIds: finalTargets,
        isPublished: false,
        createdAt: DateTime.now(),
      );

      await widget.service.createSession(session);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Rapor oturumu başarıyla oluşturuldu.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Hata oluştu: $e")));
        setState(() => _isCreating = false);
      }
    }
  }

  Widget _buildSelectionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.indigo.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.indigo.shade700, size: 22),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: Colors.indigo.shade700, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleController,
          decoration: InputDecoration(
            labelText: "Rapor Başlığı",
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          "Hedef Kitle Tipi:",
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'student', label: Text('Öğrenci')),
              ButtonSegment(value: 'teacher', label: Text('Öğretmen')),
              ButtonSegment(value: 'personnel', label: Text('Personel')),
            ],
            selected: {_targetGroup},
            onSelectionChanged: (val) {
              setState(() {
                _targetGroup = val.first;
              });
              _loadFiltersForTargetGroup();
            },
          ),
        ),
        const SizedBox(height: 24),
        if (_isLoadingFilters)
          const Center(child: CircularProgressIndicator())
        else if (_targetGroup == 'student') ...[
          _buildSelectionButton(
            label: _selectedGrades.isEmpty
                ? "Sınıf Seviyesi Seç (Opsiyonel)"
                : "${_selectedGrades.length} Sınıf Seviyesi Seçildi",
            icon: Icons.layers,
            onTap: () {
              final items = _grades
                  .map((g) => {'id': g.toString(), 'name': '$g. Sınıf'})
                  .toList();
              _openMultiSelectParams(
                "Sınıf Seviyesi Seç",
                items,
                _selectedGrades.map((g) => g.toString()).toList(),
                (selected) {
                  _onGradesSelected(selected.map((s) => int.parse(s)).toList());
                },
              );
            },
          ),
          const SizedBox(height: 16),
          _buildSelectionButton(
            label: _selectedClassIds.isEmpty
                ? "Şube Seç (Opsiyonel)"
                : "${_selectedClassIds.length} Şube Seçildi",
            icon: Icons.class_,
            onTap: () {
              if (_selectedGrades.isEmpty) return;
              _openMultiSelectParams("Şube Seç", _branches, _selectedClassIds, (
                selected,
              ) {
                _onClassesSelected(selected);
              });
            },
          ),
          const SizedBox(height: 16),
        ] else ...[
          Text(
            "Seçilebilir ${_targetGroup == 'teacher' ? 'Öğretmen' : 'Personel'} sayısı: ${_targetUsers.length}",
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
        ],
        if (_isLoadingTargets)
          const Center(child: CircularProgressIndicator())
        else if (_targetUsers.isNotEmpty) ...[
          _buildSelectionButton(
            label: _selectedTargetUserIds.length == _targetUsers.length
                ? "Tümü Seçili (Veya Düzenle)"
                : _selectedTargetUserIds.isEmpty
                ? "Tümünü Seç (Veya Düzenle)"
                : "${_selectedTargetUserIds.length} Kişi Seçildi (Düzenle)",
            icon: Icons.people,
            onTap: () {
              List<String> passedIds = _selectedTargetUserIds.isEmpty
                  ? _targetUsers.map((e) => e['id'] as String).toList()
                  : _selectedTargetUserIds;
              _openMultiSelectParams(
                "Kişileri Seç",
                _targetUsers,
                passedIds,
                (selected) {
                  setState(() => _selectedTargetUserIds = selected);
                },
                groupBy:
                    _targetGroup == 'teacher' || _targetGroup == 'personnel'
                    ? (item) {
                        final b =
                            item['branchName'] ??
                            item['branch'] ??
                            item['title'] ??
                            item['role'] ??
                            'Diğer';
                        return b.toString().toUpperCase();
                      }
                    : null,
              );
            },
          ),
          const SizedBox(height: 24),
        ],
        Divider(color: Colors.grey.shade300),
        const SizedBox(height: 16),
        const Text(
          "Değerlendiriciler:",
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 8),
        if (_isLoadingReviewers)
          const Center(child: CircularProgressIndicator())
        else
          _buildSelectionButton(
            label: _selectedReviewerIds.isEmpty
                ? "Değerlendirici Seçilmedi"
                : "${_selectedReviewerIds.length} Değerlendirici Seçildi",
            icon: Icons.assignment_ind,
            onTap: () {
              _openMultiSelectParams(
                "Değerlendirici Seç",
                _availableReviewers,
                _selectedReviewerIds,
                (selected) {
                  setState(() => _selectedReviewerIds = selected);
                },
                groupBy: (item) {
                  final b =
                      item['branchName'] ??
                      item['branch'] ??
                      item['title'] ??
                      item['role'] ??
                      'Diğer';
                  return b.toString().toUpperCase();
                },
              );
            },
          ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Rapor Kriterleri",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (_sessionCriteria.isEmpty)
              TextButton.icon(
                onPressed: _isLoadingCriteria ? null : _loadSampleCriteria,
                icon: _isLoadingCriteria
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: const Text("Örnekleri Getir"),
                style: TextButton.styleFrom(foregroundColor: Colors.orange),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_sessionCriteria.isEmpty && !_isLoadingCriteria)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(
                    Icons.list_alt_rounded,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Henüz kriter eklenmedi.\nÖrnek kriterleri yükleyebilir veya yeni ekleyebilirsiniz.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _sessionCriteria.length,
            itemBuilder: (context, index) {
              final crit = _sessionCriteria[index];
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  dense: true,
                  title: Text(
                    crit.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    crit.category,
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _sessionCriteria.removeAt(index);
                      });
                    },
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _addCustomCriterion,
          icon: const Icon(Icons.add),
          label: const Text("Yeni Kriter Ekle"),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 45),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  void _addCustomCriterion() {
    String title = "";
    String category = "Akademik Gelişim";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Yeni Kriter Ekle"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: "Kriter Başlığı",
                hintText: "Örn: Kitap Okuma Alışkanlığı",
              ),
              onChanged: (val) => title = val,
              autofocus: true,
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: category,
              decoration: const InputDecoration(labelText: "Kategori"),
              items: const [
                DropdownMenuItem(
                  value: "Akademik Gelişim",
                  child: Text("Akademik Gelişim"),
                ),
                DropdownMenuItem(
                  value: "Sosyal Gelişim",
                  child: Text("Sosyal Gelişim"),
                ),
                DropdownMenuItem(
                  value: "Davranış ve Sorumluluk",
                  child: Text("Davranış ve Sorumluluk"),
                ),
              ],
              onChanged: (val) => category = val!,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("İptal"),
          ),
          ElevatedButton(
            onPressed: () {
              if (title.trim().isEmpty) return;
              setState(() {
                _sessionCriteria.add(
                  DevelopmentCriterion(
                    id: "custom_${DateTime.now().millisecondsSinceEpoch}",
                    institutionId: widget.institutionId,
                    category: category,
                    subCategory: "Genel",
                    title: title.trim(),
                    description: "",
                    targetGradeLevels: _selectedGrades
                        .map((e) => e.toString())
                        .toList(),
                    type: "scale_1_5",
                    order: _sessionCriteria.length + 1,
                  ),
                );
              });
              Navigator.pop(context);
            },
            child: const Text("Ekle"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    Widget wizardContent = _currentStep == 0 ? _buildStep1() : _buildStep2();

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _currentStep == 0
                ? "Yeni Rapor (Adım 1/2)"
                : "Kriterler (Adım 2/2)",
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.indigo,
          elevation: 0,
          leading: IconButton(
            icon: Icon(_currentStep == 0 ? Icons.close : Icons.arrow_back),
            onPressed: () {
              if (_currentStep == 0) {
                Navigator.pop(context);
              } else {
                setState(() => _currentStep = 0);
              }
            },
          ),
        ),
        backgroundColor: Colors.grey.shade50,
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: wizardContent,
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    if (_currentStep == 1)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() => _currentStep = 0),
                          child: const Text("Geri"),
                        ),
                      ),
                    if (_currentStep == 1) const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _isCreating ? null : _createSession,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _currentStep == 0
                              ? "İleri"
                              : (_isCreating ? "Oluşturuluyor..." : "Oluştur"),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: 550,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currentStep == 0
                    ? "Yeni Rapor Oturumu"
                    : "Rapor Kriterlerini Belirle",
                style: TextStyle(
                  fontSize: 22,
                  color: Colors.indigo.shade900,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              Flexible(child: SingleChildScrollView(child: wizardContent)),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      if (_currentStep == 0) {
                        Navigator.pop(context);
                      } else {
                        setState(() => _currentStep = 0);
                      }
                    },
                    child: Text(_currentStep == 0 ? "İptal" : "Geri"),
                  ),
                  ElevatedButton(
                    onPressed: _isCreating ? null : _createSession,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _currentStep == 0
                          ? "Devam Et"
                          : (_isCreating
                                ? "Oluşturuluyor..."
                                : "Tamamla ve Oluştur"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
  }
} // end of class
