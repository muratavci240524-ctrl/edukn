import 'package:flutter/material.dart';
import 'chat_models.dart';

class CreateGroupDialog extends StatefulWidget {
  final List<ChatUser> contacts;

  const CreateGroupDialog({Key? key, required this.contacts}) : super(key: key);

  @override
  State<CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<CreateGroupDialog> {
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  List<ChatUser> _filteredContacts = [];
  List<String> _selectedUserIds = [];

  @override
  void initState() {
    super.initState();
    _filteredContacts = List.from(widget.contacts);
  }

  void _filterContacts(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredContacts = List.from(widget.contacts);
      } else {
        final lower = query.toLowerCase();
        _filteredContacts = widget.contacts.where((u) {
          return u.name.toLowerCase().contains(lower) ||
              (u.role ?? '').toLowerCase().contains(lower);
        }).toList();
      }
    });
  }

  void _createGroup() {
    if (_groupNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Lütfen grup adı giriniz.')));
      return;
    }
    if (_selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir katılımcı seçiniz.')),
      );
      return;
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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 800),
        child: Column(
          mainAxisSize: MainAxisSize.min, // Important for dialog to shrink wrap
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Yeni Grup Oluştur',
                style: const TextStyle(
                  color: Color(0xFF008069),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Group Name Input
                    TextField(
                      controller: _groupNameController,
                      decoration: InputDecoration(
                        labelText: 'Grup Adı',
                        prefixIcon: const Icon(
                          Icons.group,
                          color: Color(0xFF008069),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF008069),
                          ),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Search Input
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Kişilerde ara...',
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.grey,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF008069),
                          ),
                        ),
                      ),
                      onChanged: _filterContacts,
                    ),
                    const SizedBox(height: 16),

                    // Selection Counter
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'KATILIMCILARI SEÇİN (${_selectedUserIds.length})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (_selectedUserIds.isNotEmpty)
                          TextButton(
                            onPressed: () =>
                                setState(() => _selectedUserIds.clear()),
                            child: const Text('Temizle'),
                          ),
                      ],
                    ),

                    // List
                    Container(
                      height: 300, // Constrained height for the list part
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _filteredContacts.isEmpty
                          ? const Center(child: Text('Kişi bulunamadı.'))
                          : ListView.separated(
                              itemCount: _filteredContacts.length,
                              separatorBuilder: (c, i) =>
                                  const Divider(height: 1, indent: 56),
                              itemBuilder: (context, index) {
                                final user = _filteredContacts[index];
                                final isSelected = _selectedUserIds.contains(
                                  user.id,
                                );
                                return CheckboxListTile(
                                  value: isSelected,
                                  activeColor: const Color(0xFF008069),
                                  title: Text(
                                    user.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    user.role ?? '',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  secondary: CircleAvatar(
                                    radius: 18,
                                    backgroundImage: user.avatarUrl != null
                                        ? NetworkImage(user.avatarUrl!)
                                        : null,
                                    backgroundColor: user.userType == 'staff'
                                        ? Colors.orange.shade50
                                        : Colors.blue.shade50,
                                    child: user.avatarUrl == null
                                        ? Text(
                                            user.name[0],
                                            style: TextStyle(
                                              color: user.userType == 'staff'
                                                  ? Colors.orange
                                                  : Colors.blue,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )
                                        : null,
                                  ),
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true)
                                        _selectedUserIds.add(user.id);
                                      else
                                        _selectedUserIds.remove(user.id);
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                    ),
                    child: const Text('İptal'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _createGroup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF008069),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      'OLUŞTUR',
                      style: TextStyle(fontWeight: FontWeight.bold),
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
}
