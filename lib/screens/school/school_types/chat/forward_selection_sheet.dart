import 'package:flutter/material.dart';
import 'chat_models.dart';

class ForwardSelectionSheet extends StatefulWidget {
  final List<ChatUser> contacts;
  final Function(List<ChatUser>) onForward;

  const ForwardSelectionSheet({
    Key? key,
    required this.contacts,
    required this.onForward,
  }) : super(key: key);

  @override
  State<ForwardSelectionSheet> createState() => _ForwardSelectionSheetState();
}

class _ForwardSelectionSheetState extends State<ForwardSelectionSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<ChatUser> _getFilteredContacts(String type) {
    return widget.contacts.where((u) {
      final matchessearch = u.name.toLowerCase().contains(_searchQuery);
      final matchestype = u.userType == type;
      return matchessearch && matchestype;
    }).toList();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F2F5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Kişi ara...',
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.search, color: Colors.grey),
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Tabs
          TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF008069),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF008069),
            tabs: const [
              Tab(text: 'Personel'),
              Tab(text: 'Öğrenci'),
            ],
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildList(_getFilteredContacts('staff')),
                _buildList(_getFilteredContacts('student')),
              ],
            ),
          ),

          // Send Button
          if (_selectedIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    offset: const Offset(0, -2),
                    blurRadius: 5,
                  ),
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final selectedUsers = widget.contacts
                          .where((u) => _selectedIds.contains(u.id))
                          .toList();
                      widget.onForward(selectedUsers);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF008069),
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(16),
                    ),
                    child: const Icon(Icons.send, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildList(List<ChatUser> users) {
    if (users.isEmpty) {
      return const Center(child: Text("Sonuç bulunamadı"));
    }
    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        final isSelected = _selectedIds.contains(user.id);

        return ListTile(
          leading: Stack(
            children: [
              CircleAvatar(
                backgroundImage: user.avatarUrl != null
                    ? NetworkImage(user.avatarUrl!)
                    : null,
                child: user.avatarUrl == null
                    ? Text(user.name.isNotEmpty ? user.name[0] : '?')
                    : null,
              ),
              if (isSelected)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Color(0xFF008069),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          title: Text(user.name),
          subtitle: Text(user.role ?? ''),
          trailing: Checkbox(
            value: isSelected,
            activeColor: const Color(0xFF008069),
            onChanged: (val) => _toggleSelection(user.id),
            shape: const CircleBorder(),
          ),
          onTap: () => _toggleSelection(user.id),
        );
      },
    );
  }
}
