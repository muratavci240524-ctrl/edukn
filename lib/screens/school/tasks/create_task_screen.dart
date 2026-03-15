import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class CreateTaskScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const CreateTaskScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _recurrence = 'none';

  List<Map<String, dynamic>> _selectedUsers = [];
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Yeni Görev',
          style: TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title Input
                      TextFormField(
                        controller: _titleController,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Ne yapılması gerekiyor?',
                          hintStyle: TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        validator: (val) => val == null || val.isEmpty
                            ? 'Lütfen bir başlık girin'
                            : null,
                      ),

                      const SizedBox(height: 16),

                      // Description Input
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: TextFormField(
                          controller: _descController,
                          maxLines: 4,
                          minLines: 2,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF334155),
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Detaylı açıklama ekleyin (opsiyonel)',
                            hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                            border: InputBorder.none,
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),
                      const Text(
                        'AYARLAR',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Deadline Picker
                      _buildSettingItem(
                        icon: Icons.calendar_today_rounded,
                        color: const Color(0xFF3B82F6), // Blue
                        title: 'Son Tarih',
                        value: _formatDateTime(),
                        onTap: _pickDateTime,
                        hasClear: _selectedDate != null,
                        onClear: () {
                          setState(() {
                            _selectedDate = null;
                            _selectedTime = null;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      // Recurrence
                      _buildSettingItem(
                        icon: Icons.repeat_rounded,
                        color: const Color(0xFF8B5CF6), // Violet
                        title: 'Tekrarlama',
                        value: _getRecurrenceLabel(
                          _recurrence,
                        ), // TODO: Map to meaningful text
                        onTap: _showRecurrenceSheet,
                      ),

                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'GÖREV ATANANLAR',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          if (_selectedUsers.isNotEmpty)
                            Text(
                              '${_selectedUsers.length} kişi',
                              style: const TextStyle(
                                color: Color(0xFF4F46E5),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Assignees Section
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          // Add Button
                          InkWell(
                            onTap: _showUserSelectionDialog,
                            borderRadius: BorderRadius.circular(30),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFF4F46E5),
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(30),
                                color: const Color(0xFFEEF2FF),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.add,
                                    size: 20,
                                    color: Color(0xFF4F46E5),
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Kişi Ekle',
                                    style: TextStyle(
                                      color: Color(0xFF4F46E5),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Self Assign Button
                          if (!_selectedUsers.any(
                            (u) =>
                                u['id'] ==
                                FirebaseAuth.instance.currentUser?.uid,
                          ))
                            InkWell(
                              onTap: _assignToSelf,
                              borderRadius: BorderRadius.circular(30),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                  borderRadius: BorderRadius.circular(30),
                                  color: Colors.white,
                                ),
                                child: const Text(
                                  'Bana Ata',
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),

                          // Selected Users Chips
                          ..._selectedUsers.map(
                            (user) => Container(
                              padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x08000000),
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: const Color(0xFFE0E7FF),
                                    child: Text(
                                      (user['fullName'] ?? '?')[0]
                                          .toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF4F46E5),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    user['fullName'] ?? 'İsimsiz',
                                    style: const TextStyle(
                                      color: Color(0xFF334155),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _selectedUsers.removeWhere(
                                          (u) => u['id'] == user['id'],
                                        );
                                      });
                                    },
                                    child: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Action Bar
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveTask,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Görevi Oluştur',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required VoidCallback onTap,
    bool hasClear = false,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (hasClear && onClear != null)
              IconButton(
                onPressed: onClear,
                icon: const Icon(
                  Icons.close,
                  color: Color(0xFF94A3B8),
                  size: 18,
                ),
              )
            else
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: Color(0xFFCBD5E1),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime() {
    if (_selectedDate == null) return 'Tarih Seçiniz';
    final dateStr = DateFormat('dd MMM yyyy', 'tr_TR').format(_selectedDate!);
    final timeStr = _selectedTime != null
        ? _selectedTime!.format(context)
        : '23:59';
    return '$dateStr, $timeStr';
  }

  String _getRecurrenceLabel(String code) {
    switch (code) {
      case 'none':
        return 'Tekrarlama Yok';
      case 'daily':
        return 'Her Gün';
      case 'weekly':
        return 'Her Hafta';
      case 'monthly':
        return 'Her Ay';
      default:
        return 'Tekrarlama Yok';
    }
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF4F46E5)),
          ),
          child: child!,
        );
      },
    );

    if (date != null) {
      if (!mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: _selectedTime ?? TimeOfDay.now(),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(primary: Color(0xFF4F46E5)),
            ),
            child: child!,
          );
        },
      );

      setState(() {
        _selectedDate = date;
        _selectedTime = time;
      });
    }
  }

  void _showRecurrenceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tekrarlama Seçenekleri',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildRecurrenceOption(
              'none',
              'Tekrarlama Yok',
              Icons.do_not_disturb,
            ),
            _buildRecurrenceOption('daily', 'Her Gün', Icons.today),
            _buildRecurrenceOption('weekly', 'Her Hafta', Icons.date_range),
            _buildRecurrenceOption('monthly', 'Her Ay', Icons.calendar_month),
          ],
        ),
      ),
    );
  }

  Widget _buildRecurrenceOption(String code, String label, IconData icon) {
    final isSelected = _recurrence == code;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEEF2FF) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: isSelected ? const Color(0xFF4F46E5) : Colors.grey,
        ),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? const Color(0xFF4F46E5) : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check, color: Color(0xFF4F46E5))
          : null,
      onTap: () {
        setState(() => _recurrence = code);
        Navigator.pop(context);
      },
    );
  }

  void _assignToSelf() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance.collection('users').doc(user.uid).get().then((
        doc,
      ) {
        if (doc.exists) {
          final data = doc.data()!;
          data['id'] = doc.id;
          setState(() {
            if (!_selectedUsers.any((u) => u['id'] == data['id'])) {
              _selectedUsers.add(data);
            }
          });
        }
      });
    }
  }

  Future<void> _showUserSelectionDialog() async {
    final staffSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('type', whereIn: ['teacher', 'staff'])
        .get();

    final allUsers = staffSnapshot.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // String searchQuery = ''; // Removed unused variable

            // Filter logic inside builder needs to be reactive if we added a search field
            // But for simplicity let's just show list.
            // Better: use a proper stateful widget or draggablescrollablesheet

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.9,
              expand: false,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      height: 4,
                      width: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Kişi Seç',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: allUsers.length,
                        itemBuilder: (context, i) {
                          final user = allUsers[i];
                          final isSelected = _selectedUsers.any(
                            (u) => u['id'] == user['id'],
                          );

                          return CheckboxListTile(
                            activeColor: const Color(0xFF4F46E5),
                            secondary: CircleAvatar(
                              backgroundColor: const Color(0xFFE0E7FF),
                              child: Text(
                                (user['fullName'] ?? '?')[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Color(0xFF4F46E5),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(user['fullName'] ?? 'Unknown'),
                            subtitle: Text(_formatRole(user['type'])),
                            value: isSelected,
                            onChanged: (checked) {
                              setModalState(() {});
                              setState(() {
                                // Update main screen state
                                if (checked == true) {
                                  _selectedUsers.add(user);
                                } else {
                                  _selectedUsers.removeWhere(
                                    (u) => u['id'] == user['id'],
                                  );
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Tamamla',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatRole(String? role) {
    if (role == 'teacher') return 'Öğretmen';
    if (role == 'staff') return 'Personel';
    return role ?? '';
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir kişi seçin')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;

      // Calculate Deadline
      DateTime? deadline;
      if (_selectedDate != null) {
        deadline = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          _selectedTime?.hour ?? 23,
          _selectedTime?.minute ?? 59,
        );
      }

      final assigneeIds = _selectedUsers.map((u) => u['id'] as String).toList();
      final assigneeNames = {
        for (var u in _selectedUsers)
          (u['id'] as String): (u['fullName'] ?? 'Unknown').toString(),
      };

      await FirebaseFirestore.instance.collection('tasks').add({
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'institutionId': widget.institutionId,
        'schoolTypeId': widget.schoolTypeId,
        'creatorId': user.uid,
        'creatorName': _selectedUsers.any((u) => u['id'] == user.uid)
            ? _selectedUsers.firstWhere((u) => u['id'] == user.uid)['fullName']
            : (user.email ?? 'Admin'),
        'createdAt': FieldValue.serverTimestamp(),
        'deadline': deadline != null ? Timestamp.fromDate(deadline) : null,
        'recurrence': _recurrence,
        'assigneeIds': assigneeIds,
        'assigneeNames': assigneeNames,
        'completedBy': [],
        'isArchived': false,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Görev başarıyla oluşturuldu')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
