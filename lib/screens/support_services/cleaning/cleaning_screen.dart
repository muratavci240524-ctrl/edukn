import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class CleaningScreen extends StatefulWidget {
  final String? fixedSchoolTypeId;
  final String? fixedSchoolTypeName;

  const CleaningScreen({
    Key? key,
    this.fixedSchoolTypeId,
    this.fixedSchoolTypeName,
  }) : super(key: key);

  @override
  State<CleaningScreen> createState() => _CleaningScreenState();
}

class _CleaningScreenState extends State<CleaningScreen>
    with SingleTickerProviderStateMixin {
  String? _institutionId;
  String? _schoolDocId;
  bool _isLoading = true;
  late TabController _tabController;

  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _areas = [];
  List<Map<String, dynamic>> _leaves = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final email = user.email!;
      _institutionId = email.split('@')[1].split('.')[0].toUpperCase();

      final snap = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', isEqualTo: _institutionId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        _schoolDocId = snap.docs.first.id;
      }

      await Future.wait([_loadStaff(), _loadAreas(), _loadLeaves()]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStaff() async {
    if (_schoolDocId == null) return;
    Query query = FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('cleaningStaff');

    if (widget.fixedSchoolTypeId != null) {
      query = query.where('schoolTypeId', isEqualTo: widget.fixedSchoolTypeId);
    }

    final snap = await query.orderBy('name').get();
    setState(() {
      _staff = snap.docs.map<Map<String, dynamic>>((d) {
        final data = d.data() as Map<String, dynamic>?;
        return {'id': d.id, if (data != null) ...data};
      }).toList();
    });
  }

  Future<void> _loadAreas() async {
    if (_schoolDocId == null) return;
    Query query = FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('cleaningAreas');

    if (widget.fixedSchoolTypeId != null) {
      query = query.where('schoolTypeId', isEqualTo: widget.fixedSchoolTypeId);
    }

    final snap = await query.orderBy('name').get();
    setState(() {
      _areas = snap.docs.map<Map<String, dynamic>>((d) {
        final data = d.data() as Map<String, dynamic>?;
        return {'id': d.id, if (data != null) ...data};
      }).toList();
    });
  }

  Future<void> _loadLeaves() async {
    if (_schoolDocId == null) return;
    Query query = FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('cleaningLeaves');

    if (widget.fixedSchoolTypeId != null) {
      query = query.where('schoolTypeId', isEqualTo: widget.fixedSchoolTypeId);
    }

    final snap = await query.orderBy('startDate', descending: true).get();
    setState(() {
      _leaves = snap.docs.map<Map<String, dynamic>>((d) {
        final data = d.data() as Map<String, dynamic>?;
        return {'id': d.id, if (data != null) ...data};
      }).toList();
    });
  }

  // ─── Staff CRUD ───

  Future<void> _addStaff() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.person_add, color: Colors.green),
            SizedBox(width: 8),
            Text('Personel Ekle'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Ad Soyad *',
                prefixIcon: Icon(Icons.person),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              decoration: InputDecoration(
                labelText: 'Telefon',
                prefixIcon: Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('Ekle'),
          ),
        ],
      ),
    );

    if (result != true || nameCtrl.text.trim().isEmpty) return;

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('cleaningStaff')
        .add({
          'name': nameCtrl.text.trim(),
          'phone': phoneCtrl.text.trim(),
          'assignedAreaId': null,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
          if (widget.fixedSchoolTypeId != null)
            'schoolTypeId': widget.fixedSchoolTypeId,
        });

    await _loadStaff();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Personel eklendi'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _deleteStaff(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Personel Sil'),
        content: Text('Bu personeli silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('cleaningStaff')
        .doc(id)
        .delete();
    await _loadStaff();
  }

  // ─── Area CRUD ───

  Future<void> _addArea() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.location_on, color: Colors.green),
            SizedBox(width: 8),
            Text('Çalışma Alanı Ekle'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Alan Adı *',
                prefixIcon: Icon(Icons.place),
                hintText: 'Örn: 1. Kat Koridoru',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: InputDecoration(
                labelText: 'Açıklama',
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('Ekle'),
          ),
        ],
      ),
    );

    if (result != true || nameCtrl.text.trim().isEmpty) return;

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('cleaningAreas')
        .add({
          'name': nameCtrl.text.trim(),
          'description': descCtrl.text.trim(),
          'assignedStaffId': null,
          'assignedStaffName': null,
          'createdAt': FieldValue.serverTimestamp(),
          if (widget.fixedSchoolTypeId != null)
            'schoolTypeId': widget.fixedSchoolTypeId,
        });

    await _loadAreas();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Alan eklendi'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _assignStaffToArea(Map<String, dynamic> area) async {
    final selectedStaffId = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${area['name']} Alanına Personel Ata'),
        children: [
          // Option to unassign
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, '__none__'),
            child: Row(
              children: [
                Icon(Icons.close, color: Colors.grey),
                SizedBox(width: 12),
                Text('Atama Kaldır', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          Divider(),
          ..._staff.map(
            (s) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s['id']),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.green.shade100,
                    child: Text(
                      s['name'][0],
                      style: TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(s['name']),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (selectedStaffId == null) return;

    final staffName = selectedStaffId == '__none__'
        ? null
        : _staff.firstWhere((s) => s['id'] == selectedStaffId)['name'];

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('cleaningAreas')
        .doc(area['id'])
        .update({
          'assignedStaffId': selectedStaffId == '__none__'
              ? null
              : selectedStaffId,
          'assignedStaffName': staffName,
        });

    // Also update staff record
    if (selectedStaffId != '__none__') {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolDocId)
          .collection('cleaningStaff')
          .doc(selectedStaffId)
          .update({'assignedAreaId': area['id']});
    }

    await Future.wait([_loadStaff(), _loadAreas()]);
  }

  Future<void> _deleteArea(String id) async {
    await FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('cleaningAreas')
        .doc(id)
        .delete();
    await _loadAreas();
  }

  // ─── Leave Management ───

  Future<void> _addLeave() async {
    String? selectedStaffId;
    String? substituteStaffId;
    final startDateCtrl = TextEditingController();
    final endDateCtrl = TextEditingController();
    DateTime? startDate;
    DateTime? endDate;
    String leaveType = 'daily';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.event_busy, color: Colors.orange),
              SizedBox(width: 8),
              Text('İzin Kaydı'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Staff selector
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'Personel *',
                    prefixIcon: Icon(Icons.person),
                  ),
                  items: _staff
                      .map(
                        (s) => DropdownMenuItem(
                          value: s['id'] as String,
                          child: Text(s['name']),
                        ),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => selectedStaffId = val),
                ),
                SizedBox(height: 12),
                // Leave type
                DropdownButtonFormField<String>(
                  value: leaveType,
                  decoration: InputDecoration(
                    labelText: 'İzin Türü',
                    prefixIcon: Icon(Icons.schedule),
                  ),
                  items: [
                    DropdownMenuItem(value: 'hourly', child: Text('Saatlik')),
                    DropdownMenuItem(value: 'daily', child: Text('Günlük')),
                    DropdownMenuItem(value: 'weekly', child: Text('Haftalık')),
                  ],
                  onChanged: (val) =>
                      setDialogState(() => leaveType = val ?? 'daily'),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: startDateCtrl,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Başlangıç *',
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                      locale: Locale('tr', 'TR'),
                    );
                    if (date != null) {
                      startDate = date;
                      startDateCtrl.text = DateFormat(
                        'dd.MM.yyyy',
                      ).format(date);
                      setDialogState(() {});
                    }
                  },
                ),
                SizedBox(height: 12),
                TextField(
                  controller: endDateCtrl,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Bitiş',
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: startDate ?? DateTime.now(),
                      firstDate: startDate ?? DateTime(2020),
                      lastDate: DateTime(2030),
                      locale: Locale('tr', 'TR'),
                    );
                    if (date != null) {
                      endDate = date;
                      endDateCtrl.text = DateFormat('dd.MM.yyyy').format(date);
                      setDialogState(() {});
                    }
                  },
                ),
                SizedBox(height: 12),
                // Substitute
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'Yerine Görevlendirilen',
                    prefixIcon: Icon(Icons.swap_horiz),
                  ),
                  items: _staff
                      .where((s) => s['id'] != selectedStaffId)
                      .map(
                        (s) => DropdownMenuItem(
                          value: s['id'] as String,
                          child: Text(s['name']),
                        ),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => substituteStaffId = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: Text('Kaydet'),
            ),
          ],
        ),
      ),
    );

    if (result != true || selectedStaffId == null || startDate == null) {
      if (result == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Personel ve başlangıç tarihi zorunludur!'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final staffName = _staff.firstWhere(
      (s) => s['id'] == selectedStaffId,
    )['name'];
    final substituteName = substituteStaffId != null
        ? _staff.firstWhere((s) => s['id'] == substituteStaffId)['name']
        : null;

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('cleaningLeaves')
        .add({
          'staffId': selectedStaffId,
          'staffName': staffName,
          'leaveType': leaveType,
          'startDate': Timestamp.fromDate(startDate!),
          'endDate': endDate != null
              ? Timestamp.fromDate(endDate!)
              : Timestamp.fromDate(startDate!),
          'substituteStaffId': substituteStaffId,
          'substituteStaffName': substituteName,
          'createdAt': FieldValue.serverTimestamp(),
        });

    await _loadLeaves();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ İzin kaydedildi'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _deleteLeave(String id) async {
    await FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('cleaningLeaves')
        .doc(id)
        .delete();
    await _loadLeaves();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Temizlik İşlemleri')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Temizlik İşlemleri'),
        elevation: 1,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.green,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.green,
          isScrollable: true,
          tabs: [
            Tab(icon: Icon(Icons.people), text: 'Personel'),
            Tab(icon: Icon(Icons.location_on), text: 'Alanlar'),
            Tab(icon: Icon(Icons.event_busy), text: 'İzinler'),
            Tab(icon: Icon(Icons.bar_chart), text: 'İstatistik'),
          ],
        ),
      ),
      floatingActionButton: _buildFab(),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStaffTab(),
          _buildAreasTab(),
          _buildLeavesTab(),
          _buildStatisticsTab(),
        ],
      ),
    );
  }

  Widget? _buildFab() {
    switch (_tabController.index) {
      case 0:
        return FloatingActionButton.extended(
          onPressed: _addStaff,
          icon: Icon(Icons.person_add),
          label: Text('Personel Ekle'),
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
        );
      case 1:
        return FloatingActionButton.extended(
          onPressed: _addArea,
          icon: Icon(Icons.add_location_alt),
          label: Text('Alan Ekle'),
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
        );
      case 2:
        return FloatingActionButton.extended(
          onPressed: _addLeave,
          icon: Icon(Icons.event_busy),
          label: Text('İzin Ekle'),
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
        );
      default:
        return null;
    }
  }

  Widget _buildStaffTab() {
    if (_staff.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
            SizedBox(height: 16),
            Text(
              'Henüz personel eklenmemiş',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: 900),
        child: ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: _staff.length,
          itemBuilder: (context, index) {
            final staff = _staff[index];
            final areaName = _getAssignedAreaName(staff['assignedAreaId']);

            return Card(
              margin: EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: Text(
                    staff['name'] != null && staff['name'].isNotEmpty
                        ? staff['name'][0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  staff['name'] ?? '',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (staff['phone'] != null &&
                        (staff['phone'] as String).isNotEmpty)
                      Text(
                        '📞 ${staff['phone']}',
                        style: TextStyle(fontSize: 12),
                      ),
                    Text(
                      areaName != null ? '📍 $areaName' : '📍 Alan atanmamış',
                      style: TextStyle(
                        fontSize: 12,
                        color: areaName != null ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade300),
                  onPressed: () => _deleteStaff(staff['id']),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String? _getAssignedAreaName(String? areaId) {
    if (areaId == null) return null;
    try {
      return _areas.firstWhere((a) => a['id'] == areaId)['name'];
    } catch (_) {
      return null;
    }
  }

  Widget _buildAreasTab() {
    if (_areas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_off, size: 64, color: Colors.grey.shade400),
            SizedBox(height: 16),
            Text(
              'Henüz çalışma alanı tanımlanmamış',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: 900),
        child: ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: _areas.length,
          itemBuilder: (context, index) {
            final area = _areas[index];
            final hasStaff = area['assignedStaffName'] != null;

            return Card(
              margin: EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: hasStaff
                      ? Colors.green.shade100
                      : Colors.grey.shade200,
                  child: Icon(
                    Icons.location_on,
                    color: hasStaff ? Colors.green : Colors.grey,
                  ),
                ),
                title: Text(
                  area['name'] ?? '',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (area['description'] != null &&
                        (area['description'] as String).isNotEmpty)
                      Text(area['description'], style: TextStyle(fontSize: 12)),
                    Text(
                      hasStaff
                          ? '👤 ${area['assignedStaffName']}'
                          : '👤 Atanmamış',
                      style: TextStyle(
                        fontSize: 12,
                        color: hasStaff ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.person_add, color: Colors.green),
                      tooltip: 'Personel Ata',
                      onPressed: () => _assignStaffToArea(area),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: Colors.red.shade300,
                      ),
                      onPressed: () => _deleteArea(area['id']),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLeavesTab() {
    if (_leaves.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_available, size: 64, color: Colors.grey.shade400),
            SizedBox(height: 16),
            Text(
              'Henüz izin kaydı yok',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: 900),
        child: ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: _leaves.length,
          itemBuilder: (context, index) {
            final leave = _leaves[index];
            final startDate = (leave['startDate'] as Timestamp?)?.toDate();
            final endDate = (leave['endDate'] as Timestamp?)?.toDate();
            final startStr = startDate != null
                ? DateFormat('dd.MM.yyyy').format(startDate)
                : '-';
            final endStr = endDate != null
                ? DateFormat('dd.MM.yyyy').format(endDate)
                : '-';

            String typeLabel;
            Color typeColor;
            switch (leave['leaveType']) {
              case 'hourly':
                typeLabel = 'Saatlik';
                typeColor = Colors.blue;
                break;
              case 'weekly':
                typeLabel = 'Haftalık';
                typeColor = Colors.red;
                break;
              default:
                typeLabel = 'Günlük';
                typeColor = Colors.orange;
            }

            return Card(
              margin: EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: typeColor.withOpacity(0.1),
                          child: Icon(
                            Icons.event_busy,
                            color: typeColor,
                            size: 18,
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                leave['staffName'] ?? '',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '$startStr - $endStr',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Chip(
                          label: Text(
                            typeLabel,
                            style: TextStyle(fontSize: 11, color: typeColor),
                          ),
                          backgroundColor: typeColor.withOpacity(0.1),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: Colors.red.shade300,
                            size: 20,
                          ),
                          onPressed: () => _deleteLeave(leave['id']),
                        ),
                      ],
                    ),
                    if (leave['substituteStaffName'] != null)
                      Padding(
                        padding: EdgeInsets.only(top: 6, left: 42),
                        child: Row(
                          children: [
                            Icon(
                              Icons.swap_horiz,
                              size: 16,
                              color: Colors.green,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Yerine: ${leave['substituteStaffName']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatisticsTab() {
    final totalStaff = _staff.length;
    final assignedStaff = _staff
        .where((s) => s['assignedAreaId'] != null)
        .length;
    final totalAreas = _areas.length;
    final assignedAreas = _areas
        .where((a) => a['assignedStaffId'] != null)
        .length;
    final totalLeaves = _leaves.length;

    // Leave type breakdown
    final hourlyLeaves = _leaves
        .where((l) => l['leaveType'] == 'hourly')
        .length;
    final dailyLeaves = _leaves.where((l) => l['leaveType'] == 'daily').length;
    final weeklyLeaves = _leaves
        .where((l) => l['leaveType'] == 'weekly')
        .length;

    // Staff with most leaves
    final leaveMap = <String, int>{};
    for (final l in _leaves) {
      final name = l['staffName'] as String? ?? 'Bilinmeyen';
      leaveMap[name] = (leaveMap[name] ?? 0) + 1;
    }
    final sortedLeaveStaff = leaveMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary cards
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildStatCard(
                    'Toplam Personel',
                    '$totalStaff',
                    Icons.people,
                    Colors.green,
                  ),
                  _buildStatCard(
                    'Görevli',
                    '$assignedStaff',
                    Icons.check_circle,
                    Colors.blue,
                  ),
                  _buildStatCard(
                    'Toplam Alan',
                    '$totalAreas',
                    Icons.location_on,
                    Colors.teal,
                  ),
                  _buildStatCard(
                    'Atanmış Alan',
                    '$assignedAreas',
                    Icons.done_all,
                    Colors.indigo,
                  ),
                ],
              ),
              SizedBox(height: 24),
              Text(
                'İzin Dağılımı',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildStatRow('Toplam İzin', '$totalLeaves', Colors.grey),
                      Divider(),
                      _buildStatRow('Saatlik', '$hourlyLeaves', Colors.blue),
                      _buildStatRow('Günlük', '$dailyLeaves', Colors.orange),
                      _buildStatRow('Haftalık', '$weeklyLeaves', Colors.red),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 24),
              if (sortedLeaveStaff.isNotEmpty) ...[
                Text(
                  'En Çok İzin Alan',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                ...sortedLeaveStaff
                    .take(10)
                    .map(
                      (e) => ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.orange.shade100,
                          child: Text(
                            e.key[0],
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                        title: Text(e.key),
                        trailing: Chip(
                          label: Text('${e.value} izin'),
                          backgroundColor: Colors.orange.shade50,
                        ),
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700)),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return SizedBox(
      width: 160,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 28, color: color),
              SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
