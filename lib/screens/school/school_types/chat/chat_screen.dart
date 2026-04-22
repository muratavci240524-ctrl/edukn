import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'chat_models.dart';
import 'chat_list_widget.dart';
import 'chat_detail_widget.dart';
import 'bulk_message_dialog.dart';
import 'create_group_dialog.dart';
import '../../../../../services/chat_service.dart';
import 'dart:async';

class ChatScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;

  const ChatScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final ChatService _chatService = ChatService();
  StreamSubscription<List<Conversation>>? _conversationsSubscription;

  List<ChatUser> _contacts = [];
  List<ChatUser> _filteredContacts = [];
  List<Conversation> _conversations = [];
  List<Conversation> _filteredConversations = [];

  Conversation? _selectedConversation;
  bool _isLoadingContacts = true;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadConversations();
    _loadContacts();

    // Listen for Auth changes in case of refresh/restart
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && mounted) {
        _loadConversations();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _conversationsSubscription?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      final lowerQuery = query.toLowerCase();

      // Filter Conversations
      if (query.isEmpty) {
        _filteredConversations = _conversations
            .where((c) => !c.isArchived)
            .toList();
      } else {
        _filteredConversations = _conversations.where((c) {
          return c.chatName!.toLowerCase().contains(lowerQuery) &&
              !c.isArchived;
        }).toList();
      }

      // Filter Contacts
      if (query.isEmpty) {
        _filteredContacts = List.from(_contacts);
      } else {
        _filteredContacts = _contacts.where((u) {
          final name = u.name.toLowerCase();
          final role = (u.role ?? '').toLowerCase();
          return name.contains(lowerQuery) || role.contains(lowerQuery);
        }).toList();
      }
    });
  }

  void _handleArchiveConversation(Conversation conversation) {
    // Optimistic update locally not strictly needed as stream will update
    // But good for UI responsiveness if stream is slow.
    // However, simplest is just call service.

    _chatService.toggleArchive(conversation.id, !conversation.isArchived);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          conversation.isArchived
              ? '${conversation.chatName} arşivden çıkarıldı (işleniyor...)'
              : '${conversation.chatName} arşivlendi (işleniyor...)',
        ),
      ),
    );
  }

  void _showArchivedChatsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final archived = _conversations.where((c) => c.isArchived).toList();
        return AlertDialog(
          title: const Text('Arşivlenmiş Sohbetler'),
          content: SizedBox(
            width: 400,
            height: 500,
            child: archived.isEmpty
                ? const Center(child: Text('Arşivlenmiş sohbet yok'))
                : ListView.builder(
                    itemCount: archived.length,
                    itemBuilder: (context, index) {
                      final c = archived[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: c.chatImage != null
                              ? NetworkImage(c.chatImage!)
                              : null,
                          child: c.chatImage == null
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        title: Text(c.chatName ?? ''),
                        subtitle: Text(c.lastMessage?.content ?? ''),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.unarchive,
                            color: Colors.indigo,
                          ),
                          onPressed: () {
                            _handleArchiveConversation(c);
                            Navigator.pop(
                              context,
                            ); // Close for simplicity to refresh
                            _showArchivedChatsDialog(); // Reopen
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kapat'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadConversations() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _conversationsSubscription?.cancel();
    // Listen to real data
    _conversationsSubscription = _chatService.getConversations(user.uid).listen(
      (conversations) {
        if (mounted) {
          setState(() {
            _conversations = conversations;
            _onSearchChanged(_searchController.text);
          });
        }
      },
    );
  }

  Future<void> _loadContacts() async {
    if (mounted) setState(() => _isLoadingContacts = true);
    List<ChatUser> loadedContacts = [];

    try {
      // 1. Fetch Students
      final studentsSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in studentsSnapshot.docs) {
        final data = doc.data();
        loadedContacts.add(
          ChatUser(
            // Prefer Auth UID if available to match conversation participantIds
            id: data['uid'] ?? data['userId'] ?? doc.id,
            name: data['fullName'] ?? '${data['name']} ${data['surname']}',
            userType: 'student',
            role: data['className'] ?? 'Öğrenci',
            avatarUrl: data['photoUrl'],
          ),
        );
      }

      // 2. Fetch Staff
      final staffSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('type', isEqualTo: 'staff')
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in staffSnapshot.docs) {
        final data = doc.data();
        final branch = data['branch'] as String?;
        final title = data['title'] as String?;

        String displayRole = title ?? 'Personel';
        if (branch != null && branch.isNotEmpty) {
          displayRole = branch;
        }

        loadedContacts.add(
          ChatUser(
            id: data['uid'] ?? data['userId'] ?? doc.id,
            name: data['fullName'] ?? 'Personel',
            userType: 'staff',
            role: displayRole,
            avatarUrl: data['photoUrl'],
          ),
        );
      }

      loadedContacts.sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      print('Error loading contacts: $e');
    }

    if (mounted) {
      setState(() {
        _contacts = loadedContacts;
        _filteredContacts = loadedContacts;
        _isLoadingContacts = false;
      });
    }
  }

  void _startConversationWith(ChatUser user) {
    // Check if conversation exists
    final existing = _conversations.firstWhere(
      (c) => c.participantIds.contains(user.id),
      orElse: () => Conversation(
        id: 'temp_${user.id}',
        participantIds: [user.id],
        chatName: user.name,
        chatImage: user.avatarUrl,
        unreadCount: 0,
      ),
    );

    setState(() {
      if (!_conversations.contains(existing)) {
        _conversations.insert(0, existing);
        // Also add to global session if not exists
        if (!sessionConversations.any((c) => c.id == existing.id)) {
          sessionConversations.insert(0, existing);
        }

        // Update filtered list
        if (_searchController.text.isEmpty ||
            existing.chatName!.toLowerCase().contains(
              _searchController.text.toLowerCase(),
            )) {
          _filteredConversations = List.from(
            _conversations.where((c) => !c.isArchived),
          );
          _onSearchChanged(_searchController.text);
        }
      }
      _selectedConversation = existing;

      final isWide = MediaQuery.of(context).size.width > 800;
      if (!isWide) {
        // Mobile: Push content
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              body: SafeArea(
                child: ChatDetailWidget(
                  key: ValueKey(existing.id),
                  conversation: existing,
                  contacts: _contacts,
                  onBack: () => Navigator.pop(context),
                  onForwardMessages: _handleForwardMessages,
                ),
              ),
            ),
          ),
        );
      } else {
        // Desktop: Just select
      }
    });
  }

  Future<void> _handleForwardMessages(
    List<ChatUser> users,
    ChatMessage message,
  ) async {
    int successCount = 0;

    for (var user in users) {
      // 1. Check if we have a conversation with this user
      // We check our loaded list for existing 1-on-1
      Conversation? targetConversation;

      try {
        final existing = _conversations.firstWhere(
          (c) =>
              c.participantIds.contains(user.id) &&
              c.participantIds.length <= 2, // simplified assumption
        );
        targetConversation = existing;
      } catch (_) {
        // Not found locally (stream hasn't loaded it or doesn't exist)
      }

      String conversationId;
      if (targetConversation != null) {
        conversationId = targetConversation.id;
      } else {
        // Create new
        List<String> participants = [];
        if (_chatService.currentUserId != null)
          participants.add(_chatService.currentUserId!);
        participants.add(user.id);

        conversationId = await _chatService.createConversation(participants);
      }

      // 2. Send message
      final forwardedMsg = message.copyWith(
        senderId: _chatService.currentUserId ?? 'unknown',
        timestamp: DateTime.now(),
        isForwarded: true,
      );

      await _chatService.sendMessage(conversationId, forwardedMsg);
      successCount++;
    }

    // Update filtered list (stream handles it automatically mostly)

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$successCount sohbete iletildi.')));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;

        if (isWide) {
          // DESKTOP / TABLET LAYOUT
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.indigo,
              elevation: 0,
              leading: const BackButton(color: Colors.white),
              title: const Text(
                'Mesajlar',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            body: Row(
              children: [
              // Left Panel
              Container(
                width: 380,
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: Color(0xFFE0E0E0), width: 1),
                  ),
                  color: Colors.white,
                ),
                child: Column(
                  children: [
                    _buildUserProfileHeader(),
                    // Search Bar
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Container(
                        height: 35,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F2F5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 12),
                            const Icon(
                              Icons.search,
                              color: Color(0xFF54656F),
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: _onSearchChanged,
                                decoration: const InputDecoration(
                                  hintText: 'Aratın veya yeni sohbet başlatın',
                                  hintStyle: TextStyle(
                                    color: Color(0xFF54656F),
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  errorBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  hoverColor: Colors
                                      .transparent, // Attempt to disable hover effect if supported or ignored
                                ),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    TabBar(
                      controller: _tabController,
                      labelColor: Colors.indigo,
                      unselectedLabelColor: const Color(0xFF54656F),
                      indicatorColor: Colors.indigo,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                      indicatorSize: TabBarIndicatorSize.tab,
                      tabs: const [
                        Tab(text: 'Sohbetler'),
                        Tab(text: 'Kişiler'),
                      ],
                    ),
                    const Divider(height: 1, color: Color(0xFFE0E0E0)),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          ChatListWidget(
                            conversations: _filteredConversations,
                            selectedConversationId: _selectedConversation?.id,
                            onConversationSelected: (c) {
                              setState(() => _selectedConversation = c);
                            },
                            onArchive: _handleArchiveConversation,
                            contacts: _contacts,
                          ),
                          _buildContactsList(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Right Panel
              Expanded(
                child: _selectedConversation != null
                    ? ChatDetailWidget(
                        key: ValueKey(_selectedConversation!.id),
                        conversation: _selectedConversation!,
                        contacts: _contacts,
                        onForwardMessages: _handleForwardMessages,
                      )
                    : _buildEmptyState(),
              ),
            ],
          ));
        } else {
          // MOBILE LAYOUT
          return GestureDetector(
            onTap: () {
              if (_isSearching) {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                  _onSearchChanged('');
                });
                FocusScope.of(context).unfocus();
              }
            },
            child: Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                leading: const BackButton(color: Colors.white),
                backgroundColor: Colors.indigo,
                elevation: 0,
                // Enhanced Search UI
                title: const Text(
                  'Mesajlar',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Colors.white,
                  ),
                ),
                actions: [
                  // Animated Search Bar
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: _isSearching ? 220 : 0,
                    height: 40,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: _isSearching
                        ? TextField(
                            controller: _searchController,
                            style: const TextStyle(color: Colors.black87),
                            cursorColor: Colors.indigo,
                            decoration: InputDecoration(
                              hintText: 'Ara...',
                              hintStyle: TextStyle(color: Colors.grey.shade500),
                              prefixIcon: Icon(
                                Icons.search,
                                color: Colors.grey.shade500,
                                size: 20,
                              ),
                              suffixIcon: IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.grey,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isSearching = false;
                                    _searchController.clear();
                                    _onSearchChanged('');
                                  });
                                },
                                splashRadius: 20,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 8,
                              ),
                              isDense: true,
                            ),
                            onChanged: _onSearchChanged,
                            autofocus: true,
                          )
                        : null,
                  ),

                  if (!_isSearching)
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _isSearching = true;
                        });
                      },
                      icon: const Icon(Icons.search, color: Colors.white),
                      tooltip: 'Ara',
                    ),

                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onSelected: _handleMenuOption,
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'new_group',
                        child: Text('Yeni Grup'),
                      ),
                      const PopupMenuItem(
                        value: 'starred',
                        child: Text('Yıldızlı Mesajlar'),
                      ),
                      const PopupMenuItem(
                        value: 'archived',
                        child: Text('Arşivlenmiş Sohbetler'),
                      ),
                      const PopupMenuItem(
                        value: 'settings',
                        child: Text('Ayarlar'),
                      ),
                    ],
                  ),
                ],
                bottom: _isSearching
                    ? null
                    : TabBar(
                        controller: _tabController,
                        indicatorColor: Colors.white,
                        indicatorWeight: 3,
                        labelColor: Colors.white,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        unselectedLabelColor: Colors.white70,
                        tabs: const [
                          Tab(text: 'SOHBETLER'),
                          Tab(text: 'KİŞİLER'),
                        ],
                      ),
              ),
              body: TabBarView(
                controller: _tabController,
                children: [
                  ChatListWidget(
                    conversations: _filteredConversations,
                    selectedConversationId: null,
                    onConversationSelected: (c) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            body: SafeArea(
                              child: ChatDetailWidget(
                                key: ValueKey(c.id),
                                conversation: c,
                                contacts: _contacts,
                                onBack: () => Navigator.pop(context),
                                onForwardMessages: _handleForwardMessages,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    onArchive: _handleArchiveConversation,
                    contacts: _contacts,
                  ),
                  _buildContactsList(),
                ],
              ),
              floatingActionButton: FloatingActionButton(
                onPressed: () => _tabController.animateTo(1),
                backgroundColor: Colors.indigo,
                child: const Icon(Icons.message, color: Colors.white),
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildContactsList() {
    if (_isLoadingContacts) {
      return const Center(child: CircularProgressIndicator());
    }

    final contactsToShow = _filteredContacts;

    if (contactsToShow.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              _searchController.text.isEmpty
                  ? 'Kişi bulunamadı.'
                  : 'Sonuç bulunamadı.',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final students = contactsToShow
        .where((u) => u.userType == 'student')
        .toList();
    final staff = contactsToShow.where((u) => u.userType == 'staff').toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (staff.isNotEmpty) ...[
          _buildGroupHeader('Personel'),
          ...staff.map((user) => _buildContactItem(user)),
        ],
        if (students.isNotEmpty) ...[
          _buildGroupHeader('Öğrenciler'),
          ...students.map((user) => _buildContactItem(user)),
        ],
      ],
    );
  }

  Widget _buildGroupHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Color(0xFF008069),
        ),
      ),
    );
  }

  Widget _buildContactItem(ChatUser user) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundImage: (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
            ? NetworkImage(user.avatarUrl!)
            : null,
        backgroundColor: user.userType == 'staff'
            ? Colors.orange.shade100
            : Colors.blue.shade100,
        child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
            ? Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: user.userType == 'staff'
                      ? Colors.orange.shade800
                      : Colors.blue.shade800,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
      title: Text(
        user.name,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      subtitle: Text(
        user.role ?? user.userType ?? '',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
      ),
      onTap: () => _startConversationWith(user),
    );
  }

  Widget _buildUserProfileHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFF0F2F5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: Colors.grey,
            child: Icon(Icons.person, color: Colors.white),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_red_eye),
                tooltip: 'Mesajları İzle',
                onPressed: _showChatMonitorDialog,
                color: Colors.grey.shade600,
                splashRadius: 24,
              ),
              IconButton(
                icon: const Icon(Icons.broadcast_on_personal),
                tooltip: 'Toplu Mesaj',
                onPressed: _showBulkMessageDialog,
                color: Colors.grey.shade600,
                splashRadius: 24,
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                tooltip: 'Seçenekler',
                onSelected: _handleMenuOption,
                itemBuilder: (BuildContext context) {
                  return [
                    const PopupMenuItem(
                      value: 'new_group',
                      child: Row(
                        children: [
                          Icon(Icons.group_add, color: Colors.grey),
                          SizedBox(width: 8),
                          Text('Yeni Grup'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'starred',
                      child: Row(
                        children: [
                          Icon(Icons.star, color: Colors.grey),
                          SizedBox(width: 8),
                          Text('Yıldızlı Mesajlar'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'archived',
                      child: Row(
                        children: [
                          Icon(Icons.archive, color: Colors.grey),
                          SizedBox(width: 8),
                          Text('Arşivlenmiş Sohbetler'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'settings',
                      child: Row(
                        children: [
                          Icon(Icons.settings, color: Colors.grey),
                          SizedBox(width: 8),
                          Text('Ayarlar'),
                        ],
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleMenuOption(String value) {
    switch (value) {
      case 'new_group':
        _showCreateGroupDialog();
        break;
      case 'starred':
        _showStarredMessagesDialog();
        break;
      case 'archived':
        _showArchivedChatsDialog();
        break;
      case 'settings':
        _showSettingsDialog();
        break;
      case 'monitor':
        _showChatMonitorDialog();
        break;
    }
  }

  void _showBulkMessageDialog() {
    showDialog(
      context: context,
      builder: (context) => BulkMessageDialog(contacts: _contacts),
    );
  }

  void _showChatMonitorDialog() {
    // Filter for only staff members as requested
    final staffList = _contacts.where((u) => u.userType == 'staff').toList();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Personel Mesajlarını İzle',
            style: TextStyle(
              color: Color(0xFF008069),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: staffList.isEmpty
                ? const Center(child: Text('Personel bulunamadı.'))
                : ListView.builder(
                    itemCount: staffList.length,
                    itemBuilder: (context, index) {
                      final user = staffList[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: user.avatarUrl != null
                              ? NetworkImage(user.avatarUrl!)
                              : null,
                          radius: 18,
                          backgroundColor: Colors.orange.shade50,
                          child: user.avatarUrl == null
                              ? Text(
                                  user.name[0],
                                  style: TextStyle(
                                    color: Colors.orange.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        title: Text(
                          user.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(user.role ?? 'Personel'),
                        trailing: const Icon(
                          Icons.remove_red_eye_outlined,
                          color: Colors.grey,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${user.name} kullanıcısının mesajları izleniyor... (Demo)',
                              ),
                              backgroundColor: const Color(0xFF008069),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kapat', style: TextStyle(color: Colors.grey)),
            ),
          ],
        );
      },
    );
  }

  void _showCreateGroupDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateGroupDialog(contacts: _contacts),
    );
  }

  void _showStarredMessagesDialog() {
    // Use the global mocked list from chat_models.dart
    final starredMessages = globalStarredMessages;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Yıldızlı Mesajlar',
          style: TextStyle(
            color: Color(0xFF008069),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: 450,
          height: 300,
          child: starredMessages.isEmpty
              ? Center(
                  child: Text(
                    'Henüz yıldızlı mesajınız yok.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView.separated(
                  itemCount: starredMessages.length,
                  separatorBuilder: (c, i) => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(),
                  ),
                  itemBuilder: (context, index) {
                    final msg = starredMessages[index];
                    final isMe = msg.senderId == 'me';
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: Colors.amber.shade100,
                        child: const Icon(
                          Icons.star,
                          color: Colors.amber,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        msg.content,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Row(
                          children: [
                            Text(
                              isMe ? 'Siz' : 'Ahmet Yılmaz',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${DateFormat.yMMMd().format(msg.timestamp)} ${DateFormat.Hm().format(msg.timestamp)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF008069),
            ),
            child: const Text(
              'KAPAT',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Ayarlar',
          style: TextStyle(
            color: Color(0xFF008069),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSettingsTile(
                Icons.notifications_outlined,
                'Bildirimler',
                'Mesaj ve grup bildirimleri',
              ),
              _buildSettingsTile(
                Icons.lock_outline,
                'Gizlilik',
                'Engellenen kişiler, son görülme',
              ),
              _buildSettingsTile(
                Icons.wallpaper,
                'Sohbet Duvar Kağıdı',
                'Tema ve renkler',
              ),
              _buildSettingsTile(
                Icons.help_outline,
                'Yardım',
                'Yardım merkezi, iletişim',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF008069),
            ),
            child: const Text(
              'KAPAT',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF54656F)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
      ),
      onTap: () {},
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      color: const Color(0xFFF0F2F5),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 120,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 32),
          Text(
            '${widget.schoolTypeName} Sohbet',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w300,
              color: Color(0xFF41525D),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Mesajlaşmaya başlamak için soldan bir sohbet\nveya kişi seçin.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 32),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 14, color: Colors.grey),
              SizedBox(width: 4),
              Text(
                'Güvenli İletişim',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
