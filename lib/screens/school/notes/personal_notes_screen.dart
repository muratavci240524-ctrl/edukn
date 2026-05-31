import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';

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
  bool _showTitleError = false;

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
                  confirmDismiss: (direction) async {
                    return await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Notu Sil'),
                        content: const Text('Bu notu silmek istediğinize emin misiniz?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('İptal'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Sil', style: const TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
                  onDismissed: (_) {
                    FirebaseFirestore.instance
                        .collection('users')
                        .doc(user!.uid)
                        .collection('personal_notes')
                        .doc(docId)
                        .delete();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Not silindi!')),
                    );
                  },
                  child: InkWell(
                    onTap: () => _showNoteModal(note: note, docId: docId),
                    borderRadius: BorderRadius.circular(20),
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
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNoteModal(),
        backgroundColor: Colors.indigo,
        elevation: 4,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Yeni Not', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }

  void _showNoteModal({Map<String, dynamic>? note, String? docId}) {
    if (note != null && docId != null) {
      // Edit mode: pre-fill controllers
      _titleController.text = note['title'] ?? '';
      _contentController.text = note['content'] ?? '';
      _selectedCategory = note['category'] ?? 'Genel';
      _selectedColor = Color(note['color'] ?? Colors.indigo.value);
      
      final Timestamp? reminderTimestamp = note['reminder'] as Timestamp?;
      if (reminderTimestamp != null) {
        final dateTime = reminderTimestamp.toDate();
        _reminderDate = dateTime;
        _reminderTime = TimeOfDay.fromDateTime(dateTime);
      } else {
        _reminderDate = null;
        _reminderTime = null;
      }
    } else {
      // Create mode: clear controllers
      _titleController.clear();
      _contentController.clear();
      _reminderDate = null;
      _reminderTime = null;
      _selectedCategory = 'Genel';
      _selectedColor = Colors.indigo;
    }

    _showTitleError = false;

    final isWeb = MediaQuery.of(context).size.width >= 1150;

    if (isWeb) {
      // Web: Beautiful centered dialog
      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 16,
          backgroundColor: Colors.white,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(32),
            child: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setModalState) => _buildNoteFormFields(setModalState, context, docId: docId, isWeb: true),
              ),
            ),
          ),
        ),
      );
    } else {
      // Mobile: Full-screen Page/Dialog
      Navigator.push(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.indigo),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(docId == null ? 'Yeni Not' : 'Notu Düzenle', style: GoogleFonts.inter(color: Colors.indigo.shade900, fontWeight: FontWeight.bold)),
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: StatefulBuilder(
                  builder: (context, setModalState) => _buildNoteFormFields(setModalState, context, docId: docId, isWeb: false),
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildNoteFormFields(StateSetter setModalState, BuildContext context, {String? docId, required bool isWeb}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isWeb) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                docId == null ? 'Yeni Hatırlatıcı Not' : 'Notu Düzenle', 
                style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900, color: const Color(0xFF1E293B)),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.blueGrey),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
        TextField(
          controller: _titleController,
          decoration: InputDecoration(
            hintText: 'Başlık',
            errorText: _showTitleError ? 'Başlık alanı boş bırakılamaz.' : null,
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.indigo, width: 2),
            ),
          ),
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
          onChanged: (val) {
            if (_showTitleError && val.trim().isNotEmpty) {
              setModalState(() {
                _showTitleError = false;
              });
            }
          },
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
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.indigo, width: 2),
            ),
          ),
          style: GoogleFonts.inter(),
        ),
        const SizedBox(height: 20),
        Text('Kategori', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
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
                    style: GoogleFonts.inter(color: isSelected ? Colors.white : Colors.blueGrey, fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Hatırlatıcı (İsteğe Bağlı)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            if (_reminderDate != null || _reminderTime != null)
              TextButton.icon(
                icon: const Icon(Icons.clear_rounded, size: 14, color: Colors.red),
                label: Text('Kaldır', style: GoogleFonts.inter(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                onPressed: () {
                  setModalState(() {
                    _reminderDate = null;
                    _reminderTime = null;
                  });
                },
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context, 
                    initialDate: _reminderDate ?? DateTime.now(), 
                    firstDate: DateTime.now(), 
                    lastDate: DateTime(2101),
                  );
                  if (picked != null) setModalState(() => _reminderDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.amber.shade200)),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, size: 18, color: Colors.amber.shade800),
                      const SizedBox(width: 8),
                      Text(_reminderDate == null ? 'Tarih Seç' : DateFormat('dd.MM.yyyy').format(_reminderDate!), style: GoogleFonts.inter(color: Colors.amber.shade800, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context, 
                    initialTime: _reminderTime ?? TimeOfDay.now(),
                  );
                  if (picked != null) setModalState(() => _reminderTime = picked);
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.blue.shade200)),
                  child: Row(
                    children: [
                      Icon(Icons.access_time, size: 18, color: Colors.blue.shade800),
                      const SizedBox(width: 8),
                      Text(_reminderTime == null ? 'Saat Seç' : _reminderTime!.format(context), style: GoogleFonts.inter(color: Colors.blue.shade800, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            if (docId != null) ...[
              ElevatedButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Notu Sil'),
                      content: const Text('Bu notu silmek istediğinize emin misiniz?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil', style: const TextStyle(color: Colors.red))),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(user!.uid)
                        .collection('personal_notes')
                        .doc(docId)
                        .delete();
                    Navigator.pop(context); // Close form
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not silindi!')));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade50,
                  foregroundColor: Colors.red,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.red.shade200)),
                ),
                child: const Icon(Icons.delete_outline),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: ElevatedButton(
                onPressed: () => _saveOrUpdateNote(docId: docId, setModalState: setModalState),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  docId == null ? 'HATIRLATICI KAYDET' : 'GÜNCELLE', 
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _saveOrUpdateNote({String? docId, required StateSetter setModalState}) async {
    if (_titleController.text.trim().isEmpty) {
      setModalState(() {
        _showTitleError = true;
      });
      return;
    }

    DateTime? reminderDateTime;
    if (_reminderDate != null && _reminderTime != null) {
      reminderDateTime = DateTime(_reminderDate!.year, _reminderDate!.month, _reminderDate!.day, _reminderTime!.hour, _reminderTime!.minute);
    }

    final data = {
      'title': _titleController.text.trim(),
      'content': _contentController.text.trim(),
      'category': _selectedCategory,
      'color': _selectedColor.value,
      'reminder': reminderDateTime != null ? Timestamp.fromDate(reminderDateTime) : null,
      'isCompleted': false,
    };

    if (docId == null) {
      // Add new note
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('personal_notes')
          .add({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not başarıyla kaydedildi!')));
    } else {
      // Update existing note
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('personal_notes')
          .doc(docId)
          .update(data);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not başarıyla güncellendi!')));
    }

    Navigator.pop(context);
  }
}
