import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../chat_models.dart';
import '../../../../../../services/chat_service.dart';

class MessageMonitoringScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String currentUserRole;
  final List<ChatUser>? initialContacts;

  const MessageMonitoringScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.currentUserRole,
    this.initialContacts,
  }) : super(key: key);

  @override
  State<MessageMonitoringScreen> createState() => _MessageMonitoringScreenState();
}

class _MessageMonitoringScreenState extends State<MessageMonitoringScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();

  List<ChatUser> _selectableUsers = [];
  List<ChatUser> _filteredSelectableUsers = [];
  ChatUser? _selectedTargetUser;

  List<Conversation> _targetConversations = [];
  Conversation? _selectedConversation;
  List<ChatMessage> _targetMessages = [];

  bool _isLoadingUsers = true;
  bool _isLoadingMessages = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadSelectableUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatDisplayRole(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Kullanıcı';
    final lower = raw.toLowerCase().trim();
    if (lower == 'genel_mudur' || lower == 'genel mudur') return 'Genel Müdür';
    if (lower == 'mudur' || lower == 'müdür') return 'Müdür';
    if (lower == 'mudur_yardimcisi' || lower == 'mudur yardimcisi' || lower == 'müdür yardımcısı') return 'Müdür Yardımcısı';
    if (lower == 'ogretmen' || lower == 'öğretmen' || lower == 'teacher') return 'Öğretmen';
    if (lower == 'rehber_ogretmen' || lower == 'rehberlik') return 'Rehber Öğretmen';
    if (lower == 'ogrenci' || lower == 'öğrenci' || lower == 'student') return 'Öğrenci';
    if (lower == 'veli' || lower == 'parent') return 'Veli';
    if (lower == 'staff' || lower == 'personel') return 'Personel';
    if (lower == 'admin' || lower == 'manager') return 'Yönetici';
    return raw;
  }

  /// Yönetici rütbesine göre izlenebilecek kullanıcıları çekme
  Future<void> _loadSelectableUsers() async {
    setState(() => _isLoadingUsers = true);
    List<ChatUser> users = [];

    final roleLower = TurkishStringUtils.toLowerTr(widget.currentUserRole);
    final isGenelMudur = roleLower.contains('genel müdür') ||
        roleLower.contains('genel mudur') ||
        roleLower.contains('admin') ||
        roleLower.isEmpty ||
        roleLower == 'manager';
    final isMudur = roleLower.contains('mudur') || roleLower.contains('müdür');

    // 1. Use initial contacts first if available (loaded securely from main chat screen)
    if (widget.initialContacts != null && widget.initialContacts!.isNotEmpty) {
      for (var u in widget.initialContacts!) {
        final targetRole = TurkishStringUtils.toLowerTr(u.role ?? u.userType ?? '');
        bool canMonitor = false;
        if (isGenelMudur) {
          canMonitor = true;
        } else if (isMudur) {
          canMonitor = !targetRole.contains('genel müdür');
        } else {
          // Müdür Yardımcısı
          canMonitor = targetRole.contains('öğretmen') ||
              targetRole.contains('ogretmen') ||
              targetRole.contains('veli') ||
              targetRole.contains('öğrenci') ||
              targetRole.contains('ogrenci') ||
              targetRole.contains('teacher') ||
              targetRole.contains('student') ||
              targetRole.contains('parent');
        }

        if (canMonitor && u.id != _chatService.currentUserId) {
          users.add(ChatUser(
            id: u.id,
            name: u.name,
            userType: u.userType,
            role: _formatDisplayRole(u.role),
            avatarUrl: u.avatarUrl,
          ));
        }
      }
    }

    // 2. Fetch from Firestore with institutionId filter if users list is empty
    if (users.isEmpty) {
      try {
        Query usersQuery = FirebaseFirestore.instance.collection('users');
        if (widget.institutionId.isNotEmpty) {
          usersQuery = usersQuery.where('institutionId', isEqualTo: widget.institutionId);
        }

        final usersSnapshot = await usersQuery.get();
        for (var doc in usersSnapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final targetRole = TurkishStringUtils.toLowerTr(data['role'] ?? data['userType'] ?? data['type'] ?? '');
          final userId = data['uid'] ?? data['userId'] ?? doc.id;

          if (userId == _chatService.currentUserId || users.any((u) => u.id == userId)) continue;

          bool canMonitor = false;
          if (isGenelMudur) {
            canMonitor = true;
          } else if (isMudur) {
            canMonitor = !targetRole.contains('genel müdür');
          } else {
            canMonitor = targetRole.contains('öğretmen') ||
                targetRole.contains('ogretmen') ||
                targetRole.contains('veli') ||
                targetRole.contains('öğrenci') ||
                targetRole.contains('ogrenci') ||
                targetRole.contains('teacher') ||
                targetRole.contains('student') ||
                targetRole.contains('parent');
          }

          if (canMonitor) {
            final rawRole = data['roleTitle'] ?? data['title'] ?? data['branch'] ?? data['role'] ?? data['type'];
            users.add(ChatUser(
              id: userId,
              name: data['fullName'] ?? data['name'] ?? '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim(),
              userType: data['type'] ?? data['userType'] ?? 'staff',
              role: _formatDisplayRole(rawRole),
              avatarUrl: data['photoUrl'] ?? data['avatarUrl'],
            ));
          }
        }
      } catch (e) {
        debugPrint("İzlenebilir kullanıcılar Firestore sorgu hatası: $e");
      }
    }

    // Türkçe Alfabeye göre sırala
    users.sort((a, b) => TurkishStringUtils.compareTr(a.name, b.name));

    if (mounted) {
      setState(() {
        _selectableUsers = users;
        _filteredSelectableUsers = users;
        _isLoadingUsers = false;
      });
    }
  }

  void _onUserSearch(String query) {
    setState(() {
      _searchQuery = query;
      final normalized = TurkishStringUtils.normalizeForSearch(query);
      if (normalized.isEmpty) {
        _filteredSelectableUsers = _selectableUsers;
      } else {
        _filteredSelectableUsers = _selectableUsers.where((u) {
          final name = TurkishStringUtils.normalizeForSearch(u.name);
          final role = TurkishStringUtils.normalizeForSearch(u.role ?? '');
          return name.contains(normalized) || role.contains(normalized);
        }).toList();
      }
    });
  }

  String _getConversationTitle(Conversation conv) {
    if (conv.isGroup && conv.chatName != null && conv.chatName!.isNotEmpty) {
      return '👥 ${conv.chatName}';
    }

    final targetId = _selectedTargetUser?.id;
    final otherParticipantId = conv.participantIds.firstWhere(
      (id) => id != targetId,
      orElse: () => '',
    );

    if (otherParticipantId.isNotEmpty) {
      final foundUser = _selectableUsers.firstWhere(
        (u) => u.id == otherParticipantId,
        orElse: () => ChatUser(id: otherParticipantId, name: ''),
      );
      if (foundUser.name.isNotEmpty) {
        return foundUser.name;
      }
    }

    if (conv.chatName != null && conv.chatName!.isNotEmpty) {
      return conv.chatName!;
    }

    return 'Sohbet (${conv.id.length > 6 ? conv.id.substring(0, 6) : conv.id})';
  }

  Future<void> _selectTargetUser(ChatUser user) async {
    setState(() {
      _selectedTargetUser = user;
      _selectedConversation = null;
      _targetMessages = [];
    });

    List<Conversation> list = [];

    // Load target user's conversations
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('conversations')
          .where('participantIds', arrayContains: user.id)
          .get();

      list = snapshot.docs.map((doc) => Conversation.fromMap(doc.data(), doc.id)).toList();
      list.sort((a, b) {
        final aTime = a.lastMessage?.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.lastMessage?.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

      // Resolve missing participant names for 1-on-1 chats
      for (var conv in list) {
        for (var pid in conv.participantIds) {
          if (pid != user.id && !_selectableUsers.any((u) => u.id == pid)) {
            try {
              final uDoc = await FirebaseFirestore.instance.collection('users').doc(pid).get();
              if (uDoc.exists) {
                final d = uDoc.data()!;
                _selectableUsers.add(ChatUser(
                  id: pid,
                  name: d['fullName'] ?? d['name'] ?? '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim(),
                  role: _formatDisplayRole(d['roleTitle'] ?? d['title'] ?? d['role']),
                ));
              } else {
                final sDoc = await FirebaseFirestore.instance.collection('students').doc(pid).get();
                if (sDoc.exists) {
                  final sd = sDoc.data()!;
                  _selectableUsers.add(ChatUser(
                    id: pid,
                    name: sd['fullName'] ?? '${sd['name']} ${sd['surname']}',
                    role: 'Öğrenci',
                  ));
                }
              }
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint("İzlenen sohbetler yüklenirken hata: $e");
    }

    if (mounted) {
      setState(() {
        _targetConversations = list;
      });
    }
  }

  Future<void> _loadConversationMessages(Conversation conversation) async {
    setState(() {
      _selectedConversation = conversation;
      _isLoadingMessages = true;
    });

    List<ChatMessage> msgs = [];

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversation.id)
          .collection('messages')
          .orderBy('timestamp', descending: false)
          .get();

      msgs = snapshot.docs.map((doc) => ChatMessage.fromMap(doc.data(), doc.id)).toList();
    } catch (e) {
      debugPrint("İzlenen mesajlar yüklenirken hata: $e");
    }

    if (mounted) {
      setState(() {
        _targetMessages = msgs;
        _isLoadingMessages = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '👁️ Mesaj İzleme & Denetim Paneli',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              'Yönetici Özel Denetim Yetkisi',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
      body: Row(
        children: [
          // Left Sidebar: User Selector & Conversations
          SizedBox(
            width: 340,
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  // Target User Picker Button
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: InkWell(
                      onTap: _showUserSelectionModal,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.indigo.shade100),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.indigo,
                              backgroundImage: (_selectedTargetUser?.avatarUrl != null)
                                  ? NetworkImage(_selectedTargetUser!.avatarUrl!)
                                  : null,
                              child: (_selectedTargetUser?.avatarUrl == null)
                                  ? Text(
                                      _selectedTargetUser != null
                                          ? _selectedTargetUser!.name[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedTargetUser?.name ?? 'İzlenecek Kişiyi Seçin',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.indigo.shade900,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    _selectedTargetUser?.role ?? 'Tıklayıp listeden seçiniz',
                                    style: GoogleFonts.inter(fontSize: 11, color: Colors.blueGrey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down_circle_outlined, color: Colors.indigo),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),

                  // Target Conversations List
                  Expanded(
                    child: _selectedTargetUser == null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Lütfen yukarıdan izlemek istediğiniz kullanıcıyı seçiniz.',
                                style: GoogleFonts.inter(color: Colors.blueGrey.shade400, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : _targetConversations.isEmpty
                            ? Center(
                                child: Text(
                                  'Bu kullanıcının aktif sohbeti yok.',
                                  style: GoogleFonts.inter(color: Colors.blueGrey),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _targetConversations.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final conv = _targetConversations[index];
                                  final isSelected = conv.id == _selectedConversation?.id;
                                  final lastMsg = conv.lastMessage;

                                  return ListTile(
                                    selected: isSelected,
                                    selectedTileColor: Colors.indigo.shade50,
                                    leading: const CircleAvatar(
                                      backgroundColor: Colors.indigo,
                                      child: Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20),
                                    ),
                                    title: Text(
                                      _getConversationTitle(conv),
                                      style: GoogleFonts.inter(
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        fontSize: 14,
                                      ),
                                    ),
                                    subtitle: Text(
                                      lastMsg?.content ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(fontSize: 12),
                                    ),
                                    onTap: () => _loadConversationMessages(conv),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),

          // Right Panel: Read-only Message Audit Timeline
          Expanded(
            child: _selectedConversation == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.remove_red_eye_outlined, size: 64, color: Colors.indigo.shade200),
                        const SizedBox(height: 16),
                        Text(
                          'Detaylarını incelemek istediğiniz sohbeti soldan seçiniz.',
                          style: GoogleFonts.inter(fontSize: 15, color: Colors.blueGrey.shade600, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )
                : _isLoadingMessages
                    ? const Center(child: CircularProgressIndicator())
                    : Container(
                        color: const Color(0xFFEFEAE2),
                        child: Column(
                          children: [
                            // Header Banner
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              color: Colors.white,
                              child: Row(
                                children: [
                                  const Icon(Icons.shield_outlined, color: Colors.indigo),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Salt Okunur Denetim Akışı: ${_selectedTargetUser?.name} ↔ ${_getConversationTitle(_selectedConversation!)}',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.indigo.shade900,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'DENETİM MODU',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),

                            // Messages List
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _targetMessages.length,
                                itemBuilder: (context, index) {
                                  final msg = _targetMessages[index];
                                  final isTargetSender = msg.senderId == _selectedTargetUser?.id;

                                  return Align(
                                    alignment: isTargetSender ? Alignment.centerRight : Alignment.centerLeft,
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(12),
                                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.5),
                                      decoration: BoxDecoration(
                                        color: isTargetSender ? const Color(0xFFD9FDD3) : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 2, offset: const Offset(0, 1)),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isTargetSender ? (_selectedTargetUser?.name ?? 'İzlenen Kişi') : 'Karşı Taraf',
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                              color: Colors.indigo,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            msg.content,
                                            style: GoogleFonts.inter(fontSize: 14, color: Colors.black87),
                                          ),
                                          const SizedBox(height: 4),
                                          Align(
                                            alignment: Alignment.bottomRight,
                                            child: Text(
                                              DateFormat('dd.MM.yyyy HH:mm').format(msg.timestamp),
                                              style: GoogleFonts.inter(fontSize: 10, color: Colors.grey),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _showUserSelectionModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'İzlenecek Kişiyi Seçin',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      _onUserSearch(val);
                      setModalState(() {});
                    },
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Kişi ismi veya rol arayın (ör: Anıl)...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _filteredSelectableUsers.isEmpty
                        ? const Center(child: Text('Yetkiniz dâhilinde kişi bulunamadı.'))
                        : ListView.separated(
                            itemCount: _filteredSelectableUsers.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final user = _filteredSelectableUsers[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.indigo,
                                  backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
                                  child: user.avatarUrl == null ? Text(user.name[0].toUpperCase(), style: const TextStyle(color: Colors.white)) : null,
                                ),
                                title: Text(user.name, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                                subtitle: Text(user.role ?? user.userType ?? '', style: GoogleFonts.inter(fontSize: 12)),
                                onTap: () {
                                  Navigator.pop(context);
                                  _selectTargetUser(user);
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
      },
    );
  }
}
