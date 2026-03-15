import 'package:flutter/material.dart';
import 'chat_models.dart';

class BulkMessageDialog extends StatefulWidget {
  final List<ChatUser> contacts;
  const BulkMessageDialog({Key? key, required this.contacts}) : super(key: key);

  @override
  State<BulkMessageDialog> createState() => _BulkMessageDialogState();
}

class _BulkMessageDialogState extends State<BulkMessageDialog> {
  final TextEditingController messageController = TextEditingController();
  final TextEditingController searchController = TextEditingController();

  // 0: Kişi, 1: Sınıf, 2: Şube
  int _selectedType = 0;

  // Data
  List<ChatUser> _filteredContacts = [];
  List<String> _uniqueClasses = [];
  List<String> _uniqueBranches = [];

  // Selections
  List<String> _selectedUserIds = [];
  List<String> _selectedClasses = [];
  List<String> _selectedBranches = [];

  // Target Audiences
  bool _sendToStudent = false;
  bool _sendToTeacher = false;
  bool _sendToParent = false;

  @override
  void initState() {
    super.initState();
    _filteredContacts = List.from(widget.contacts);
    _extractClassesAndBranches();
  }

  void _extractClassesAndBranches() {
    // Determine branches from students
    // Assuming role/className holds the branch info like "801", "8-A", etc.
    final branches = widget.contacts
        .where((u) => u.userType == 'student' && u.role != null)
        .map((u) => u.role!)
        .toSet()
        .toList();
    branches.sort();
    _uniqueBranches = branches;

    // Determine classes from branches
    final classes = <String>{};
    for (var b in branches) {
      String? level;
      // 1. Try format like "12-A" or "9/B" (digits followed by separator)
      final matchSeparator = RegExp(r'^(\d+)[-/]').firstMatch(b);
      if (matchSeparator != null) {
        level = matchSeparator.group(1);
      } else {
        // 2. Try formats like "801", "502", "1201"
        // If length is 3, typical for primary/middle (e.g. 501 -> 5, 801 -> 8)
        // If length is 4, typical for high school (e.g. 1001 -> 10, 1202 -> 12)
        final matchAdhoc = RegExp(r'^(\d+)').firstMatch(b);
        if (matchAdhoc != null) {
          String raw = matchAdhoc.group(1)!;
          if (raw.length == 3) {
            level = raw.substring(0, 1);
          } else if (raw.length == 4) {
            level = raw.substring(0, 2);
          } else {
            // fallback: just take it all or try reasonable split
            level = raw;
          }
        }
      }

      if (level != null && level.isNotEmpty) {
        classes.add(level);
      }
    }

    _uniqueClasses = classes.toList()
      ..sort((a, b) {
        int? iA = int.tryParse(a);
        int? iB = int.tryParse(b);
        if (iA != null && iB != null) return iA.compareTo(iB);
        return a.compareTo(b);
      });

    if (_uniqueClasses.isEmpty) {
      // Mock data if no students found
      _uniqueClasses = ['5', '6', '7', '8'];
    }
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Toplu Mesaj Gönder',
                style: const TextStyle(
                  color: Color(0xFF008069),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Type Selector
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          _buildTypeOption('Kişi Seç', 0),
                          _buildTypeOption('Sınıf Seviyesi Seç', 1),
                          _buildTypeOption('Şube Seç', 2),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Message Input
                    TextField(
                      controller: messageController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Mesajınız',
                        labelStyle: TextStyle(color: Colors.grey.shade600),
                        hintText: 'İletilecek mesaj...',
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

                    // Content based on Selection
                    if (_selectedType == 0) _buildPersonSelector(),
                    if (_selectedType == 1) _buildClassSelector(),
                    if (_selectedType == 2) _buildBranchSelector(),
                  ],
                ),
              ),
            ),

            // Footer Actions
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
                    onPressed: _sendMessage,
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
                      'GÖNDER',
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

  Widget _buildTypeOption(String label, int index) {
    final isSelected = _selectedType == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedType = index;
            // Clear selections when switching (optional, but cleaner)
            // _selectedUserIds.clear(); // Keep separate selections? Maybe.
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected
                  ? const Color(0xFF008069)
                  : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPersonSelector() {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              hintText: 'Kişi ara...',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF008069)),
              ),
            ),
            onChanged: _filterContacts,
          ),
          const SizedBox(height: 10),
          Container(
            height: 44,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6), // Softer grey for track
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: const Color(0xFF008069),
              unselectedLabelColor: Colors.grey.shade500,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
              tabs: const [
                Tab(text: 'PERSONEL'),
                Tab(text: 'ÖĞRENCİ'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'KİŞİ SEÇİMİ (${_selectedUserIds.length})',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    // Toggle select all based on current filter context is tricky with tabs
                    // Better to just Clear All or Select All Visible
                    // For simplicity, let's keep it as Clear/Select All filtered
                    if (_selectedUserIds.length > 0) {
                      _selectedUserIds.clear();
                    } else {
                      _selectedUserIds = _filteredContacts
                          .map((u) => u.id)
                          .toList();
                    }
                  });
                },
                child: Text(
                  _selectedUserIds.isNotEmpty
                      ? 'Tümünü Kaldır'
                      : 'Görünenleri Seç',
                ),
              ),
            ],
          ),
          Container(
            height: 250, // Fixed height
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TabBarView(
              children: [
                _buildContactList(
                  _filteredContacts
                      .where((u) => u.userType == 'staff')
                      .toList(),
                ),
                _buildContactList(
                  _filteredContacts
                      .where((u) => u.userType == 'student')
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactList(List<ChatUser> contacts) {
    if (contacts.isEmpty) {
      return const Center(child: Text('Kişi bulunamadı.'));
    }
    return ListView.separated(
      itemCount: contacts.length,
      separatorBuilder: (c, i) => const Divider(height: 1, indent: 50),
      itemBuilder: (context, index) {
        final user = contacts[index];
        final isSelected = _selectedUserIds.contains(user.id);
        return CheckboxListTile(
          value: isSelected,
          title: Text(
            user.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          subtitle: Text(
            user.role ?? '',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          activeColor: const Color(0xFF008069),
          dense: true,
          secondary: CircleAvatar(
            backgroundImage: user.avatarUrl != null
                ? NetworkImage(user.avatarUrl!)
                : null,
            radius: 16,
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
    );
  }

  Widget _buildClassSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SINIF SEVİYESİ SEÇİN',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _uniqueClasses.map((cls) {
            final isSelected = _selectedClasses.contains(cls);
            return FilterChip(
              showCheckmark: false,
              label: Text('$cls. Sınıf'),
              selected: isSelected,
              selectedColor: const Color(0xFF008069).withOpacity(0.15),
              labelStyle: TextStyle(
                color: isSelected ? const Color(0xFF008069) : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (selected) {
                setState(() {
                  if (selected)
                    _selectedClasses.add(cls);
                  else
                    _selectedClasses.remove(cls);
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        _buildTargetAudienceSelector(),
      ],
    );
  }

  Widget _buildBranchSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ŞUBE SEÇİN',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 150),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _uniqueBranches.map((br) {
                final isSelected = _selectedBranches.contains(br);
                return FilterChip(
                  showCheckmark: false,
                  label: Text(br),
                  selected: isSelected,
                  selectedColor: const Color(0xFF008069).withOpacity(0.15),
                  labelStyle: TextStyle(
                    color: isSelected
                        ? const Color(0xFF008069)
                        : Colors.black87,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                  onSelected: (selected) {
                    setState(() {
                      if (selected)
                        _selectedBranches.add(br);
                      else
                        _selectedBranches.remove(br);
                    });
                  },
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildTargetAudienceSelector(),
      ],
    );
  }

  Widget _buildTargetAudienceSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'HEDEF KİTLE',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildAudienceOption(
              'Öğrenci',
              Icons.school,
              _sendToStudent,
              () => setState(() => _sendToStudent = !_sendToStudent),
            ),
            const SizedBox(width: 8),
            _buildAudienceOption(
              'Öğretmen',
              Icons.person_outline,
              _sendToTeacher,
              () => setState(() => _sendToTeacher = !_sendToTeacher),
            ),
            const SizedBox(width: 8),
            _buildAudienceOption(
              'Veli',
              Icons.family_restroom,
              _sendToParent,
              () => setState(() => _sendToParent = !_sendToParent),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAudienceOption(
    String title,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF008069) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF008069)
                  : Colors.grey.shade300,
              width: 1.5,
            ),
            boxShadow: [
              if (!isSelected)
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? Colors.white : Colors.grey.shade600,
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _sendMessage() {
    // Mock sending
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mesaj gönderildi ✓'),
        backgroundColor: Color(0xFF008069),
      ),
    );
  }
}
