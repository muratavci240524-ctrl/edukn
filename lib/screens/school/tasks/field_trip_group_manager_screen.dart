import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../models/field_trip_model.dart';
import '../../../../services/field_trip_service.dart';
import '../../../../services/pdf_service.dart'; // Added
import 'package:printing/printing.dart'; // Added

class FieldTripGroupManagerScreen extends StatefulWidget {
  final FieldTrip trip;

  const FieldTripGroupManagerScreen({Key? key, required this.trip})
    : super(key: key);

  @override
  State<FieldTripGroupManagerScreen> createState() =>
      _FieldTripGroupManagerScreenState();
}

class _FieldTripGroupManagerScreenState
    extends State<FieldTripGroupManagerScreen> {
  late FieldTrip _trip;
  final FieldTripService _service = FieldTripService();
  final PdfService _pdfService = PdfService(); // Added

  List<Map<String, dynamic>> _participatingStudents = [];
  List<Map<String, dynamic>> _teachers = [];
  bool _isLoading = true;

  // Group editing state
  String? _editingGroupId; // If null, creating new. If set, editing this ID.
  List<String> _selectedTeacherIds = [];
  List<String> _selectedStudentIdsForGroup = [];
  bool _isCreatingOrEditing = false;

  final _groupNameController = TextEditingController();
  final _vehiclePlateController = TextEditingController();
  final _driverPhoneController = TextEditingController();

  String _studentSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _loadData();
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _vehiclePlateController.dispose();
    _driverPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Load Teachers
      final staffSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: _trip.institutionId)
          .where('role', isEqualTo: 'ogretmen')
          .get();

      _teachers = staffSnapshot.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'name': data['fullName'] ?? '${data['name']} ${data['surname']}',
        };
      }).toList();
      _teachers.sort(
        (a, b) => (a['name'] as String).compareTo(b['name'] as String),
      );

      // 2. Load Students & Determine Participation
      List<Map<String, dynamic>> allStudents = [];
      final ids = _trip.targetStudentIds;

      for (var i = 0; i < ids.length; i += 10) {
        final chunk = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
        if (chunk.isEmpty) continue;
        final snapshot = await FirebaseFirestore.instance
            .collection('students')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (var doc in snapshot.docs) {
          allStudents.add({'id': doc.id, ...doc.data()});
        }
      }

      // 3. Filter Participating Students (Manual Override > Survey > Pending)
      Map<String, dynamic> surveyResponses = {};
      if (_trip.participationSurveyId != null) {
        final sSnap = await FirebaseFirestore.instance
            .collection('survey_responses')
            .where('surveyId', isEqualTo: _trip.participationSurveyId)
            .get();
        for (var doc in sSnap.docs) {
          final data = doc.data();
          if (data['userId'] != null) surveyResponses[data['userId']] = data;
        }
      }

      List<Map<String, dynamic>> confirmed = [];

      for (var s in allStudents) {
        final sid = s['id'];

        if (_trip.manualParticipationStatus.containsKey(sid)) {
          final manual = _trip.manualParticipationStatus[sid];
          if (manual == 'participating') confirmed.add(s);
        } else {
          if (surveyResponses.containsKey(sid)) {
            final answers =
                surveyResponses[sid]['answers'] as Map<String, dynamic>? ?? {};
            bool yes = false;
            for (var v in answers.values) {
              if (v.toString().toLowerCase().contains('evet') ||
                  v.toString().toLowerCase().contains('katılıyorum'))
                yes = true;
            }
            if (yes) confirmed.add(s);
          }
        }
      }

      confirmed.sort(
        (a, b) => (a['fullName'] ?? '').compareTo(b['fullName'] ?? ''),
      );

      if (mounted) {
        setState(() {
          _participatingStudents = confirmed;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _printGroups() async {
    try {
      // Create a map of Student ID -> Name for printing
      // Create a map of Student ID -> Detailed Info for printing
      Map<String, Map<String, dynamic>> studentDetails = {};
      for (var s in _participatingStudents) {
        String parentName = '-';
        String parentPhone = '-';

        // Extract parent info (prefer 'Veli' or just the first parent)
        final parents = s['parents'] as List<dynamic>? ?? [];
        if (parents.isNotEmpty) {
          // Try to find a Veli (relation) or just take first
          var p = parents.first;
          // If it's a map
          if (p is Map) {
            parentName = p['name'] ?? '-';
            parentPhone = p['phone'] ?? '-';
          }
        }

        studentDetails[s['id']] = {
          'fullName': s['fullName'] ?? 'Bilinmeyen',
          'className': s['className'] ?? '',
          'phone': s['phone'] ?? '',
          'parentName': parentName,
          'parentPhone': parentPhone,
        };
      }

      final pdfBytes = await _pdfService.generateFieldTripGroupsPdf(
        trip: _trip,
        studentDetails: studentDetails,
      );

      await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
        name: 'gezi_gruplari.pdf',
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF oluşturma hatası: $e')));
    }
  }

  void _startEditing(FieldTripGroup group) {
    setState(() {
      _isCreatingOrEditing = true;
      _editingGroupId = group.id;
      _groupNameController.text = group.name;
      _vehiclePlateController.text = group.vehiclePlate ?? '';
      _driverPhoneController.text = group.driverPhone ?? '';
      _selectedTeacherIds = List.from(group.teacherIds);
      _selectedStudentIdsForGroup = List.from(group.studentIds);
      _studentSearchQuery = '';
    });
  }

  void _startCreating() {
    setState(() {
      _isCreatingOrEditing = true;
      _editingGroupId = null;
      _groupNameController.clear();
      _vehiclePlateController.clear();
      _driverPhoneController.clear();
      _selectedTeacherIds = [];
      _selectedStudentIdsForGroup = [];
      _studentSearchQuery = '';
    });
  }

  void _cancelEditing() {
    setState(() {
      _isCreatingOrEditing = false;
      _editingGroupId = null;
      _groupNameController.clear();
      _vehiclePlateController.clear();
      _driverPhoneController.clear();
      _selectedTeacherIds = [];
      _selectedStudentIdsForGroup = [];
      _studentSearchQuery = '';
    });
  }

  Future<void> _saveGroup() async {
    if (_groupNameController.text.isEmpty ||
        _selectedTeacherIds.isEmpty ||
        _selectedStudentIdsForGroup.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lütfen zorunlu alanları doldurunuz (Grup Adı, Öğretmenler, Öğrenciler)',
          ),
        ),
      );
      return;
    }

    // Construct names list based on IDs
    List<String> selectedNames = [];
    for (var id in _selectedTeacherIds) {
      final t = _teachers.firstWhere(
        (element) => element['id'] == id,
        orElse: () => {'name': ''},
      );
      selectedNames.add(t['name']);
    }

    final newGroup = FieldTripGroup(
      id: _editingGroupId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _groupNameController.text,
      teacherIds: List.from(_selectedTeacherIds),
      teacherNames: selectedNames,
      studentIds: List.from(_selectedStudentIdsForGroup),
      vehiclePlate: _vehiclePlateController.text.isNotEmpty
          ? _vehiclePlateController.text
          : null,
      driverPhone: _driverPhoneController.text.isNotEmpty
          ? _driverPhoneController.text
          : null,
    );

    List<FieldTripGroup> updatedGroups;
    if (_editingGroupId != null) {
      // Update existing
      updatedGroups = _trip.groups.map((g) {
        return g.id == _editingGroupId ? newGroup : g;
      }).toList();
    } else {
      // Add new
      updatedGroups = List<FieldTripGroup>.from(_trip.groups)..add(newGroup);
    }

    final updatedTrip = FieldTrip(
      id: _trip.id,
      institutionId: _trip.institutionId,
      schoolTypeId: _trip.schoolTypeId,
      schoolTypeName: _trip.schoolTypeName,
      name: _trip.name,
      purpose: _trip.purpose,
      departureTime: _trip.departureTime,
      returnTime: _trip.returnTime,
      classLevel: _trip.classLevel,
      targetBranchIds: _trip.targetBranchIds,
      targetStudentIds: _trip.targetStudentIds,
      totalStudents: _trip.totalStudents,
      participationSurveyId: _trip.participationSurveyId,
      surveyPublishDate: _trip.surveyPublishDate,
      manualParticipationStatus: _trip.manualParticipationStatus,
      isPaid: _trip.isPaid,
      amount: _trip.amount,
      paymentStatus: _trip.paymentStatus,
      feedbackSurveyId: _trip.feedbackSurveyId,
      authorId: _trip.authorId,
      createdAt: _trip.createdAt,
      status: _trip.status,
      groups: updatedGroups,
    );

    try {
      await _service.updateFieldTrip(updatedTrip);
      setState(() {
        _trip = updatedTrip;
        _cancelEditing();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _editingGroupId != null ? 'Grup güncellendi' : 'Grup oluşturuldu',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _deleteGroup(FieldTripGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Grubu Sil'),
        content: Text(
          '${group.name} grubunu silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final updatedGroups = _trip.groups.where((g) => g.id != group.id).toList();
    final updatedTrip = FieldTrip(
      id: _trip.id,
      institutionId: _trip.institutionId,
      schoolTypeId: _trip.schoolTypeId,
      schoolTypeName: _trip.schoolTypeName,
      name: _trip.name,
      purpose: _trip.purpose,
      departureTime: _trip.departureTime,
      returnTime: _trip.returnTime,
      classLevel: _trip.classLevel,
      targetBranchIds: _trip.targetBranchIds,
      targetStudentIds: _trip.targetStudentIds,
      totalStudents: _trip.totalStudents,
      participationSurveyId: _trip.participationSurveyId,
      surveyPublishDate: _trip.surveyPublishDate,
      manualParticipationStatus: _trip.manualParticipationStatus,
      isPaid: _trip.isPaid,
      amount: _trip.amount,
      paymentStatus: _trip.paymentStatus,
      feedbackSurveyId: _trip.feedbackSurveyId,
      authorId: _trip.authorId,
      createdAt: _trip.createdAt,
      status: _trip.status,
      groups: updatedGroups,
    );
    try {
      await _service.updateFieldTrip(updatedTrip);
      setState(() {
        _trip = updatedTrip;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Grup silindi')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Filter Logic for Available Students
    // 1. Find all students currently assigned to ANY group
    // 2. EXCEPT the group currently being edited (if any)

    final otherGroups = _editingGroupId == null
        ? _trip.groups
        : _trip.groups.where((g) => g.id != _editingGroupId);

    final assignedInOtherGroups = otherGroups
        .expand((g) => g.studentIds)
        .toSet();

    final availableStudents = _participatingStudents.where((s) {
      return !assignedInOtherGroups.contains(s['id']);
    }).toList();

    // Filter by search query
    final filteredAvailable = availableStudents.where((s) {
      final name = (s['fullName'] ?? '').toString().toLowerCase();
      return name.contains(_studentSearchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Grup Yönetimi',
          style: TextStyle(color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _printGroups,
            tooltip: 'Listeyi Yazdır',
          ),
        ],
      ),
      body: Row(
        children: [
          // Left: Group Creation & List
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey[50],
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Gruplar',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (!_isCreatingOrEditing)
                        ElevatedButton.icon(
                          onPressed: _startCreating,
                          icon: const Icon(Icons.add),
                          label: const Text('Yeni Grup'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (_isCreatingOrEditing)
                    Expanded(child: _buildGroupForm(filteredAvailable))
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: _trip.groups.length,
                        separatorBuilder: (c, i) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final group = _trip.groups[index];
                          // Safely handle teacher names
                          final tNames = group.teacherNames.isNotEmpty
                              ? group.teacherNames.join(", ")
                              : "Öğretmen Yok";

                          return Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.indigo.shade50,
                                child: const Icon(
                                  Icons.groups,
                                  color: Colors.indigo,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      group.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit,
                                      size: 20,
                                      color: Colors.blue,
                                    ),
                                    onPressed: () => _startEditing(group),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      size: 20,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _deleteGroup(group),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$tNames • ${group.studentIds.length} Öğrenci',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (group.vehiclePlate != null ||
                                      group.driverPhone != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text(
                                        '${group.vehiclePlate ?? ''} ${group.driverPhone != null ? '• ${group.driverPhone}' : ''}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              // Removing default trailing to use custom Row in title for actions
                              trailing: const SizedBox.shrink(),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: group.studentIds.map((sid) {
                                      final s = _participatingStudents
                                          .firstWhere(
                                            (ps) => ps['id'] == sid,
                                            orElse: () => {
                                              'fullName': 'Bilinmeyen',
                                            },
                                          );
                                      return Chip(
                                        avatar: CircleAvatar(
                                          child: Text(s['fullName'][0]),
                                        ),
                                        label: Text(s['fullName']),
                                        backgroundColor: Colors.indigo.shade50,
                                        labelStyle: TextStyle(
                                          color: Colors.indigo.shade900,
                                          fontSize: 11,
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Right: Unassigned List (Reference) for large screens
          if (MediaQuery.of(context).size.width > 900)
            Expanded(
              flex: 1,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: Colors.grey.shade300)),
                  color: Colors.white,
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Gruplanmamış Öğrenciler (${availableStudents.length - _selectedStudentIdsForGroup.length})', // Roughly correct for viewing purposes
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: availableStudents.length,
                        itemBuilder: (c, i) {
                          final s = availableStudents[i];
                          // Don't show students that are tentatively selected in the current form
                          if (_isCreatingOrEditing &&
                              _selectedStudentIdsForGroup.contains(s['id'])) {
                            return const SizedBox.shrink();
                          }

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.grey.shade200,
                              foregroundColor: Colors.grey.shade700,
                              child: Text(s['fullName'][0]),
                            ),
                            title: Text(s['fullName']),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupForm(List<Map<String, dynamic>> availableFiltered) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.shade100),
        boxShadow: [
          BoxShadow(color: Colors.indigo.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note, color: Colors.indigo),
              const SizedBox(width: 8),
              Text(
                _editingGroupId != null ? 'Grubu Düzenle' : 'Yeni Grup Oluştur',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _groupNameController,
                  decoration: InputDecoration(
                    labelText: 'Grup Adı *',
                    hintText: 'Örn: 1. Otobüs',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _vehiclePlateController,
                  decoration: InputDecoration(
                    labelText: 'Araç Plaka',
                    hintText: '34 AB 123',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _driverPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Şoför Tel',
                    hintText: '05...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Sorumlu Öğretmenler *',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: InkWell(
              onTap: () async {
                final selected = await showDialog<List<String>>(
                  context: context,
                  builder: (context) {
                    List<String> tempSelected = List.from(_selectedTeacherIds);
                    return StatefulBuilder(
                      builder: (context, setStateSB) {
                        return AlertDialog(
                          title: const Text('Öğretmen Seç'),
                          content: SizedBox(
                            width: double.maxFinite,
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _teachers.length,
                              itemBuilder: (context, index) {
                                final t = _teachers[index];
                                final tid = t['id'] as String;
                                final isSel = tempSelected.contains(tid);
                                return CheckboxListTile(
                                  title: Text(t['name']),
                                  value: isSel,
                                  onChanged: (val) {
                                    setStateSB(() {
                                      if (val == true) {
                                        tempSelected.add(tid);
                                      } else {
                                        tempSelected.remove(tid);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, null),
                              child: const Text('İptal'),
                            ),
                            ElevatedButton(
                              onPressed: () =>
                                  Navigator.pop(context, tempSelected),
                              child: const Text('Tamam'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );

                if (selected != null) {
                  setState(() {
                    _selectedTeacherIds = selected;
                  });
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _selectedTeacherIds.isEmpty
                          ? const Text(
                              'Öğretmen Seçiniz...',
                              style: TextStyle(color: Colors.grey),
                            )
                          : Text(
                              _teachers
                                  .where(
                                    (t) =>
                                        _selectedTeacherIds.contains(t['id']),
                                  )
                                  .map((t) => t['name'])
                                  .join(', '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.black87),
                            ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Öğrenciler *',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          // Student Selector with Search
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Listede Ara...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        setState(() {
                          _studentSearchQuery = val;
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: availableFiltered.isEmpty
                        ? const Center(
                            child: Text('Gruplanacak öğrenci bulunamadı'),
                          )
                        : ListView.builder(
                            itemCount: availableFiltered.length,
                            itemBuilder: (context, index) {
                              final s = availableFiltered[index];
                              final isSelected = _selectedStudentIdsForGroup
                                  .contains(s['id']);
                              return CheckboxListTile(
                                title: Text(s['fullName']),
                                value: isSelected,
                                dense: true,
                                activeColor: Colors.indigo,
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true)
                                      _selectedStudentIdsForGroup.add(s['id']);
                                    else
                                      _selectedStudentIdsForGroup.remove(
                                        s['id'],
                                      );
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: _cancelEditing, child: const Text('İptal')),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _saveGroup,
                icon: const Icon(Icons.save),
                label: Text(
                  _editingGroupId != null
                      ? 'Değişiklikleri Kaydet'
                      : 'Grubu Kaydet',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
