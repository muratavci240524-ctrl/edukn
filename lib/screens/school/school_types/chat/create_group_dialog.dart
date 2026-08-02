import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'chat_models.dart';

class CreateGroupDialog extends StatefulWidget {
  final List<ChatUser> contacts;
  final Function(String name, List<ChatUser> selectedUsers)? onCreateGroup;

  const CreateGroupDialog({
    Key? key,
    required this.contacts,
    this.onCreateGroup,
  }) : super(key: key);

  @override
  State<CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<CreateGroupDialog> {
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  List<ChatUser> _filteredContacts = [];
  final List<String> _selectedUserIds = [];

  @override
  void initState() {
    super.initState();
    _filteredContacts = List.from(widget.contacts);
  }

  void _filterContacts(String query) {
    setState(() {
      if (query.trim().isEmpty) {
        _filteredContacts = List.from(widget.contacts);
      } else {
        final lower = query.toLowerCase().trim();
        _filteredContacts = widget.contacts.where((u) {
          return u.name.toLowerCase().contains(lower) ||
              (u.role ?? '').toLowerCase().contains(lower);
        }).toList();
      }
    });
  }

  void _createGroup() {
    if (_groupNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen grup adı giriniz.')),
      );
      return;
    }
    if (_selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir katılımcı seçiniz.')),
      );
      return;
    }

    final selectedUsers = widget.contacts
        .where((u) => _selectedUserIds.contains(u.id))
        .toList();

    if (widget.onCreateGroup != null) {
      widget.onCreateGroup!(_groupNameController.text.trim(), selectedUsers);
    }

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "'${_groupNameController.text}' grubu oluşturuldu (${_selectedUserIds.length} üye)",
        ),
        backgroundColor: const Color(0xFF008069),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedUsers = widget.contacts
        .where((u) => _selectedUserIds.contains(u.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Drag indicator handle
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Header Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.group_add_rounded, color: Colors.indigo, size: 22),
                ),
                const SizedBox(width: 10),
                Text(
                  'Yeni Grup Oluştur',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade900,
                  ),
                ),
              ],
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Group Name Input
        TextField(
          controller: _groupNameController,
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Grup Adını Yazın...',
            prefixIcon: const Icon(Icons.group_work_rounded, color: Colors.indigo),
            filled: true,
            fillColor: const Color(0xFFF0F2F5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(height: 12),

        // Contact Search Bar
        TextField(
          controller: _searchController,
          onChanged: _filterContacts,
          style: GoogleFonts.inter(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Kişilerde Ara...',
            prefixIcon: const Icon(Icons.search, color: Colors.grey),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),

        // Selected Members Horizontal Chips
        if (selectedUsers.isNotEmpty) ...[
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: selectedUsers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final u = selectedUsers[index];
                return Chip(
                  avatar: CircleAvatar(
                    backgroundColor: Colors.indigo.shade100,
                    child: Text(
                      u.name.isNotEmpty ? u.name[0].toUpperCase() : 'K',
                      style: const TextStyle(fontSize: 10, color: Colors.indigo, fontWeight: FontWeight.bold),
                    ),
                  ),
                  label: Text(u.name, style: GoogleFonts.inter(fontSize: 12)),
                  deleteIcon: const Icon(Icons.cancel, size: 16, color: Colors.grey),
                  onDeleted: () {
                    setState(() {
                      _selectedUserIds.remove(u.id);
                    });
                  },
                  backgroundColor: Colors.indigo.shade50,
                  side: BorderSide.none,
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Subtitle / Counter Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'KATILIMCILAR (${_selectedUserIds.length} Seçildi)',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
            ),
            if (_selectedUserIds.isNotEmpty)
              TextButton(
                onPressed: () => setState(() => _selectedUserIds.clear()),
                child: const Text('Temizle', style: TextStyle(fontSize: 12, color: Colors.red)),
              ),
          ],
        ),
        const SizedBox(height: 4),

        // Expanded Scrollable Contacts List
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: _filteredContacts.isEmpty
                ? Center(child: Text('Kişi bulunamadı.', style: GoogleFonts.inter(color: Colors.grey)))
                : ListView.separated(
                    itemCount: _filteredContacts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final user = _filteredContacts[index];
                      final isSelected = _selectedUserIds.contains(user.id);
                      return CheckboxListTile(
                        value: isSelected,
                        activeColor: Colors.indigo,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        title: Text(user.name, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text(user.role ?? '', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
                        secondary: CircleAvatar(
                          radius: 18,
                          backgroundColor: user.userType == 'staff' ? Colors.orange.shade100 : Colors.blue.shade100,
                          child: Text(
                            user.name.isNotEmpty ? user.name[0].toUpperCase() : 'K',
                            style: TextStyle(color: user.userType == 'staff' ? Colors.deepOrange : Colors.blue, fontWeight: FontWeight.bold),
                          ),
                        ),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedUserIds.add(user.id);
                            } else {
                              _selectedUserIds.remove(user.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 12),

        // Bottom Action Button
        ElevatedButton.icon(
          onPressed: _createGroup,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
          label: Text(
            'GRUP OLUŞTUR (${_selectedUserIds.length} ÜYE)',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
