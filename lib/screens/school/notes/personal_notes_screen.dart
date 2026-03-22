import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:ui';

class PersonalNotesScreen extends StatefulWidget {
  const PersonalNotesScreen({Key? key}) : super(key: key);

  @override
  _PersonalNotesScreenState createState() => _PersonalNotesScreenState();
}

class _PersonalNotesScreenState extends State<PersonalNotesScreen> {
  final user = FirebaseAuth.instance.currentUser;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  DateTime? _reminderDate;
  TimeOfDay? _reminderTime;
  String _selectedCategory = 'Genel';
  Color _selectedColor = Colors.indigo;

  final List<Map<String, dynamic>> _categories = [
    {'name': 'Genel', 'color': Colors.indigo},
    {'name': 'Toplantı', 'color': Colors.purple},
    {'name': 'Önemli', 'color': Colors.red},
    {'name': 'Fikir', 'color': Colors.teal},
    {'name': 'Yapılacak', 'color': Colors.orange},
  ];

  @override
  Widget build(BuildContext context) {
    if (user == null) return const Scaffold(body: Center(child: Text('Giriş yapmanız gerekiyor.')));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text('Notlarım', style: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.w900, fontSize: 20)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.indigo),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.blueGrey),
            onPressed: () {},
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .collection('personal_notes')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Bir hata oluştu.'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final notes = snapshot.data!.docs;

          if (notes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Icon(Icons.note_alt_outlined, size: 80, color: Colors.grey.shade300),
                   const SizedBox(height: 16),
                   const Text('Henüz hiç not eklememişsiniz.', style: TextStyle(color: Colors.blueGrey, fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index].data() as Map<String, dynamic>;
              final docId = notes[index].id;
              final Color color = Color(note['color'] ?? Colors.indigo.value);
              final reminder = note['reminder'] as Timestamp?;
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Dismissible(
                  key: Key(docId),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)),
                    child: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  onDismissed: (_) {
                    FirebaseFirestore.instance
                        .collection('users')
                        .doc(user!.uid)
                        .collection('personal_notes')
                        .doc(docId)
                        .delete();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            Container(width: 6, color: color),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          note['category'] ?? 'Genel',
                                          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                                        ),
                                        if (reminder != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                                            child: Row(
                                              children: [
                                                Icon(Icons.alarm, size: 10, color: Colors.orange.shade800),
                                                const SizedBox(width: 4),
                                                Text(
                                                  DateFormat('dd MMM, HH:mm').format(reminder.toDate()),
                                                  style: TextStyle(color: Colors.orange.shade800, fontSize: 9, fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      note['title'] ?? 'Başlıksız',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      note['content'] ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade600, height: 1.5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddNoteDialog(),
        backgroundColor: Colors.indigo,
        elevation: 4,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Yeni Not', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }

  void _showAddNoteDialog() {
    _titleController.clear();
    _contentController.clear();
    _reminderDate = null;
    _reminderTime = null;
    _selectedCategory = 'Genel';
    _selectedColor = Colors.indigo;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
          padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 24),
              const Text('Yeni Hatırlatıcı Not', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
              const SizedBox(height: 24),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: 'Başlık',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contentController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Notunuzu yazın...',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Kategori', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final isSelected = _selectedCategory == cat['name'];
                    return InkWell(
                      onTap: () => setModalState(() { _selectedCategory = cat['name']; _selectedColor = cat['color']; }),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: isSelected ? cat['color'] : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: isSelected ? cat['color'] : Colors.grey.shade300),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          cat['name'],
                          style: TextStyle(color: isSelected ? Colors.white : Colors.blueGrey, fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2101));
                        if (picked != null) setModalState(() => _reminderDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.amber.shade200)),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, size: 18, color: Colors.amber.shade800),
                            const SizedBox(width: 8),
                            Text(_reminderDate == null ? 'Tarih Seç' : DateFormat('dd.MM.yyyy').format(_reminderDate!), style: TextStyle(color: Colors.amber.shade800, fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                        if (picked != null) setModalState(() => _reminderTime = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.blue.shade200)),
                        child: Row(
                          children: [
                            Icon(Icons.access_time, size: 18, color: Colors.blue.shade800),
                            const SizedBox(width: 8),
                            Text(_reminderTime == null ? 'Saat Seç' : _reminderTime!.format(context), style: TextStyle(color: Colors.blue.shade800, fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _saveNote(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('HATIRLATICI KAYDET', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveNote() async {
    if (_titleController.text.isEmpty) return;

    DateTime? reminderDateTime;
    if (_reminderDate != null && _reminderTime != null) {
      reminderDateTime = DateTime(_reminderDate!.year, _reminderDate!.month, _reminderDate!.day, _reminderTime!.hour, _reminderTime!.minute);
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('personal_notes')
        .add({
      'title': _titleController.text,
      'content': _contentController.text,
      'category': _selectedCategory,
      'color': _selectedColor.value,
      'reminder': reminderDateTime != null ? Timestamp.fromDate(reminderDateTime) : null,
      'createdAt': FieldValue.serverTimestamp(),
      'isCompleted': false,
    });

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not başarıyla kaydedildi!')));
  }
}
