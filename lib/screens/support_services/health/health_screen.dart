import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class HealthScreen extends StatefulWidget {
  final String? fixedSchoolTypeId;
  final String? fixedSchoolTypeName;

  const HealthScreen({
    Key? key,
    this.fixedSchoolTypeId,
    this.fixedSchoolTypeName,
  }) : super(key: key);

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen>
    with SingleTickerProviderStateMixin {
  String? _institutionId;
  String? _schoolDocId;
  bool _isLoading = true;
  late TabController _tabController;

  List<Map<String, dynamic>> _visits = [];
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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

      await _loadVisits();
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

  Future<void> _loadVisits() async {
    if (_schoolDocId == null) return;

    final startOfDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final endOfDay = startOfDay.add(Duration(days: 1));

    var query = FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('healthVisits')
        .where(
          'visitDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where('visitDate', isLessThan: Timestamp.fromDate(endOfDay));

    if (widget.fixedSchoolTypeId != null) {
      query = query.where('schoolTypeId', isEqualTo: widget.fixedSchoolTypeId);
    }

    final snap = await query.orderBy('visitDate', descending: true).get();

    setState(() {
      _visits = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    });
  }

  Future<void> _addVisit() async {
    final studentNameCtrl = TextEditingController();
    final complaintCtrl = TextEditingController();
    final treatmentCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool medicationGiven = false;
    String? medicationName;
    final medicationCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.local_hospital, color: Colors.red),
              SizedBox(width: 8),
              Text('Yeni Revir Ziyareti'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: studentNameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Öğrenci Adı Soyadı *',
                    prefixIcon: Icon(Icons.person),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                SizedBox(height: 12),
                TextField(
                  controller: complaintCtrl,
                  decoration: InputDecoration(
                    labelText: 'Şikayeti *',
                    prefixIcon: Icon(Icons.sick),
                    hintText: 'Örn: Baş ağrısı, karın ağrısı',
                  ),
                  maxLines: 2,
                ),
                SizedBox(height: 12),
                TextField(
                  controller: treatmentCtrl,
                  decoration: InputDecoration(
                    labelText: 'Yapılan Müdahale',
                    prefixIcon: Icon(Icons.medical_services),
                    hintText: 'Örn: Ateş ölçümü, pansuman',
                  ),
                  maxLines: 2,
                ),
                SizedBox(height: 12),
                SwitchListTile(
                  title: Text('İlaç Verildi mi?'),
                  value: medicationGiven,
                  activeColor: Colors.red,
                  onChanged: (val) {
                    setDialogState(() => medicationGiven = val);
                  },
                ),
                if (medicationGiven) ...[
                  SizedBox(height: 8),
                  TextField(
                    controller: medicationCtrl,
                    decoration: InputDecoration(
                      labelText: 'Verilen İlaç',
                      prefixIcon: Icon(Icons.medication),
                      hintText: 'Örn: Parol 500mg',
                    ),
                  ),
                ],
                SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: InputDecoration(
                    labelText: 'Notlar',
                    prefixIcon: Icon(Icons.note),
                  ),
                  maxLines: 2,
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
              onPressed: () {
                medicationName = medicationCtrl.text.trim();
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text('Kaydet'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    if (studentNameCtrl.text.trim().isEmpty ||
        complaintCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Öğrenci adı ve şikayet zorunludur!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('healthVisits')
        .add({
          'studentName': studentNameCtrl.text.trim(),
          'complaint': complaintCtrl.text.trim(),
          'treatment': treatmentCtrl.text.trim(),
          'medicationGiven': medicationGiven,
          'medicationName': medicationGiven ? (medicationName ?? '') : '',
          'notes': notesCtrl.text.trim(),
          'visitDate': Timestamp.fromDate(DateTime.now()),
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': FirebaseAuth.instance.currentUser?.email ?? '',
          if (widget.fixedSchoolTypeId != null)
            'schoolTypeId': widget.fixedSchoolTypeId,
        });

    await _loadVisits();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Ziyaret kaydedildi'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _deleteVisit(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ziyaret Sil'),
        content: Text('Bu ziyaret kaydını silmek istediğinize emin misiniz?'),
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
        .collection('healthVisits')
        .doc(id)
        .delete();

    await _loadVisits();
  }

  Future<void> _changeDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: Locale('tr', 'TR'),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
      await _loadVisits();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Sağlık İşlemleri')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Sağlık İşlemleri'),
        elevation: 1,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.red,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.red,
          tabs: [
            Tab(icon: Icon(Icons.local_hospital), text: 'Revir Ziyaretleri'),
            Tab(icon: Icon(Icons.bar_chart), text: 'İstatistikler'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addVisit,
        icon: Icon(Icons.add),
        label: Text('Ziyaret Ekle'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildVisitsList(), _buildStatistics()],
      ),
    );
  }

  Widget _buildVisitsList() {
    final dateStr = DateFormat('dd MMMM yyyy', 'tr_TR').format(_selectedDate);

    return Column(
      children: [
        // Date selector
        Container(
          color: Colors.red.shade50,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.chevron_left),
                onPressed: () {
                  setState(
                    () => _selectedDate = _selectedDate.subtract(
                      Duration(days: 1),
                    ),
                  );
                  _loadVisits();
                },
              ),
              Expanded(
                child: InkWell(
                  onTap: _changeDate,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text(
                          dateStr,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.red.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right),
                onPressed: () {
                  setState(
                    () => _selectedDate = _selectedDate.add(Duration(days: 1)),
                  );
                  _loadVisits();
                },
              ),
            ],
          ),
        ),
        // Visit count
        Container(
          padding: EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            children: [
              Icon(Icons.people, color: Colors.red),
              SizedBox(width: 8),
              Text(
                'Bugün ${_visits.length} ziyaret',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Divider(height: 1),
        // Visit list
        Expanded(
          child: _visits.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.health_and_safety,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Bu tarihte ziyaret kaydı yok',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : Center(
                  child: Container(
                    constraints: BoxConstraints(maxWidth: 900),
                    child: ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: _visits.length,
                      itemBuilder: (context, index) {
                        final visit = _visits[index];
                        final time = (visit['visitDate'] as Timestamp?)
                            ?.toDate();
                        final timeStr = time != null
                            ? DateFormat('HH:mm').format(time)
                            : '';

                        return Card(
                          margin: EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: Colors.red.shade100,
                                      child: Icon(
                                        Icons.person,
                                        color: Colors.red,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            visit['studentName'] ?? '',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                          Text(
                                            timeStr,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_outline,
                                        color: Colors.red.shade300,
                                      ),
                                      onPressed: () =>
                                          _deleteVisit(visit['id']),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 12),
                                _buildInfoRow(
                                  Icons.sick,
                                  'Şikayet',
                                  visit['complaint'] ?? '-',
                                ),
                                if (visit['treatment'] != null &&
                                    (visit['treatment'] as String).isNotEmpty)
                                  _buildInfoRow(
                                    Icons.medical_services,
                                    'Müdahale',
                                    visit['treatment'],
                                  ),
                                if (visit['medicationGiven'] == true)
                                  _buildInfoRow(
                                    Icons.medication,
                                    'İlaç',
                                    visit['medicationName']?.isNotEmpty == true
                                        ? visit['medicationName']
                                        : 'Verildi',
                                    color: Colors.orange,
                                  ),
                                if (visit['notes'] != null &&
                                    (visit['notes'] as String).isNotEmpty)
                                  _buildInfoRow(
                                    Icons.note,
                                    'Not',
                                    visit['notes'],
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    Color? color,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color ?? Colors.grey),
          SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color ?? Colors.grey.shade700,
            ),
          ),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildStatistics() {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolDocId)
          .collection('healthVisits')
          .orderBy('visitDate', descending: true)
          .limit(500)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        final totalVisits = docs.length;
        final medicationCount = docs
            .where((d) => d['medicationGiven'] == true)
            .length;

        // Group by complaint
        final complaintMap = <String, int>{};
        for (final doc in docs) {
          final complaint = doc['complaint'] as String? ?? 'Diğer';
          complaintMap[complaint] = (complaintMap[complaint] ?? 0) + 1;
        }
        final sortedComplaints = complaintMap.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        // Group by student
        final studentMap = <String, int>{};
        for (final doc in docs) {
          final name = doc['studentName'] as String? ?? 'Bilinmeyen';
          studentMap[name] = (studentMap[name] ?? 0) + 1;
        }
        final frequentVisitors = studentMap.entries.toList()
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
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Toplam Ziyaret',
                          '$totalVisits',
                          Icons.local_hospital,
                          Colors.red,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'İlaç Verilen',
                          '$medicationCount',
                          Icons.medication,
                          Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 24),
                  // Top complaints
                  Text(
                    'En Sık Şikayetler',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  ...sortedComplaints
                      .take(10)
                      .map(
                        (e) => ListTile(
                          dense: true,
                          leading: Icon(Icons.sick, color: Colors.red.shade300),
                          title: Text(e.key),
                          trailing: Chip(
                            label: Text('${e.value}'),
                            backgroundColor: Colors.red.shade50,
                          ),
                        ),
                      ),
                  SizedBox(height: 24),
                  // Frequent visitors
                  Text(
                    'Sık Ziyaret Eden Öğrenciler',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  ...frequentVisitors
                      .take(10)
                      .map(
                        (e) => ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.red.shade100,
                            child: Text(
                              e.key.isNotEmpty ? e.key[0] : '?',
                              style: TextStyle(fontSize: 12, color: Colors.red),
                            ),
                          ),
                          title: Text(e.key),
                          trailing: Chip(
                            label: Text('${e.value} ziyaret'),
                            backgroundColor: Colors.red.shade50,
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
