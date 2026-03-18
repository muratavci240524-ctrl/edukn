import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../services/attendance_service.dart';

class ManualAttendanceScreen extends StatefulWidget {
  final String institutionId;
  final List<Map<String, dynamic>> initialStaff;

  const ManualAttendanceScreen({
    super.key,
    required this.institutionId,
    required this.initialStaff,
  });

  @override
  State<ManualAttendanceScreen> createState() => _ManualAttendanceScreenState();
}

class _ManualAttendanceScreenState extends State<ManualAttendanceScreen> {
  final AttendanceService _service = AttendanceService();
  String? _selectedUserId;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _checkInTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay? _checkOutTime;
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  bool _isSaving = false;

  late List<Map<String, dynamic>> _filteredStaff;

  @override
  void initState() {
    super.initState();
    _filteredStaff = widget.initialStaff;
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    setState(() {
      _filteredStaff = widget.initialStaff.where((s) {
        final name = (s['fullName'] ?? "${s['firstName']} ${s['lastName']}").toString().toLowerCase();
        return name.contains(_searchController.text.toLowerCase());
      }).toList();
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _selectTime(bool isCheckIn) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isCheckIn ? _checkInTime : (_checkOutTime ?? const TimeOfDay(hour: 17, minute: 0)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF6366F1)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isCheckIn) {
          _checkInTime = picked;
        } else {
          _checkOutTime = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_selectedUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen bir personel seçin')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final checkInDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _checkInTime.hour,
        _checkInTime.minute,
      );

      DateTime? checkOutDateTime;
      if (_checkOutTime != null) {
        checkOutDateTime = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          _checkOutTime!.hour,
          _checkOutTime!.minute,
        );
      }

      await _service.addManualEntry(
        userId: _selectedUserId!,
        institutionId: widget.institutionId,
        date: _selectedDate,
        checkIn: checkInDateTime,
        checkOut: checkOutDateTime,
        note: _noteController.text,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.green, content: Text('✅ Kayıt başarıyla eklendi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Manuel Giriş Ekle', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF1E293B),
      ),
      body: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Header
            const Text('PERSONEL SEÇİMİ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF6366F1), letterSpacing: 1.2)),
            const SizedBox(height: 12),
            
            // Search & Select Staff - Make this flexible
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'Personel Ara...',
                          filled: false, // Make transparent to show white container
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          icon: Icon(Icons.search_rounded, color: Color(0xFF94A3B8)),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _filteredStaff.length,
                        itemBuilder: (context, index) {
                          final staff = _filteredStaff[index];
                          final isSelected = _selectedUserId == staff['id'];
                          return ListTile(
                            onTap: () => setState(() => _selectedUserId = staff['id']),
                            leading: CircleAvatar(
                              backgroundColor: isSelected ? const Color(0xFF6366F1) : const Color(0xFFF1F5F9),
                              child: Text(
                                (staff['fullName'] ?? staff['firstName'])[0].toUpperCase(),
                                style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF6366F1), fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(
                              staff['fullName'] ?? "${staff['firstName']} ${staff['lastName']}",
                              style: TextStyle(fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600, fontSize: 14),
                            ),
                            subtitle: Text(staff['department'] ?? 'Departman Yok', style: const TextStyle(fontSize: 12)),
                            trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: Color(0xFF6366F1)) : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            const Text('GİRİŞ DETAYLARI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF6366F1), letterSpacing: 1.2)),
            const SizedBox(height: 12),
            
            // Bottom Group: Fixed size layout
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Date Picker Card
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16), // Match container radius
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        builder: (context, child) => Theme(
                          data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF6366F1))),
                          child: child!,
                        ),
                      );
                      if (picked != null) setState(() => _selectedDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 20, color: Color(0xFF6366F1)),
                          const SizedBox(width: 12),
                          Text(DateFormat('d MMMM yyyy', 'tr_TR').format(_selectedDate), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                          const Spacer(),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF94A3B8)),
                        ],
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 10),
                
                // Time Pickers
                Row(
                  children: [
                    Expanded(
                      child: _buildTimeSelector(
                        label: 'Giriş',
                        time: _checkInTime,
                        onTap: () => _selectTime(true),
                        icon: Icons.login_rounded,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildTimeSelector(
                        label: 'Çıkış',
                        time: _checkOutTime,
                        onTap: () => _selectTime(false),
                        icon: Icons.logout_rounded,
                        color: const Color(0xFF64748B),
                        isOptional: true,
                        onClear: () => setState(() => _checkOutTime = null),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 10),
                
                // Note Field
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: TextField(
                    controller: _noteController,
                    maxLines: 1,
                    decoration: const InputDecoration(
                      hintText: 'Not ekle...',
                      filled: false, // Make transparent
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      hintStyle: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Save Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isSaving 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('KAYDI TAMAMLA', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeSelector({
    required String label,
    TimeOfDay? time,
    required VoidCallback onTap,
    required IconData icon,
    required Color color,
    bool isOptional = false,
    VoidCallback? onClear,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 6),
                  Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                  if (isOptional && time != null) ...[
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        onClear?.call();
                      },
                      child: const Icon(Icons.cancel_rounded, size: 16, color: Colors.red),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                time?.format(context) ?? 'Seçilmedi',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: time == null ? const Color(0xFFCBD5E1) : const Color(0xFF1E293B)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
