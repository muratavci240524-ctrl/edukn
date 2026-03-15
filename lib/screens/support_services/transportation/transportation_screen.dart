import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart'; // for rootBundle

class TransportationScreen extends StatefulWidget {
  final String? fixedSchoolTypeId;
  final String? fixedSchoolTypeName;

  const TransportationScreen({
    Key? key,
    this.fixedSchoolTypeId,
    this.fixedSchoolTypeName,
  }) : super(key: key);

  @override
  State<TransportationScreen> createState() => _TransportationScreenState();
}

class _TransportationScreenState extends State<TransportationScreen>
    with SingleTickerProviderStateMixin {
  String? _institutionId;
  String? _schoolDocId;
  bool _isLoading = true;
  List<Map<String, dynamic>> _vehicles = [];
  late TabController _tabController;

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
      if (email.contains('@')) {
        _institutionId = email.split('@')[1].split('.')[0].toUpperCase();
      }

      final snap = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', isEqualTo: _institutionId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        _schoolDocId = snap.docs.first.id;
      }

      await _loadVehicles();
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

  Future<void> _loadVehicles() async {
    if (_schoolDocId == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('vehicles')
        .orderBy('vehicleNumber')
        .get();

    setState(() {
      _vehicles = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      _vehicles.sort((a, b) {
        final numA = int.tryParse(a['vehicleNumber']?.toString() ?? '') ?? 999;
        final numB = int.tryParse(b['vehicleNumber']?.toString() ?? '') ?? 999;
        return numA.compareTo(numB);
      });
    });
  }

  Future<void> _addVehicle() async {
    final vehicleNoCtrl = TextEditingController();
    final plateCtrl = TextEditingController();
    final driverCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final capacityCtrl = TextEditingController();
    final routeCtrl = TextEditingController();
    final guideNameCtrl = TextEditingController();
    final guidePhoneCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.directions_bus, color: Colors.blue),
            SizedBox(width: 8),
            Text('Yeni Araç Ekle'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: vehicleNoCtrl,
                decoration: InputDecoration(
                  labelText: 'Araç No *',
                  hintText: 'Örn: 1, 2, 3...',
                  prefixIcon: Icon(Icons.confirmation_number),
                ),
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 12),
              TextField(
                controller: plateCtrl,
                decoration: InputDecoration(
                  labelText: 'Plaka *',
                  prefixIcon: Icon(Icons.featured_video),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              SizedBox(height: 12),
              TextField(
                controller: driverCtrl,
                decoration: InputDecoration(
                  labelText: 'Sürücü Adı *',
                  prefixIcon: Icon(Icons.person),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                decoration: InputDecoration(
                  labelText: 'Sürücü Telefon',
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              SizedBox(height: 12),
              TextField(
                controller: capacityCtrl,
                decoration: InputDecoration(
                  labelText: 'Kapasite',
                  prefixIcon: Icon(Icons.people),
                  hintText: 'Örn: 16',
                ),
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 12),
              TextField(
                controller: routeCtrl,
                decoration: InputDecoration(
                  labelText: 'Güzergah',
                  prefixIcon: Icon(Icons.route),
                  hintText: 'Örn: Merkez - Batıkent',
                ),
              ),
              SizedBox(height: 12),
              TextField(
                controller: guideNameCtrl,
                decoration: InputDecoration(
                  labelText: 'Rehber Adı',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              SizedBox(height: 12),
              TextField(
                controller: guidePhoneCtrl,
                decoration: InputDecoration(
                  labelText: 'Rehber Telefon',
                  prefixIcon: Icon(Icons.phone_android),
                ),
                keyboardType: TextInputType.phone,
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: Text('Ekle'),
          ),
        ],
      ),
    );

    if (result != true) return;
    if (vehicleNoCtrl.text.isEmpty ||
        plateCtrl.text.isEmpty ||
        driverCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Araç No, Plaka ve Sürücü zorunludur!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('vehicles')
        .add({
          'vehicleNumber': vehicleNoCtrl.text.trim(),
          'plateNumber': plateCtrl.text.trim().toUpperCase(),
          'driverName': driverCtrl.text.trim(),
          'driverPhone': phoneCtrl.text.trim(),
          'capacity': int.tryParse(capacityCtrl.text.trim()) ?? 0,
          'route': routeCtrl.text.trim(),
          'guideName': guideNameCtrl.text.trim(),
          'guidePhone': guidePhoneCtrl.text.trim(),
          'passengers': {},
          'createdAt': FieldValue.serverTimestamp(),
        });

    await _loadVehicles();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Araç eklendi'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _deleteVehicle(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Araç Sil'),
        content: Text(
          'Bu aracı ve tüm öğrenci atamalarını silmek istediğinize emin misiniz?',
        ),
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

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolDocId)
          .collection('vehicles')
          .doc(id)
          .delete();
      await _loadVehicles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Araç silindi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _openStatistics() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _TransportationStatisticsScreen(
          vehicles: _vehicles,
          schoolDocId: _schoolDocId!,
          institutionId: _institutionId!,
          fixedSchoolTypeId: widget.fixedSchoolTypeId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return Scaffold(
        appBar: AppBar(title: Text('Servis İşlemleri')),
        body: Center(child: CircularProgressIndicator()),
      );

    return Scaffold(
      appBar: AppBar(
        title: Text('Servis İşlemleri'),
        elevation: 1,
        actions: [
          IconButton(
            icon: Icon(Icons.bar_chart, color: Colors.blue),
            tooltip: 'İstatistikler',
            onPressed: _openStatistics,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blue,
          tabs: [
            Tab(icon: Icon(Icons.directions_bus), text: 'Araçlar'),
            Tab(icon: Icon(Icons.fact_check), text: 'Yoklama'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _addVehicle,
              icon: Icon(Icons.add),
              label: Text('Araç Ekle'),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [_buildVehiclesList(), _buildAttendanceView()],
      ),
    );
  }

  Widget _buildVehiclesList() {
    if (_vehicles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_bus, size: 64, color: Colors.grey.shade300),
            SizedBox(height: 16),
            Text('Henüz araç yok', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _vehicles.length,
      itemBuilder: (context, index) {
        final v = _vehicles[index];
        final passengers = (v['passengers'] as Map<String, dynamic>?) ?? {};
        final count = passengers.length;

        return Card(
          elevation: 2,
          margin: EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _VehicleDetailScreen(
                    schoolDocId: _schoolDocId!,
                    institutionId: _institutionId!,
                    vehicle: v,
                    fixedSchoolTypeId: widget.fixedSchoolTypeId,
                  ),
                ),
              );
              _loadVehicles();
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.blue.shade50,
                    radius: 24,
                    child: Text(
                      v['vehicleNumber']?.toString() ?? '?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${v['plateNumber']} - ${v['driverName']}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (v['route'] != null)
                          Text(
                            'Güzergah: ${v['route']}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        SizedBox(height: 4),
                        Text(
                          'Şoför: ${v['driverPhone'] ?? ''}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                        if (v['guideName'] != null &&
                            v['guideName'].toString().isNotEmpty)
                          Text(
                            'Rehber: ${v['guideName']} (${v['guidePhone'] ?? ''})',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade100),
                        ),
                        child: Text(
                          '$count / ${v['capacity'] ?? '-'}',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          color: Colors.red.shade400,
                        ),
                        onPressed: () => _deleteVehicle(v['id']),
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttendanceView() {
    return _AttendanceScreen(
      schoolDocId: _schoolDocId!,
      institutionId: _institutionId!,
      vehicles: _vehicles,
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Vehicle Detail (Manage Students with Reorder & Print)
// ---------------------------------------------------------------------------
class _VehicleDetailScreen extends StatefulWidget {
  final String schoolDocId;
  final String institutionId;
  final Map<String, dynamic> vehicle;
  final String? fixedSchoolTypeId;

  const _VehicleDetailScreen({
    required this.schoolDocId,
    required this.institutionId,
    required this.vehicle,
    this.fixedSchoolTypeId,
  });

  @override
  State<_VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<_VehicleDetailScreen> {
  // passengers: { studentId: { morning: bool, evening: bool, order: int } }
  Map<String, dynamic> _passengers = {};
  List<Map<String, dynamic>> _studentDetails = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _passengers = Map<String, dynamic>.from(widget.vehicle['passengers'] ?? {});
    _loadStudentDetails();
  }

  Future<void> _loadStudentDetails() async {
    if (_passengers.isEmpty) {
      if (mounted)
        setState(() {
          _studentDetails = [];
          _isLoading = false;
        });
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final all = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      _studentDetails = all
          .where((s) => _passengers.containsKey(s['id']))
          .toList();

      // Sort strategy:
      // 1. Check if 'order' exists in passenger map
      // 2. Sort by order ASC
      // 3. Fallback to Name ASC if order missing/equal
      _studentDetails.sort((a, b) {
        final pA = _passengers[a['id']] ?? {};
        final pB = _passengers[b['id']] ?? {};
        final orderA = (pA['order'] as int?) ?? 9999;
        final orderB = (pB['order'] as int?) ?? 9999;

        if (orderA != orderB) return orderA.compareTo(orderB);
        return (a['name'] as String).compareTo(b['name'] as String);
      });

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openAddStudentDialog() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _VehicleStudentSelectionScreen(
          schoolDocId: widget.schoolDocId,
          institutionId: widget.institutionId,
          vehicleId: widget.vehicle['id'],
          vehicleNumber: widget.vehicle['vehicleNumber'] ?? '?',
          currentPassengers: _passengers,
          fixedSchoolTypeId: widget.fixedSchoolTypeId,
        ),
      ),
    );
    // Reload
    final vSnap = await FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolDocId)
        .collection('vehicles')
        .doc(widget.vehicle['id'])
        .get();
    if (vSnap.exists) {
      setState(() {
        _passengers = Map<String, dynamic>.from(
          vSnap.data()?['passengers'] ?? {},
        );
        _isLoading = true;
      });
      _loadStudentDetails();
    }
  }

  Future<void> _removePassenger(String studentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Öğrenciyi Çıkar'),
        content: Text(
          'Bu öğrenciyi servisten çıkarmak istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Çıkar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _passengers.remove(studentId);
      _studentDetails.removeWhere((s) => s['id'] == studentId);
    });

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolDocId)
        .collection('vehicles')
        .doc(widget.vehicle['id'])
        .update({'passengers': _passengers});
  }

  Future<void> _updateOrder() async {
    // Save current order of _studentDetails to _passengers
    for (int i = 0; i < _studentDetails.length; i++) {
      final sid = _studentDetails[i]['id'];
      if (_passengers.containsKey(sid)) {
        final pData = Map<String, dynamic>.from(_passengers[sid] as Map);
        pData['order'] = i;
        _passengers[sid] = pData;
      }
    }

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolDocId)
        .collection('vehicles')
        .doc(widget.vehicle['id'])
        .update({'passengers': _passengers});
  }

  Future<void> _transferPassenger(Map<String, dynamic> student) async {
    // 1. Fetch other vehicles
    final snap = await FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolDocId)
        .collection('vehicles')
        .get();

    final otherVehicles = snap.docs
        .where((d) => d.id != widget.vehicle['id'])
        .map((d) => {'id': d.id, ...d.data()})
        .toList();

    if (otherVehicles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transfer edilecek başka araç bulunamadı.')),
      );
      return;
    }

    final targetVehicle = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Transfer: ${student['name']}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: otherVehicles.length,
            itemBuilder: (context, index) {
              final v = otherVehicles[index];
              return ListTile(
                leading: CircleAvatar(child: Text(v['vehicleNumber'] ?? '?')),
                title: Text('Araç ${v['vehicleNumber']} - ${v['plateNumber']}'),
                subtitle: Text(v['route'] ?? '-'),
                onTap: () => Navigator.pop(ctx, v),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('İptal')),
        ],
      ),
    );

    if (targetVehicle == null) return;

    final studentId = student['id'];
    final pData = _passengers[studentId];

    // 2. Add to new vehicle
    final targetId = targetVehicle['id'];
    final targetPassengers = Map<String, dynamic>.from(
      targetVehicle['passengers'] ?? {},
    );
    targetPassengers[studentId] = pData;

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolDocId)
        .collection('vehicles')
        .doc(targetId)
        .update({'passengers': targetPassengers});

    // 3. Remove from current vehicle
    setState(() {
      _passengers.remove(studentId);
      _studentDetails.removeWhere((s) => s['id'] == studentId);
    });

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolDocId)
        .collection('vehicles')
        .doc(widget.vehicle['id'])
        .update({'passengers': _passengers});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ ${student['name']} Araç ${targetVehicle['vehicleNumber']}\'e transfer edildi.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _updateStudentService(
    String studentId,
    String type,
    bool val,
  ) async {
    final pData = Map<String, dynamic>.from(_passengers[studentId] ?? {});
    pData[type] = val;

    setState(() {
      _passengers[studentId] = pData;
    });

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolDocId)
        .collection('vehicles')
        .doc(widget.vehicle['id'])
        .update({'passengers': _passengers});
  }

  void _showStudentDetails(Map<String, dynamic> s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.person, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(child: Text('${s['name']} ${s['surname']}')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow(
                'Okul No',
                s['studentNo'] ?? s['studentNumber'] ?? '-',
              ),
              _detailRow('Sınıf', s['className'] ?? '-'),
              Divider(),
              _detailRow('Veli Adı', s['parentName'] ?? '-'),
              _detailRow('Veli Tel', s['parentPhone'] ?? '-'),
              Divider(),
              _detailRow('Adres', s['address'] ?? '-'),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.edit_note, color: Colors.blue),
            tooltip: 'Aracı Düzenle',
            onPressed: _editVehicle,
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Kapat')),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _editVehicle() async {
    final vehicleNoCtrl = TextEditingController(
      text: widget.vehicle['vehicleNumber']?.toString(),
    );
    final plateCtrl = TextEditingController(
      text: widget.vehicle['plateNumber'],
    );
    final driverCtrl = TextEditingController(
      text: widget.vehicle['driverName'],
    );
    final phoneCtrl = TextEditingController(
      text: widget.vehicle['driverPhone'],
    );
    final capacityCtrl = TextEditingController(
      text: widget.vehicle['capacity']?.toString(),
    );
    final routeCtrl = TextEditingController(text: widget.vehicle['route']);
    final guideNameCtrl = TextEditingController(
      text: widget.vehicle['guideName'],
    );
    final guidePhoneCtrl = TextEditingController(
      text: widget.vehicle['guidePhone'],
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.edit, color: Colors.blue),
            SizedBox(width: 8),
            Text('Aracı Düzenle'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: vehicleNoCtrl,
                decoration: InputDecoration(
                  labelText: 'Araç No *',
                  prefixIcon: Icon(Icons.confirmation_number),
                ),
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 12),
              TextField(
                controller: plateCtrl,
                decoration: InputDecoration(
                  labelText: 'Plaka *',
                  prefixIcon: Icon(Icons.featured_video),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              SizedBox(height: 12),
              TextField(
                controller: driverCtrl,
                decoration: InputDecoration(
                  labelText: 'Sürücü Adı *',
                  prefixIcon: Icon(Icons.person),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                decoration: InputDecoration(
                  labelText: 'Sürücü Telefon',
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              SizedBox(height: 12),
              TextField(
                controller: capacityCtrl,
                decoration: InputDecoration(
                  labelText: 'Kapasite',
                  prefixIcon: Icon(Icons.people),
                ),
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 12),
              TextField(
                controller: routeCtrl,
                decoration: InputDecoration(
                  labelText: 'Güzergah',
                  prefixIcon: Icon(Icons.route),
                ),
              ),
              SizedBox(height: 12),
              TextField(
                controller: guideNameCtrl,
                decoration: InputDecoration(
                  labelText: 'Rehber Adı',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              SizedBox(height: 12),
              TextField(
                controller: guidePhoneCtrl,
                decoration: InputDecoration(
                  labelText: 'Rehber Telefon',
                  prefixIcon: Icon(Icons.phone_android),
                ),
                keyboardType: TextInputType.phone,
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: Text('Güncelle'),
          ),
        ],
      ),
    );

    if (result != true) return;

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolDocId)
        .collection('vehicles')
        .doc(widget.vehicle['id'])
        .update({
          'vehicleNumber': vehicleNoCtrl.text.trim(),
          'plateNumber': plateCtrl.text.trim().toUpperCase(),
          'driverName': driverCtrl.text.trim(),
          'driverPhone': phoneCtrl.text.trim(),
          'capacity': int.tryParse(capacityCtrl.text.trim()) ?? 0,
          'route': routeCtrl.text.trim(),
          'guideName': guideNameCtrl.text.trim(),
          'guidePhone': guidePhoneCtrl.text.trim(),
        });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Araç bilgileri güncellendi'),
          backgroundColor: Colors.green,
        ),
      );
      // We don't have a direct way to reload widget.vehicle here without parent callback,
      // but the changes are in Firestore. The detail screen might need a pop or a refresh.
      // Easiest is to pop and let the parent reload list.
      Navigator.pop(context);
    }
  }

  pw.Widget _pwInfoRow(String label, String value, pw.Font font) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label: ',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: font),
          ),
          pw.TextSpan(text: value),
        ],
      ),
    );
  }

  Future<void> _printList() async {
    final pdf = pw.Document();

    // Load font if needed, for simplicity using default or built-in,
    // but for Turkish chars we ideally need a font.
    // Using a bundled font is best practice but complex in this snippet.
    // We will try standard setup. If generic font fails chars, we might need simple fallback.
    // 'Theme.withFont' can be used with Printing package's 'fontFromAssetBundle' if available.
    // For now, let's use standard.

    final vehicleInfo = widget.vehicle;
    final regularFont = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Servis Yolcu Listesi',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(DateFormat('dd.MM.yyyy').format(DateTime.now())),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _pwInfoRow(
                          'Araç No',
                          '${vehicleInfo['vehicleNumber']}',
                          boldFont,
                        ),
                        pw.SizedBox(height: 4),
                        _pwInfoRow(
                          'Plaka',
                          '${vehicleInfo['plateNumber']}',
                          boldFont,
                        ),
                        pw.SizedBox(height: 4),
                        _pwInfoRow(
                          'Güzergah',
                          '${vehicleInfo['route'] ?? '-'}',
                          boldFont,
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _pwInfoRow(
                          'Sürücü',
                          '${vehicleInfo['driverName']}',
                          boldFont,
                        ),
                        pw.SizedBox(height: 4),
                        _pwInfoRow(
                          'Telefon',
                          '${vehicleInfo['driverPhone']}',
                          boldFont,
                        ),
                        if (vehicleInfo['guideName'] != null &&
                            vehicleInfo['guideName'].toString().isNotEmpty) ...[
                          pw.SizedBox(height: 4),
                          _pwInfoRow(
                            'Rehber',
                            '${vehicleInfo['guideName']}',
                            boldFont,
                          ),
                          pw.SizedBox(height: 4),
                          _pwInfoRow(
                            'Rehber Tel',
                            '${vehicleInfo['guidePhone'] ?? '-'}',
                            boldFont,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Table.fromTextArray(
              context: context,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headers: [
                '#',
                'Öğrenci Adı',
                'TC No',
                'Sınıf',
                'Veli',
                'Telefon',
                'Adres',
              ],
              data: List<List<dynamic>>.generate(_studentDetails.length, (
                index,
              ) {
                final s = _studentDetails[index];
                return [
                  (index + 1).toString(),
                  '${s['name']} ${s['surname']}',
                  '${s['tcNo'] ?? '-'}',
                  '${s['className'] ?? '-'}',
                  '${s['parentName'] ?? '-'}',
                  '${s['parentPhone'] ?? '-'}',
                  '${s['address'] ?? '-'}',
                ];
              }),
              columnWidths: {
                0: pw.FixedColumnWidth(30), // Seq
                6: pw.FlexColumnWidth(2), // Address
              },
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.vehicle['vehicleNumber']} Nolu Araç (${widget.vehicle['plateNumber']})',
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.print),
            tooltip: 'Listeyi Yazdır',
            onPressed: () {
              if (_studentDetails.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Liste boş, yazdırılamaz.')),
                );
              } else {
                _printList();
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Colors.yellow.shade100,
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.drag_indicator,
                        size: 16,
                        color: Colors.orange.shade800,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sıralamayı değiştirmek için basılı tutup sürükleyin.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.all(16),
                  color: Colors.grey.shade50,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _detailInfoTile(
                              Icons.person,
                              'Sürücü',
                              widget.vehicle['driverName'] ?? '-',
                              widget.vehicle['driverPhone'] ?? '',
                            ),
                          ),
                          if (widget.vehicle['guideName'] != null &&
                              widget.vehicle['guideName'].toString().isNotEmpty)
                            Expanded(
                              child: _detailInfoTile(
                                Icons.person_outline,
                                'Rehber',
                                widget.vehicle['guideName'],
                                widget.vehicle['guidePhone'] ?? '',
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: _studentDetails.length,
                    padding: EdgeInsets.all(16),
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (oldIndex < newIndex) {
                          newIndex -= 1;
                        }
                        final item = _studentDetails.removeAt(oldIndex);
                        _studentDetails.insert(newIndex, item);
                      });
                      _updateOrder();
                    },
                    itemBuilder: (context, index) {
                      final s = _studentDetails[index];
                      final pData = _passengers[s['id']] ?? {};
                      final isMorning = pData['morning'] == true;
                      final isEvening = pData['evening'] == true;

                      return Card(
                        key: ValueKey(s['id']),
                        margin: EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text('${index + 1}'),
                            backgroundColor: Colors.blue.shade50,
                            foregroundColor: Colors.blue,
                          ),
                          title: Text('${s['name']} ${s['surname']}'),
                          subtitle: Text(
                            '${s['className'] ?? '-'}  •  No: ${s['studentNo'] ?? s['studentNumber'] ?? '-'}',
                          ),
                          onTap: () => _showStudentDetails(s),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _serviceToggle(
                                'S',
                                isMorning,
                                (v) => _updateStudentService(
                                  s['id'],
                                  'morning',
                                  v,
                                ),
                              ),
                              _serviceToggle(
                                'A',
                                isEvening,
                                (v) => _updateStudentService(
                                  s['id'],
                                  'evening',
                                  v,
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'remove') _removePassenger(s['id']);
                                  if (v == 'transfer') _transferPassenger(s);
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'transfer',
                                    child: Text('Farklı Araca Transfer'),
                                  ),
                                  PopupMenuItem(
                                    value: 'remove',
                                    child: Text(
                                      'Listeden Çıkar',
                                      style: TextStyle(color: Colors.red),
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
                ),
                Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openAddStudentDialog,
                      icon: Icon(Icons.person_add),
                      label: Text('Öğrenci Ekle / Düzenle'),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _detailInfoTile(
    IconData icon,
    String label,
    String name,
    String phone,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blue.shade700),
        SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              Text(
                name,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
              if (phone.isNotEmpty)
                Text(phone, style: TextStyle(fontSize: 11, color: Colors.blue)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _serviceToggle(String label, bool value, Function(bool) onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 24,
        height: 24,
        margin: EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: value
              ? (label == 'S' ? Colors.orange : Colors.indigo)
              : Colors.grey.shade200,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: value ? Colors.white : Colors.grey.shade600,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Selection Screen (Improved UI)
// ---------------------------------------------------------------------------
class _VehicleStudentSelectionScreen extends StatefulWidget {
  final String schoolDocId;
  final String institutionId;
  final String vehicleId;
  final String vehicleNumber;
  final Map<String, dynamic> currentPassengers;
  final String? fixedSchoolTypeId;

  const _VehicleStudentSelectionScreen({
    required this.schoolDocId,
    required this.institutionId,
    required this.vehicleId,
    required this.vehicleNumber,
    required this.currentPassengers,
    this.fixedSchoolTypeId,
  });

  @override
  State<_VehicleStudentSelectionScreen> createState() =>
      _VehicleStudentSelectionScreenState();
}

class _VehicleStudentSelectionScreenState
    extends State<_VehicleStudentSelectionScreen> {
  List<Map<String, dynamic>> _allStudents = [];
  Map<String, dynamic> _localPassengers = {};
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _localPassengers = Map.from(widget.currentPassengers);
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    try {
      var query = FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId);

      if (widget.fixedSchoolTypeId != null) {
        query = query.where(
          'schoolTypeId',
          isEqualTo: widget.fixedSchoolTypeId,
        );
      }

      final snap = await query.orderBy('name').get();

      setState(() {
        _allStudents = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveChanges() async {
    await FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolDocId)
        .collection('vehicles')
        .doc(widget.vehicleId)
        .update({'passengers': _localPassengers});

    Navigator.pop(context);
  }

  void _toggleStudent(String id, bool? morning, bool? evening) {
    if ((morning == false || morning == null) &&
        (evening == false || evening == null)) {
      setState(() {
        _localPassengers.remove(id);
      });
    } else {
      setState(() {
        final existing = _localPassengers[id] as Map? ?? {};
        // preserve order if exists
        _localPassengers[id] = {
          'morning': morning ?? false,
          'evening': evening ?? false,
          'order': existing['order'],
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter
    final filtered = _allStudents.where((s) {
      final term = _searchQuery.toLowerCase();
      final name = '${s['name']} ${s['surname']}'.toLowerCase();
      final no = '${s['studentNo'] ?? s['studentNumber'] ?? ''}'.toLowerCase();
      final cls = '${s['className'] ?? ''}'.toLowerCase();
      return name.contains(term) || no.contains(term) || cls.contains(term);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.vehicleNumber} Nolu Araç Öğrencileri'),
        actions: [
          TextButton(
            onPressed: _saveChanges,
            child: Text(
              'KAYDET',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Öğrenci Ara (Ad, No, Sınıf)...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final s = filtered[index];
                      final id = s['id'];
                      final isAssigned = _localPassengers.containsKey(id);
                      final pData = _localPassengers[id] ?? {};
                      final isMorning = pData['morning'] == true;
                      final isEvening = pData['evening'] == true;

                      return Card(
                        margin: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        color: isAssigned ? Colors.blue.shade50 : Colors.white,
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isAssigned
                                      ? Colors.blue
                                      : Colors.grey.shade300,
                                  child: isAssigned
                                      ? Text(
                                          widget.vehicleNumber,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : Icon(Icons.person, color: Colors.grey),
                                ),
                                title: Text(
                                  '${s['name']} ${s['surname']}',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  '${s['className'] ?? '?'} - No: ${s['studentNo'] ?? s['studentNumber'] ?? '?'}',
                                ),
                                trailing: isAssigned
                                    ? Icon(
                                        Icons.check_circle,
                                        color: Colors.blue,
                                      )
                                    : Icon(
                                        Icons.circle_outlined,
                                        color: Colors.grey,
                                      ),
                                onTap: () {
                                  // Toggle entire assignment on tap (auto select both if selecting)
                                  if (isAssigned) {
                                    // Deselect
                                    _toggleStudent(id, false, false);
                                  } else {
                                    // Select Both
                                    _toggleStudent(id, true, true);
                                  }
                                },
                              ),
                              if (isAssigned)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        'Kullanım:',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Wrap(
                                          spacing: 8,
                                          children: [
                                            ChoiceChip(
                                              label: Text('Sabah'),
                                              selected: isMorning,
                                              selectedColor:
                                                  Colors.orange.shade200,
                                              onSelected: (v) => _toggleStudent(
                                                id,
                                                v,
                                                isEvening,
                                              ),
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            ChoiceChip(
                                              label: Text('Akşam'),
                                              selected: isEvening,
                                              selectedColor:
                                                  Colors.indigo.shade200,
                                              onSelected: (v) => _toggleStudent(
                                                id,
                                                isMorning,
                                                v,
                                              ),
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ],
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
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Attendance Screen (Unchanged, just ensuring it's here)
// ---------------------------------------------------------------------------
class _AttendanceScreen extends StatefulWidget {
  final String schoolDocId;
  final String institutionId;
  final List<Map<String, dynamic>> vehicles;

  const _AttendanceScreen({
    required this.schoolDocId,
    required this.institutionId,
    required this.vehicles,
  });

  @override
  State<_AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<_AttendanceScreen> {
  Map<String, dynamic>? _selectedVehicle;

  @override
  Widget build(BuildContext context) {
    if (_selectedVehicle != null) {
      return _TakeAttendanceView(
        schoolDocId: widget.schoolDocId,
        institutionId: widget.institutionId,
        vehicle: _selectedVehicle!,
        onBack: () => setState(() => _selectedVehicle = null),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: widget.vehicles.length,
      itemBuilder: (context, index) {
        final v = widget.vehicles[index];
        return Card(
          margin: EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Text(
                v['vehicleNumber'] ?? '?',
                style: TextStyle(
                  color: Colors.blue.shade900,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text('Araç ${v['vehicleNumber']} - ${v['plateNumber']}'),
            subtitle: Text('Yoklama almak için tıklayın'),
            trailing: Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => setState(() => _selectedVehicle = v),
          ),
        );
      },
    );
  }
}

class _TakeAttendanceView extends StatefulWidget {
  final String schoolDocId;
  final String institutionId;
  final Map<String, dynamic> vehicle;
  final VoidCallback onBack;

  const _TakeAttendanceView({
    required this.schoolDocId,
    required this.institutionId,
    required this.vehicle,
    required this.onBack,
  });

  @override
  State<_TakeAttendanceView> createState() => _TakeAttendanceViewState();
}

class _TakeAttendanceViewState extends State<_TakeAttendanceView>
    with SingleTickerProviderStateMixin {
  late TabController _periodTabController;
  DateTime _date = DateTime.now();

  List<Map<String, dynamic>> _students = [];
  Map<String, dynamic> _attendanceData = {}; // { studentId: 'came' | 'absent' }
  Map<String, dynamic> _morningStatusCache = {}; // For evening view dots
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _periodTabController = TabController(length: 2, vsync: this);
    _periodTabController.addListener(_loadAttendance);
    _loadStudentsAndAttendance();
  }

  @override
  void dispose() {
    _periodTabController.dispose();
    super.dispose();
  }

  String get _period => _periodTabController.index == 0 ? 'morning' : 'evening';
  String get _dateStr => DateFormat('yyyy-MM-dd').format(_date);

  Future<void> _loadStudentsAndAttendance() async {
    setState(() => _isLoading = true);

    final passengers =
        (widget.vehicle['passengers'] as Map<String, dynamic>?) ?? {};
    if (passengers.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();
      final all = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      _students = all.where((s) => passengers.containsKey(s['id'])).toList();
      // Sort: Check 'order' field in passengers
      _students.sort((a, b) {
        final pA = passengers[a['id']] ?? {};
        final pB = passengers[b['id']] ?? {};
        final orderA = (pA['order'] as int?) ?? 9999;
        final orderB = (pB['order'] as int?) ?? 9999;
        if (orderA != orderB) return orderA.compareTo(orderB);
        return (a['name'] as String).compareTo(b['name'] as String);
      });
    } catch (e) {
      print(e);
    }

    await _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _attendanceData = {}; // Clear previous data
    });
    try {
      final period = _period;

      // Always fetch morning status if we are in evening view, or even if we're in morning view
      // to keep cache warm and consistent.
      final mDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolDocId)
          .collection('vehicles')
          .doc(widget.vehicle['id'])
          .collection('attendance')
          .doc('${_dateStr}_morning')
          .get();

      final morningStatus = mDoc.exists ? (mDoc.data()?['status'] ?? {}) : {};

      final doc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolDocId)
          .collection('vehicles')
          .doc(widget.vehicle['id'])
          .collection('attendance')
          .doc('${_dateStr}_$period')
          .get();

      if (mounted) {
        setState(() {
          _morningStatusCache = morningStatus;
          _attendanceData = doc.exists ? (doc.data()?['status'] ?? {}) : {};
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markAttendance(String studentId, String status) async {
    setState(() {
      _attendanceData[studentId] = status;
      if (_period == 'morning') {
        _morningStatusCache[studentId] = status;
      }
    });

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolDocId)
        .collection('vehicles')
        .doc(widget.vehicle['id'])
        .collection('attendance')
        .doc('${_dateStr}_$_period')
        .set({
          'date': Timestamp.fromDate(_date),
          'period': _period,
          'status': _attendanceData,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Yoklama kaydedildi'),
          duration: Duration(milliseconds: 500),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final passengers =
        (widget.vehicle['passengers'] as Map<String, dynamic>?) ?? {};
    final relevantStudents = _students.where((s) {
      final pData = passengers[s['id']];
      if (pData == null) return false;
      return pData[_period] == true;
    }).toList();

    return Column(
      children: [
        Container(
          color: Colors.white,
          child: Column(
            children: [
              ListTile(
                leading: IconButton(
                  icon: Icon(Icons.arrow_back),
                  onPressed: widget.onBack,
                ),
                title: Text(
                  '${DateFormat('dd MMMM yyyy', 'tr_TR').format(_date)} Yoklaması',
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Araç ${widget.vehicle['vehicleNumber']} (${widget.vehicle['plateNumber']})',
                    ),
                    if (widget.vehicle['guideName'] != null &&
                        widget.vehicle['guideName'].toString().isNotEmpty)
                      Text(
                        'Rehber: ${widget.vehicle['guideName']} (${widget.vehicle['guidePhone'] ?? ''})',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.indigo.shade300,
                        ),
                      ),
                  ],
                ),
                trailing: IconButton(
                  icon: Icon(Icons.calendar_today),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2023),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) {
                      setState(() {
                        _date = d;
                      });
                      _loadAttendance();
                    }
                  },
                ),
              ),
              TabBar(
                controller: _periodTabController,
                tabs: [
                  Tab(text: 'SABAH'),
                  Tab(text: 'AKŞAM'),
                ],
                labelColor: Colors.blue,
                unselectedLabelColor: Colors.grey,
              ),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.grey.shade50,
                child: Text(
                  '( +: Evet,  -: Hayır )',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: relevantStudents.length,
                  itemBuilder: (context, index) {
                    final s = relevantStudents[index];
                    final status = _attendanceData[s['id']];
                    final isEvening = _period == 'evening';

                    Color dotColor = Colors.grey.shade400;
                    if (isEvening) {
                      final mStatus = _morningStatusCache[s['id']];
                      if (mStatus == 'came')
                        dotColor = Colors.green;
                      else if (mStatus == 'absent')
                        dotColor = Colors.red;
                    }

                    return Card(
                      key: ValueKey(
                        '${s['id']}_${_period}_${status}_${dotColor.value}',
                      ),
                      child: ListTile(
                        leading: Stack(
                          children: [
                            CircleAvatar(child: Text(s['name'][0])),
                            if (isEvening)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: dotColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text('${s['name']} ${s['surname']}'),
                        subtitle: Text(s['className'] ?? '-'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _AttendanceButton(
                              label: '-',
                              color: Colors.red,
                              isSelected: status == 'absent',
                              onTap: () => _markAttendance(s['id'], 'absent'),
                            ),
                            SizedBox(width: 8),
                            _AttendanceButton(
                              label: '+',
                              color: Colors.green,
                              isSelected: status == 'came',
                              onTap: () => _markAttendance(s['id'], 'came'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AttendanceButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _AttendanceButton({
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          border: Border.all(color: color, width: 2),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Statistics Screen (Stats)
// ---------------------------------------------------------------------------
class _TransportationStatisticsScreen extends StatelessWidget {
  final List<Map<String, dynamic>> vehicles;
  final String schoolDocId;
  final String institutionId;
  final String? fixedSchoolTypeId;

  const _TransportationStatisticsScreen({
    required this.vehicles,
    required this.schoolDocId,
    required this.institutionId,
    this.fixedSchoolTypeId,
  });

  @override
  Widget build(BuildContext context) {
    int totalCapacity = 0;
    int totalAssigned = 0;

    for (var v in vehicles) {
      totalCapacity += (v['capacity'] as int? ?? 0);
      final p = (v['passengers'] as Map?) ?? {};
      totalAssigned += p.length;
    }

    double occupancy = totalCapacity > 0
        ? (totalAssigned / totalCapacity)
        : 0.0;

    return Scaffold(
      appBar: AppBar(title: Text('Servis İstatistikleri')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'Toplam Araç',
                    value: '${vehicles.length}',
                    icon: Icons.directions_bus,
                    color: Colors.blue,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: _StatCard(
                    title: 'Toplam Öğrenci',
                    value: '$totalAssigned',
                    icon: Icons.people,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'Doluluk Oranı',
                    value: '%${(occupancy * 100).toStringAsFixed(1)}',
                    icon: Icons.pie_chart,
                    color: Colors.green,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: _StatCard(
                    title: 'Kullanım İstatistiği',
                    value: 'Raporlar',
                    icon: Icons.bar_chart,
                    color: Colors.purple,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => _UsageStatisticsView(
                            schoolDocId: schoolDocId,
                            institutionId: institutionId,
                            vehicles: vehicles,
                            fixedSchoolTypeId: fixedSchoolTypeId,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),
            Text(
              'Araç Bazlı Durum',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),

            ...vehicles.map((v) {
              final p = (v['passengers'] as Map?) ?? {};
              final cap = (v['capacity'] as int? ?? 0);
              final count = p.length;
              final occ = cap > 0 ? count / cap : 0.0;

              return Card(
                margin: EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(child: Text(v['vehicleNumber'] ?? '?')),
                  title: Text('${v['plateNumber']}'),
                  subtitle: LinearProgressIndicator(
                    value: occ,
                    backgroundColor: Colors.grey.shade200,
                    color: occ > 0.9 ? Colors.red : Colors.blue,
                  ),
                  trailing: Text('$count / $cap'),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              title,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. Usage Statistics View (List of Students)
// ---------------------------------------------------------------------------
class _UsageStatisticsView extends StatefulWidget {
  final String schoolDocId;
  final String institutionId;
  final List<Map<String, dynamic>> vehicles;
  final String? fixedSchoolTypeId;

  const _UsageStatisticsView({
    required this.schoolDocId,
    required this.institutionId,
    required this.vehicles,
    this.fixedSchoolTypeId,
  });

  @override
  State<_UsageStatisticsView> createState() => _UsageStatisticsViewState();
}

class _UsageStatisticsViewState extends State<_UsageStatisticsView> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _usageList = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUsageData();
  }

  Future<void> _loadUsageData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Get all assigned student IDs from ALL vehicles passed
      Set<String> assignedIds = {};
      for (var v in widget.vehicles) {
        final passengers = (v['passengers'] as Map?) ?? {};
        assignedIds.addAll(passengers.keys.cast<String>());
      }

      // If no one is assigned yet, we still show the list but it might be empty.
      // However, the user wants students to be automatically included?
      // If they are assigned to a vehicle, they should be here.

      // 2. Resolve students of the institution
      // We must include institutionId for Firestore Security Rules.
      final studentSnap = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      List<Map<String, dynamic>> studentsToProcess = studentSnap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList();

      // If we want to strictly show only assigned ones:
      if (assignedIds.isNotEmpty) {
        studentsToProcess = studentsToProcess
            .where((s) => assignedIds.contains(s['id']))
            .toList();
      }

      // 3. Fetch attendance logs
      List<Map<String, dynamic>> allAttendance = [];
      for (var v in widget.vehicles) {
        final vehicleId = v['id'];
        if (vehicleId == null) continue;

        final attSnap = await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolDocId)
            .collection('vehicles')
            .doc(vehicleId)
            .collection('attendance')
            .limit(500) // Safety limit
            .get();
        allAttendance.addAll(
          attSnap.docs.map((d) => {'vehicleId': vehicleId, ...d.data()}),
        );
      }

      // 4. If we missed any students who have attendance but aren't currently "assigned",
      // we can optionally fetch them too, but let's keep it clean for now.

      // 5. Aggregate
      List<Map<String, dynamic>> results = [];
      for (var s in studentsToProcess) {
        final sid = s['id'];
        int cameCount = 0;
        List<DateTime> cameDates = [];
        List<DateTime> absentDates = [];

        for (var att in allAttendance) {
          final statusMap = (att['status'] as Map?) ?? {};
          final status = statusMap[sid];
          if (status == null) continue;

          final timestamp = att['date'] as Timestamp?;
          if (timestamp == null) continue;
          final date = timestamp.toDate();

          if (status == 'came') {
            cameCount++;
            cameDates.add(date);
          } else if (status == 'absent') {
            absentDates.add(date);
          }
        }

        cameDates.sort((a, b) => b.compareTo(a));
        absentDates.sort((a, b) => b.compareTo(a));

        results.add({
          ...s,
          'usageCount': cameCount,
          'cameDates': cameDates,
          'absentDates': absentDates,
        });
      }

      // Sort
      results.sort((a, b) {
        final countA = a['usageCount'] as int;
        final countB = b['usageCount'] as int;
        if (countA != countB) return countB.compareTo(countA);
        final nameA = (a['name']?.toString() ?? '').toLowerCase();
        final nameB = (b['name']?.toString() ?? '').toLowerCase();
        return nameA.compareTo(nameB);
      });

      if (mounted) {
        setState(() {
          _usageList = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Usage stats fetch error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Tamam',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoading && _usageList.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('Öğrenci Kullanım İstatistikleri')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_off, size: 64, color: Colors.grey.shade300),
              SizedBox(height: 16),
              Text(
                'Servislerde kayıtlı öğrenci bulunamadı.\n(Öğrencileri önce bir araca atamalısınız)',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }
    final filtered = _usageList.where((s) {
      final term = _searchQuery.toLowerCase();
      final name = '${s['name']} ${s['surname']}'.toLowerCase();
      return name.contains(term);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text('Öğrenci Kullanım İstatistikleri')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Öğrenci Ara...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final s = filtered[index];
                      return Card(
                        margin: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(child: Text(s['name'][0])),
                          title: Text('${s['name']} ${s['surname']}'),
                          subtitle: Text(s['className'] ?? '-'),
                          trailing: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${s['usageCount']} Gün',
                              style: TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    _StudentAttendanceReportScreen(student: s),
                              ),
                            );
                          },
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

class _StudentAttendanceReportScreen extends StatelessWidget {
  final Map<String, dynamic> student;

  const _StudentAttendanceReportScreen({required this.student});

  Future<void> _printReport() async {
    final pdf = pw.Document();
    final regularFont = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    final cameDates = (student['cameDates'] as List<DateTime>?) ?? [];
    final absentDates = (student['absentDates'] as List<DateTime>?) ?? [];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'Bireysel Servis Kullanım Raporu',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text('Öğrenci: ${student['name']} ${student['surname']}'),
          pw.Text('Sınıf: ${student['className'] ?? '-'}'),
          pw.Text('Toplam Kullanım: ${student['usageCount']} Gün'),
          pw.SizedBox(height: 20),

          pw.Text(
            'Servis Kullanılan Günler (${cameDates.length})',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Divider(),
          pw.Wrap(
            spacing: 10,
            runSpacing: 5,
            children: cameDates
                .map((d) => pw.Text(DateFormat('dd.MM.yyyy').format(d)))
                .toList(),
          ),

          pw.SizedBox(height: 20),
          pw.Text(
            'Servis Kullanılmayan Günler (${absentDates.length})',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.red,
            ),
          ),
          pw.Divider(),
          pw.Wrap(
            spacing: 10,
            runSpacing: 5,
            children: absentDates
                .map((d) => pw.Text(DateFormat('dd.MM.yyyy').format(d)))
                .toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: '${student['name']}_Servis_Raporu.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cameDates = (student['cameDates'] as List<DateTime>?) ?? [];
    final absentDates = (student['absentDates'] as List<DateTime>?) ?? [];

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${student['name']} - Servis Raporu'),
          actions: [
            IconButton(
              icon: Icon(Icons.print),
              onPressed: _printReport,
              tooltip: 'Raporu Yazdır',
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'GELDİĞİ GÜNLER (${cameDates.length})'),
              Tab(text: 'GELMEDİĞİ GÜNLER (${absentDates.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _DateList(dates: cameDates, color: Colors.green),
            _DateList(dates: absentDates, color: Colors.red),
          ],
        ),
      ),
    );
  }
}

class _DateList extends StatelessWidget {
  final List<DateTime> dates;
  final Color color;

  const _DateList({required this.dates, required this.color});

  @override
  Widget build(BuildContext context) {
    if (dates.isEmpty) {
      return Center(child: Text('Kayıt bulunamadı.'));
    }
    return ListView.builder(
      itemCount: dates.length,
      padding: EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final d = dates[index];
        return Card(
          child: ListTile(
            leading: Icon(Icons.calendar_today, color: color),
            title: Text(DateFormat('dd MMMM yyyy, EEEE', 'tr_TR').format(d)),
          ),
        );
      },
    );
  }
}
