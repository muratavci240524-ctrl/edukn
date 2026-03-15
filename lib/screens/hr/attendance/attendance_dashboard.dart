import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../services/attendance_service.dart';

class AttendanceDashboard extends StatefulWidget {
  const AttendanceDashboard({super.key});

  @override
  State<AttendanceDashboard> createState() => _AttendanceDashboardState();
}

class _AttendanceDashboardState extends State<AttendanceDashboard> with SingleTickerProviderStateMixin {
  final AttendanceService _service = AttendanceService();
  late TabController _tabController;

  // Tab 1: Daily
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _dailyRecords = [];
  List<Map<String, dynamic>> _allStaff = [];
  bool _loadingDaily = true;

  // Tab 2: History
  DateTime _historyStart = DateTime.now().subtract(const Duration(days: 30));
  DateTime _historyEnd = DateTime.now();
  List<Map<String, dynamic>> _historyRecords = [];
  bool _loadingHistory = false;
  String? _selectedStaffId; // Filter by staff

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadStaffAndDaily();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStaffAndDaily() async {
    setState(() => _loadingDaily = true);
    try {
      // 1. Tüm personeli çek
      final staffQuery = await FirebaseFirestore.instance.collection('users').get();
      _allStaff = staffQuery.docs.map((e) {
        final data = e.data();
        data['id'] = e.id;
        return data;
      }).toList();

      // 2. Seçili tarihteki kayıtları çek
      await _loadDailyRecords();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      setState(() => _loadingDaily = false);
    }
  }

