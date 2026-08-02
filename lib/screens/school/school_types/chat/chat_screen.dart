import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'chat_models.dart';
import 'chat_list_widget.dart';
import 'chat_detail_widget.dart';
import 'bulk_message_dialog.dart';
import 'create_group_dialog.dart';
import 'call/call_models.dart';
import 'call/call_service.dart';
import 'call/call_screen_dialog.dart';
import 'monitoring/message_monitoring_screen.dart';
import 'settings/chat_settings_dialog.dart';
import '../../../../widgets/alici_secimi.dart';
import '../../../../../services/chat_service.dart';
import '../../../../../services/user_permission_service.dart';
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
  StreamSubscription<List<CallSession>>? _incomingCallSubscription;

  List<ChatUser> _contacts = [];
  List<ChatUser> _filteredContacts = [];
  List<Conversation> _conversations = [];
  List<Conversation> _filteredConversations = [];

  Conversation? _selectedConversation;
  bool _isLoadingContacts = true;
  bool _isSearching = false;
  String _activeCategoryFilter = 'Tümü';

  bool _canSeeSettings = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkPermissions();
    _loadConversations();
    _loadContacts();
    _listenForIncomingCalls();
    CallService().registerFcmToken();

    // Listen for Auth changes in case of refresh/restart
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && mounted) {
        _checkPermissions();
        _loadConversations();
        _listenForIncomingCalls();
        CallService().registerFcmToken();
      }
    });
  }

  Future<void> _checkPermissions() async {
    try {
      final userData = await UserPermissionService.loadUserData();
      final role = (userData?['role'] ?? '').toString().toLowerCase();
      final type = (userData?['type'] ?? userData?['userType'] ?? '').toString().toLowerCase();

      final isTeacher = type == 'teacher' || role == 'ogretmen' || role == 'öğretmen' || role == 'teacher';
      final isManagerOrAdmin = role == 'admin' || role == 'genel_mudur' || role == 'genel müdür' || role == 'mudur' || role == 'müdür' || role == 'manager';

      final hasCustomSettingsPerm = UserPermissionService.hasModuleAccess('haberlesme_ayarlar', userData);

      if (mounted) {
        setState(() {
          _currentUserRole = isManagerOrAdmin ? 'manager' : (isTeacher ? 'teacher' : 'staff');
          // Teachers cannot see settings unless explicit permission is assigned
          _canSeeSettings = isManagerOrAdmin || hasCustomSettingsPerm;
        });
      }
    } catch (e) {
      debugPrint("Haberleşme yetki kontrolü hatası: $e");
    }
  }

  void _listenForIncomingCalls() {
    _incomingCallSubscription?.cancel();
    _incomingCallSubscription =
        CallService().listenForIncomingCalls().listen((incomingCalls) {
      if (incomingCalls.isNotEmpty && mounted) {
        final activeCall = incomingCalls.first;
        CallScreenDialog.showCall(
          context: context,
          callSession: activeCall,
          isIncoming: true,
        );
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _conversationsSubscription?.cancel();
    _incomingCallSubscription?.cancel();
    super.dispose();
  }

  String _currentUserRole = 'manager';

  void _openMessageMonitoring() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessageMonitoringScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          currentUserRole: _currentUserRole,
          initialContacts: _contacts,
        ),
      ),
    );
  }

  void _showBulkMessageDialog() {
    List<String> selectedRecipients = [];

    showDialog(
      context: context,
      builder: (context) => AliciSecimi(
        selectedRecipients: selectedRecipients,
        savedGroups: const [],
        schoolTypeId: widget.schoolTypeId,
        institutionId: widget.institutionId,
        onSaveGroup: (groupName) {},
        onConfirmed: (recipients, recipientNames) async {
          if (recipients.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Lütfen en az 1 alıcı seçiniz.')),
            );
            return;
          }

          Navigator.pop(context);
          _promptAndSendBulkMessage(recipients, recipientNames);
        },
      ),
    );
  }

  void _promptAndSendBulkMessage(List<String> recipients, Map<String, String> recipientNames) {
    final TextEditingController messageController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Toplu Mesaj İçeriği (${recipients.length} Alıcı)',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo),
        ),
        content: TextField(
          controller: messageController,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Gönderilecek toplu mesajı yazın...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
            label: Text('Gönder', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
            onPressed: () async {
              final text = messageController.text.trim();
              if (text.isEmpty) return;

              Navigator.pop(context);

              final currentUid = _chatService.currentUserId ?? FirebaseAuth.instance.currentUser?.uid ?? '';
              int sentCount = 0;

              for (var targetId in recipients) {
                try {
                  List<String> participantIds = [currentUid, targetId];
                  final conversationId = await _chatService.createConversation(participantIds);

                  final message = ChatMessage(
                    id: 'msg_${DateTime.now().millisecondsSinceEpoch}_$sentCount',
                    senderId: currentUid,
                    content: text,
                    timestamp: DateTime.now(),
                    type: MessageType.text,
                  );

                  await _chatService.sendMessage(conversationId, message);
                  sentCount++;
                } catch (e) {
                  debugPrint("Bulk message error for $targetId: $e");
                }
              }

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Toplu mesaj $sentCount alıcıya başarıyla gönderildi!'),
                    backgroundColor: const Color(0xFF008069),
                  ),
                );
                _loadConversations();
              }
            },
          ),
        ],
      ),
    );
  }

  void _handleMenuOption(String value) {
    if (value == 'monitoring') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MessageMonitoringScreen(
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
            currentUserRole: _currentUserRole,
            initialContacts: _contacts,
          ),
        ),
      );
    } else if (value == 'settings') {
      ChatSettingsDialog.show(context);
    } else if (value == 'new_group') {
      _showCreateGroupDialog();
    } else if (value == 'bulk_message') {
      _showBulkMessageDialog();
    } else if (value == 'starred') {
      _showStarredMessagesDialog();
    } else if (value == 'archived') {
      _showArchivedChatsDialog();
    }
  }

  void _showCreateGroupDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: CreateGroupDialog(
          contacts: _contacts,
          onCreateGroup: (name, selectedUsers) async {
            final participantIds = selectedUsers.map((u) => u.id).toList();
            if (_chatService.currentUserId != null &&
                !participantIds.contains(_chatService.currentUserId)) {
              participantIds.add(_chatService.currentUserId!);
            }
            await _chatService.createConversation(
              participantIds,
              isGroup: true,
              groupName: name,
            );
            _loadConversations();
          },
        ),
      ),
    );
  }

  Future<List<ChatMessage>> _fetchStarredMessagesFromFirestore() async {
    List<ChatMessage> list = List.from(globalStarredMessages);

    try {
      for (var conv in _conversations) {
        final msgsSnapshot = await FirebaseFirestore.instance
            .collection('conversations')
            .doc(conv.id)
            .collection('messages')
            .where('isStarred', isEqualTo: true)
            .get();

        for (var doc in msgsSnapshot.docs) {
          final msg = ChatMessage.fromMap(doc.data(), doc.id);
          if (!list.any((m) => m.id == msg.id)) {
            list.add(msg);
          }
        }
      }
    } catch (e) {
      debugPrint("Yıldızlı mesajlar çekilirken hata: $e");
    }

    return list;
  }

  void _showStarredMessagesBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.star_rounded, color: Colors.amber, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Yıldızlı Mesajlar',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<List<ChatMessage>>(
                  future: _fetchStarredMessagesFromFirestore(),
                  builder: (context, snapshot) {
                    final messages = snapshot.data ?? globalStarredMessages;
                    if (snapshot.connectionState == ConnectionState.waiting && messages.isEmpty) {
                      return const Center(child: CircularProgressIndicator(color: Colors.amber));
                    }
                    if (messages.isEmpty) {
                      return Center(
                        child: Text(
                          'Henüz yıldızlı mesajınız bulunmuyor.',
                          style: GoogleFonts.inter(color: Colors.blueGrey, fontSize: 14),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: messages.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          leading: CircleAvatar(
                            backgroundColor: Colors.amber.shade50,
                            child: const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
                          ),
                          title: Text(
                            msg.content.isNotEmpty ? msg.content : '[Medya Mesajı]',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            DateFormat('dd.MM.yyyy HH:mm').format(msg.timestamp),
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.indigo),
                          onTap: () {
                            Navigator.pop(context);
                            _navigateToMessage(msg);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _navigateToMessage(ChatMessage message) {
    if (_conversations.isNotEmpty) {
      setState(() {
        _selectedConversation = _conversations.first;
      });
    }
  }

  void _showStarredMessagesDialog() {
    _showStarredMessagesBottomSheet();
  }

  String _getConversationTitle(Conversation conv) {
    if (conv.chatName != null && conv.chatName!.isNotEmpty) {
      return conv.chatName!;
    }
    return 'Sohbet';
  }

  void _handleArchiveConversation(Conversation conversation) {
    final willArchive = !conversation.isArchived;
    _chatService.toggleArchive(conversation.id, willArchive);

    if (willArchive && _selectedConversation?.id == conversation.id) {
      setState(() {
        _selectedConversation = null;
      });
    }

    final title = _getConversationTitle(conversation);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          willArchive
              ? '$title arşivlendi ve sohbet listesinden kaldırıldı.'
              : '$title arşivden çıkarıldı.',
        ),
        backgroundColor: Colors.indigo,
      ),
    );
  }

  void _handleClearConversation(Conversation conversation) {
    // Sohbeti Temizle: Silme yetkisi olmadığı için veritabanındaki mesaj geçmişi silinmez.
    // Sohbet arşive aktarılır ve sohbet listesinden kişinin adı kaldırılır.
    _chatService.toggleArchive(conversation.id, true);

    if (_selectedConversation?.id == conversation.id) {
      setState(() {
        _selectedConversation = null;
      });
    }

    final title = _getConversationTitle(conversation);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$title sohbeti temizlendi (Mesaj silme yetkiniz olmadığı için mesaj geçmişi arşivde saklandı, sohbet listesinden kaldırıldı).',
        ),
        backgroundColor: Colors.blueGrey,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showArchivedChatsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final archived = _conversations.where((c) => c.isArchived).toList();
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.archive_rounded, color: Colors.blueGrey, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Arşivlenmiş Sohbetler',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: archived.isEmpty
                    ? Center(
                        child: Text(
                          'Arşivlenmiş sohbetiniz bulunmuyor.',
                          style: GoogleFonts.inter(color: Colors.blueGrey, fontSize: 14),
                        ),
                      )
                    : ListView.separated(
                        itemCount: archived.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final c = archived[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                            leading: CircleAvatar(
                              backgroundImage: (c.chatImage != null && c.chatImage!.isNotEmpty)
                                  ? NetworkImage(c.chatImage!)
                                  : null,
                              child: (c.chatImage == null || c.chatImage!.isEmpty)
                                  ? const Icon(Icons.person)
                                  : null,
                            ),
                            title: Text(
                              c.chatName ?? 'Sohbet',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
                            ),
                            subtitle: Text(
                              c.lastMessage?.content ?? '',
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.unarchive_rounded, color: Colors.indigo),
                              tooltip: 'Arşivden Çıkar',
                              onPressed: () {
                                _handleArchiveConversation(c);
                                Navigator.pop(context);
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
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

  void _onSearchChanged(String query) {
    setState(() {
      final normalizedQuery = TurkishStringUtils.normalizeForSearch(query);
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;

      _filteredConversations = _conversations.where((c) {
        if (c.isArchived) return false;
        if (c.lastMessage == null || c.lastMessage!.content.trim().isEmpty) return false;

        // Category Filter Chips (Tümü, Okunmamış, Favoriler, Gruplar)
        if (_activeCategoryFilter == 'Okunmamış') {
          final unread = c.unreadCounts[currentUserId] ?? 0;
          if (unread <= 0) return false;
        } else if (_activeCategoryFilter == 'Favoriler') {
          if (c.lastMessage?.isStarred != true) return false;
        } else if (_activeCategoryFilter == 'Gruplar') {
          if (!c.isGroup) return false;
        }

        // Search Query Filter
        if (normalizedQuery.isNotEmpty) {
          final name = TurkishStringUtils.normalizeForSearch(c.chatName ?? '');
          return name.contains(normalizedQuery);
        }

        return true;
      }).toList();

      if (normalizedQuery.isNotEmpty) {
        _filteredContacts = _contacts.where((u) {
          final name = TurkishStringUtils.normalizeForSearch(u.name);
          return name.contains(normalizedQuery);
        }).toList();
      } else {
        _filteredContacts = List.from(_contacts);
      }
    });
  }

  Widget _buildWhatsAppCategoryFilterPills() {
    final categories = ['Tümü', 'Okunmamış', 'Favoriler', 'Gruplar'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: Colors.white,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
          },
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: categories.map((cat) {
              final isSelected = _activeCategoryFilter == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: ChoiceChip(
                  label: Text(
                    cat,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? const Color(0xFF008069) : const Color(0xFF54656F),
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: const Color(0xFFD9FDD3),
                  backgroundColor: const Color(0xFFF0F2F5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? const Color(0xFF25D366) : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _activeCategoryFilter = cat;
                        _onSearchChanged(_searchController.text);
                      });
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ),
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
        final docSchoolTypeId = data['schoolTypeId'] as String?;
        if (widget.schoolTypeId.isNotEmpty &&
            docSchoolTypeId != null &&
            docSchoolTypeId.isNotEmpty &&
            docSchoolTypeId != widget.schoolTypeId) {
          continue; // Skip student belonging to another school type
        }

        loadedContacts.add(
          ChatUser(
            // Prefer Auth UID if available to match conversation participantIds
            id: data['uid'] ?? data['userId'] ?? doc.id,
            name: data['fullName'] ?? '${data['name']} ${data['surname']}',
            userType: 'student',
            role: data['className'] ?? 'Öğrenci',
            avatarUrl: data['photoUrl'],
            schoolTypeId: docSchoolTypeId,
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
        final docSchoolTypeId = data['schoolTypeId'] as String?;
        final docSchoolTypeIds = List<String>.from(data['schoolTypeIds'] ?? []);

        if (widget.schoolTypeId.isNotEmpty &&
            docSchoolTypeId != null &&
            docSchoolTypeId.isNotEmpty &&
            docSchoolTypeId != widget.schoolTypeId &&
            !docSchoolTypeIds.contains(widget.schoolTypeId)) {
          continue; // Skip staff belonging exclusively to another school type
        }

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
            schoolTypeId: docSchoolTypeId,
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
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                      child: Container(
                        height: 38,
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
                                  hoverColor: Colors.transparent,
                                ),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // WhatsApp Web Category Filter Chips (Tümü, Okunmamış, Favoriler, Gruplar)
                    _buildWhatsAppCategoryFilterPills(),
                    const Divider(height: 1, color: Color(0xFFE9EDEF)),
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
                            currentUserRole: _currentUserRole,
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 6,
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onSelected: _handleMenuOption,
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'new_group',
                        height: 40,
                        child: Row(
                          children: [
                            const Icon(Icons.group_add_rounded, color: Colors.indigo, size: 18),
                            const SizedBox(width: 10),
                            Text('Yeni Grup', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'bulk_message',
                        height: 40,
                        child: Row(
                          children: [
                            const Icon(Icons.send_rounded, color: Colors.indigo, size: 18),
                            const SizedBox(width: 10),
                            Text('Toplu Mesaj Gönder', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'starred',
                        height: 40,
                        child: Row(
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                            const SizedBox(width: 10),
                            Text('Yıldızlı Mesajlar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'archived',
                        height: 40,
                        child: Row(
                          children: [
                            const Icon(Icons.archive_rounded, color: Colors.blueGrey, size: 18),
                            const SizedBox(width: 10),
                            Text('Arşivlenmiş Sohbetler', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      if (_canSeeSettings)
                        PopupMenuItem(
                          value: 'settings',
                          height: 40,
                          child: Row(
                            children: [
                              const Icon(Icons.settings_suggest_rounded, color: Colors.indigo, size: 18),
                              const SizedBox(width: 10),
                              Text('Ayarlar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                            ],
                          ),
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
                    currentUserRole: _currentUserRole,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFF0F2F5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: Colors.indigo,
                child: Icon(Icons.person_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Sohbetler',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF111B21),
                ),
              ),
            ],
          ),
          Row(
            children: [
              if (_chatService.isManagerRole(_currentUserRole))
                IconButton(
                  icon: const Icon(Icons.remove_red_eye_outlined, size: 20),
                  tooltip: 'Mesajları İzle',
                  onPressed: _openMessageMonitoring,
                  color: const Color(0xFF54656F),
                  splashRadius: 20,
                ),
              if (!_currentUserRole.toLowerCase().contains('student') && !_currentUserRole.toLowerCase().contains('parent'))
                IconButton(
                  icon: const Icon(Icons.broadcast_on_personal, size: 20),
                  tooltip: 'Toplu Mesaj',
                  onPressed: _showBulkMessageDialog,
                  color: const Color(0xFF54656F),
                  splashRadius: 20,
                ),
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                tooltip: 'Yeni Sohbet / Grup',
                onPressed: _showCreateGroupDialog,
                color: const Color(0xFF54656F),
                splashRadius: 20,
              ),
              PopupMenuButton<String>(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 6,
                icon: Icon(Icons.more_vert, color: Colors.grey.shade700),
                tooltip: 'Seçenekler',
                onSelected: _handleMenuOption,
                itemBuilder: (BuildContext context) {
                  return [
                    PopupMenuItem(
                      value: 'new_group',
                      height: 40,
                      child: Row(
                        children: [
                          const Icon(Icons.group_add_rounded, color: Colors.indigo, size: 18),
                          const SizedBox(width: 10),
                          Text('Yeni Grup', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'starred',
                      height: 40,
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                          const SizedBox(width: 10),
                          Text('Yıldızlı Mesajlar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'archived',
                      height: 40,
                      child: Row(
                        children: [
                          const Icon(Icons.archive_rounded, color: Colors.blueGrey, size: 18),
                          const SizedBox(width: 10),
                          Text('Arşivlenmiş Sohbetler', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    if (_canSeeSettings)
                      PopupMenuItem(
                        value: 'settings',
                        height: 40,
                        child: Row(
                          children: [
                            const Icon(Icons.settings_suggest_rounded, color: Colors.indigo, size: 18),
                            const SizedBox(width: 10),
                            Text('Ayarlar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
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
  }  void _showSettingsDialog() {
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