  Future<void> _loadDailyRecords() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final records = await _service.getAttendanceForDate(dateStr);
    setState(() => _dailyRecords = records);
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final records = await _service.getHistory(
        startDate: _historyStart,
        endDate: _historyEnd,
        userId: _selectedStaffId,
      );
      setState(() => _historyRecords = records);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      setState(() => _loadingHistory = false);
    }
  }

  // Helper to find staff name
  String _getStaffName(String userId) {
    final staff = _allStaff.firstWhere((s) => s['id'] == userId, orElse: () => {});
    if (staff.isNotEmpty) {
      return "${staff['firstName']} ${staff['lastName']}";
    }
    return "Bilinmeyen Personel";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Puantaj Yönetimi'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Günlük Durum'),
            Tab(text: 'Geçmiş Kayıtlar (Arşiv)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDailyTab(),
          _buildHistoryTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showManualEntryDialog,
        child: const Icon(Icons.add),
        tooltip: 'Manuel Kayıt Ekle',
      ),
    );
  }

  // --- TAB 1: GÜNLÜK DURUM ---
  Widget _buildDailyTab() {
    if (_loadingDaily) return const Center(child: CircularProgressIndicator());

    // Merge staff with attendance
    final List<Map<String, dynamic>> combinedList = [];
    
    for (var staff in _allStaff) {
      final attendance = _dailyRecords.firstWhere(
        (r) => r['userId'] == staff['id'],
        orElse: () => {},
      );
      
      combinedList.add({
        'staff': staff,
        'attendance': attendance.isNotEmpty ? attendance : null,
      });
    }

    // İstatistikler
    final total = _allStaff.length;
    final present = _dailyRecords.length;
    final absent = total - present;

    return Column(
      children: [
        // Tarih Seçici ve Özet
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.indigo.shade50,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: () {
                      setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
                      _loadDailyRecords();
                    },
                  ),
                  Text(
                    DateFormat('d MMMM yyyy').format(_selectedDate),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios),
                    onPressed: () {
                      setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
                      _loadDailyRecords();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatCard('Toplam', total.toString(), Colors.blue),
                  _buildStatCard('Gelen', present.toString(), Colors.green),
                  _buildStatCard('Gelmeyen', absent.toString(), Colors.red),
                ],
              ),
            ],
          ),
        ),
        
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: combinedList.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final item = combinedList[index];
              final staff = item['staff'];
              final attendance = item['attendance'];
              final hasRecord = attendance != null;
              
              String statusText = 'Gelmedi';
              Color statusColor = Colors.red;
              String timeText = '-';

              if (hasRecord) {
                statusText = 'Geldi';
                statusColor = Colors.green;
                final checkIn = (attendance['checkIn'] as Timestamp).toDate();
                timeText = DateFormat('HH:mm').format(checkIn);
                
                if (attendance['checkOut'] != null) {
                  final checkOut = (attendance['checkOut'] as Timestamp).toDate();
                  timeText += " - ${DateFormat('HH:mm').format(checkOut)}";
                  statusText = 'Tamamlandı';
                  statusColor = Colors.grey;
                }
              }

              return ListTile(
                onTap: hasRecord ? () => _showEditEntryDialog(attendance, "${staff['firstName']} ${staff['lastName']}") : null,
                leading: CircleAvatar(
                  backgroundColor: Colors.indigo.shade100,
                  child: Text(
                    (staff['firstName'] ?? 'A').toString()[0].toUpperCase() + 
                    (staff['lastName'] ?? 'B').toString()[0].toUpperCase()
                  ),
                ),
                title: Text("${staff['firstName']} ${staff['lastName']}"),
                subtitle: Text(staff['department'] ?? 'Departman Yok'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(timeText, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(color: Colors.grey.shade600)),
      ],
    );
  }

  // --- DIALOGS ---

  Future<void> _showManualEntryDialog() async {
    String? selectedUserId;
    DateTime date = DateTime.now();
    TimeOfDay checkInTime = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay? checkOutTime;
    final noteController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Manuel Kayıt Ekle'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Personel Seçimi
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Personel'),
                    items: _allStaff.map((s) => DropdownMenuItem(
                      value: s['id'] as String,
                      child: Text("${s['firstName']} ${s['lastName']}"),
                    )).toList(),
                    onChanged: (v) => setDialogState(() => selectedUserId = v),
                  ),
                  const SizedBox(height: 12),
                  
                  // Tarih Seçimi
                  ListTile(
                    title: const Text('Tarih'),
                    subtitle: Text(DateFormat('d MMMM yyyy').format(date)),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setDialogState(() => date = picked);
                    },
                  ),
                  
                  // Giriş Saati
                  ListTile(
                    title: const Text('Giriş Saati'),
                    subtitle: Text(checkInTime.format(context)),
                    trailing: const Icon(Icons.access_time),
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: checkInTime);
                      if (picked != null) setDialogState(() => checkInTime = picked);
                    },
                  ),

                  // Çıkış Saati
                  ListTile(
                    title: const Text('Çıkış Saati (Opsiyonel)'),
                    subtitle: Text(checkOutTime?.format(context) ?? 'Seçilmedi'),
                    trailing: IconButton(
                      icon: Icon(checkOutTime == null ? Icons.add_circle_outline : Icons.clear),
                      onPressed: () async {
                        if (checkOutTime == null) {
                          final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 17, minute: 0));
                          if (picked != null) setDialogState(() => checkOutTime = picked);
                        } else {
                          setDialogState(() => checkOutTime = null);
                        }
                      },
                    ),
                  ),

                  // Not
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: 'Not (Opsiyonel)'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
              ElevatedButton(
                onPressed: () async {
                  if (selectedUserId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen personel seçin')));
                    return;
                  }
                  
                  final checkInDateTime = DateTime(date.year, date.month, date.day, checkInTime.hour, checkInTime.minute);
                  DateTime? checkOutDateTime;
                  if (checkOutTime != null) {
                    checkOutDateTime = DateTime(date.year, date.month, date.day, checkOutTime!.hour, checkOutTime!.minute);
                  }

                  try {
                    await _service.addManualEntry(
                      userId: selectedUserId!,
                      date: date,
                      checkIn: checkInDateTime,
                      checkOut: checkOutDateTime,
                      note: noteController.text,
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      _loadDailyRecords(); // Listeyi yenile
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kayıt eklendi')));
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
                  }
                },
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEditEntryDialog(Map<String, dynamic> attendance, String staffName) async {
    final docId = attendance['id'];
    final dateStr = attendance['date'] as String; // YYYY-MM-DD
    final date = DateTime.parse(dateStr);
    
    final checkInTs = attendance['checkIn'] as Timestamp;
    final checkOutTs = attendance['checkOut'] as Timestamp?;
    
    TimeOfDay checkInTime = TimeOfDay.fromDateTime(checkInTs.toDate());
    TimeOfDay? checkOutTime = checkOutTs != null ? TimeOfDay.fromDateTime(checkOutTs.toDate()) : null;
    
    final noteController = TextEditingController(text: attendance['notes'] ?? '');

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Düzenle: $staffName'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Tarih: ${DateFormat('d MMMM yyyy').format(date)}"),
                  const SizedBox(height: 16),
                  
                  // Giriş Saati
                  ListTile(
                    title: const Text('Giriş Saati'),
                    subtitle: Text(checkInTime.format(context)),
                    trailing: const Icon(Icons.access_time),
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: checkInTime);
                      if (picked != null) setDialogState(() => checkInTime = picked);
                    },
                  ),

                  // Çıkış Saati
                  ListTile(
                    title: const Text('Çıkış Saati'),
                    subtitle: Text(checkOutTime?.format(context) ?? 'Yok'),
                    trailing: IconButton(
                      icon: Icon(checkOutTime == null ? Icons.add_circle_outline : Icons.clear),
                      onPressed: () async {
                        if (checkOutTime == null) {
                          final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 17, minute: 0));
                          if (picked != null) setDialogState(() => checkOutTime = picked);
                        } else {
                          setDialogState(() => checkOutTime = null);
                        }
                      },
                    ),
                  ),

                  // Not
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: 'Not'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
              ElevatedButton(
                onPressed: () async {
                  final checkInDateTime = DateTime(date.year, date.month, date.day, checkInTime.hour, checkInTime.minute);
                  DateTime? checkOutDateTime;
                  if (checkOutTime != null) {
                    checkOutDateTime = DateTime(date.year, date.month, date.day, checkOutTime!.hour, checkOutTime!.minute);
                  }

                  try {
                    await _service.updateAttendance(
                      docId: docId,
                      checkIn: checkInDateTime,
                      checkOut: checkOutDateTime,
                      note: noteController.text,
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      _loadDailyRecords(); // Listeyi yenile
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kayıt güncellendi')));
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
                  }
                },
                child: const Text('Güncelle'),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- TAB 2: GEÇMİŞ KAYITLAR (ARŞİV) ---
  Widget _buildHistoryTab() {
    return Column(
      children: [
        // Filtreler
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.indigo.shade50,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange: DateTimeRange(start: _historyStart, end: _historyEnd),
                        );
                        if (picked != null) {
                          setState(() {
                            _historyStart = picked.start;
                            _historyEnd = picked.end;
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Tarih Aralığı',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.date_range),
                        ),
                        child: Text(
                          "${DateFormat('dd.MM.yyyy').format(_historyStart)} - ${DateFormat('dd.MM.yyyy').format(_historyEnd)}",
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Personel Filtrele (Opsiyonel)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      value: _selectedStaffId,
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Tümü'),
                        ),
                        ..._allStaff.map((s) => DropdownMenuItem(
                          value: s['id'] as String,
                          child: Text("${s['firstName']} ${s['lastName']}"),
                        )),
                      ],
                      onChanged: (v) => setState(() => _selectedStaffId = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _loadHistory,
                    icon: const Icon(Icons.search),
                    label: const Text('Getir'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Liste
        Expanded(
          child: _loadingHistory
              ? const Center(child: CircularProgressIndicator())
              : _historyRecords.isEmpty
                  ? const Center(child: Text('Kayıt bulunamadı'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _historyRecords.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final record = _historyRecords[index];
                        final userId = record['userId'] as String;
                        final staffName = _getStaffName(userId);
                        final date = DateTime.parse(record['date']);
                        final checkIn = (record['checkIn'] as Timestamp).toDate();
                        final checkOutTs = record['checkOut'] as Timestamp?;
                        
                        String timeText = DateFormat('HH:mm').format(checkIn);
                        if (checkOutTs != null) {
                          timeText += " - ${DateFormat('HH:mm').format(checkOutTs.toDate())}";
                        }

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.indigo.shade100,
                            child: Text(staffName.isNotEmpty ? staffName[0] : '?'),
                          ),
                          title: Text(staffName),
                          subtitle: Text(DateFormat('d MMMM yyyy, EEEE', 'tr_TR').format(date)),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(timeText, style: const TextStyle(fontWeight: FontWeight.bold)),
                              if (record['notes'] != null && record['notes'].isNotEmpty)
                                Icon(Icons.note, size: 16, color: Colors.grey),
                            ],
                          ),
                          onTap: () => _showEditEntryDialog(record, staffName),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
