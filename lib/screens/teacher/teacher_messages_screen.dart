import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../school/school_types/chat/chat_models.dart';
import '../school/school_types/chat/chat_list_widget.dart';
import '../school/school_types/chat/chat_detail_widget.dart';
import '../../services/chat_service.dart';
import '../../services/user_permission_service.dart';
import 'dart:async';

class TeacherMessagesScreen extends StatefulWidget {
  final String institutionId;

  const TeacherMessagesScreen({
    Key? key,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<TeacherMessagesScreen> createState() => _TeacherMessagesScreenState();
}

class _TeacherMessagesScreenState extends State<TeacherMessagesScreen>
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
  Map<String, dynamic>? userData;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUserAndData();
  }

  Future<void> _loadUserAndData() async {
    userData = await UserPermissionService.loadUserData();
    _loadConversations();
    _loadContacts();
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

      if (query.isEmpty) {
        _filteredConversations = _conversations.where((c) => !c.isArchived).toList();
      } else {
        _filteredConversations = _conversations.where((c) {
          return c.chatName!.toLowerCase().contains(lowerQuery) && !c.isArchived;
        }).toList();
      }

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

  Future<void> _loadConversations() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _conversationsSubscription?.cancel();
    _conversationsSubscription = _chatService.getConversations(user.uid).listen((conversations) {
      if (mounted) {
        setState(() {
          _conversations = conversations;
          _onSearchChanged(_searchController.text);
        });
      }
    });
  }

  Future<void> _loadContacts() async {
    if (mounted) setState(() => _isLoadingContacts = true);
    List<ChatUser> loadedContacts = [];

    try {
      // Doğru ID ve Kurum bilgisini al
      final teacherId = userData?['id'] ?? FirebaseAuth.instance.currentUser?.uid;
      final instId = (userData?['institutionId'] ?? widget.institutionId ?? "").toString().toUpperCase();
      final teacherSchoolTypes = List<String>.from(userData?['schoolTypes'] ?? []);

      debugPrint('🔍 Mesaj Rehberi - TeacherId: $teacherId, InstId: "$instId", SchoolTypes: $teacherSchoolTypes');

      // 1. Yöneticileri Getir
      final List<String> managerRoles = [
        'Kurum Yöneticisi', 'Genel Müdür', 'Müdür', 'Müdür Yardımcısı', 'Yönetici',
        'genel_mudur', 'mudur', 'mudur_yardimcisi', 'admin', 'Personel'
      ];

      final managersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: instId)
          .where('role', whereIn: managerRoles)
          .get();

      debugPrint('   - Bulunan yönetici/personel sayısı: ${managersSnap.docs.length}');

      for (var doc in managersSnap.docs) {
        if (doc.id == teacherId) continue;
        final data = doc.data();
        
        // Eğer yönetici ise veya ortak okul türü varsa veya öğretmenin okul türü hiç tanımlanmamışsa göster
        final managerSchoolTypes = List<String>.from(data['schoolTypes'] ?? []);
        bool isRelevant = data['role'] == 'Kurum Yöneticisi' || 
                         data['role'] == 'genel_mudur' ||
                         data['role'] == 'Genel Müdür' ||
                         teacherSchoolTypes.isEmpty || // Öğretmene tür tanımlı değilse hepsini görsün
                         managerSchoolTypes.any((t) => teacherSchoolTypes.contains(t));

        if (isRelevant) {
          loadedContacts.add(ChatUser(
            id: doc.id,
            name: data['fullName'] ?? 'Yönetici',
            userType: 'staff',
            role: data['role'],
            avatarUrl: data['photoUrl'],
          ));
        }
      }

      // 2. Tanımlı Öğrencileri Getir (Ders atamaları üzerinden)
      debugPrint('   🔍 Ders atamaları aranıyor...');
      
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final assignQueries = [
         FirebaseFirestore.instance.collection('lessonAssignments')
            .where('institutionId', isEqualTo: instId)
            .where('teacherIds', arrayContains: teacherId).get(),
         if (currentUid != null && currentUid != teacherId)
            FirebaseFirestore.instance.collection('lessonAssignments')
               .where('institutionId', isEqualTo: instId)
               .where('teacherIds', arrayContains: currentUid).get(),
         FirebaseFirestore.instance.collection('lessonAssignments')
            .where('teacherIds', arrayContains: teacherId).get(), // Global fallback
      ];

      final assignSnaps = await Future.wait(assignQueries);
      final Set<String> classIds = {};
      
      for (var snap in assignSnaps) {
        for (var doc in snap.docs) {
          final data = doc.data();
          final cid = data['classId']?.toString();
          if (cid != null) {
            // Sadece doğru kuruma ait sınıf olduğundan emin ol (global fallback'ten gelenler için)
            final docInstId = (data['institutionId'] ?? "").toString().toUpperCase();
            if (instId.isEmpty || docInstId == instId) {
              classIds.add(cid);
            }
          }
        }
      }

      debugPrint('   - Benzersiz Sınıf Sayısı: ${classIds.length}');

      if (classIds.isNotEmpty) {
        final List<String> classIdList = classIds.toList();
        for (var i = 0; i < classIdList.length; i += 10) {
          final chunk = classIdList.skip(i).take(10).toList();
          final studentsSnap = await FirebaseFirestore.instance
              .collection('students')
              .where('classId', whereIn: chunk)
              .get();

          debugPrint('      - Sınıf chunk ${i/10} öğrenci: ${studentsSnap.docs.length}');

          for (var doc in studentsSnap.docs) {
            final data = doc.data();
            final sId = data['uid'] ?? doc.id;
            if (!loadedContacts.any((c) => c.id == sId)) {
              loadedContacts.add(ChatUser(
                id: sId,
                name: data['fullName'] ?? 'Öğrenci',
                userType: 'student',
                role: data['className'] ?? 'Öğrenci',
                avatarUrl: data['photoUrl'],
              ));
            }
          }
        }
        
        // 3. Velileri Getir
        final studentIds = loadedContacts.where((u) => u.userType == 'student').map((u) => u.id).toList();
        if (studentIds.isNotEmpty) {
          for (var i = 0; i < studentIds.length; i += 10) {
            final chunk = studentIds.skip(i).take(10).toList();
            final parentsSnap = await FirebaseFirestore.instance
                .collection('users')
                .where('role', isEqualTo: 'Veli')
                .where('studentIds', arrayContainsAny: chunk)
                .get();

            for (var doc in parentsSnap.docs) {
              final data = doc.data();
              if (!loadedContacts.any((c) => c.id == doc.id)) {
                loadedContacts.add(ChatUser(
                  id: doc.id,
                  name: '${data['fullName']} (Veli)',
                  userType: 'parent',
                  role: 'Veli',
                  avatarUrl: data['photoUrl'],
                ));
              }
            }
          }
        }
      }

      loadedContacts.sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      debugPrint('Hata (Mesaj Kişileri): $e');
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
      }
      _selectedConversation = existing;

      final isWide = MediaQuery.of(context).size.width > 800;
      if (!isWide) {
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

  Future<void> _handleForwardMessages(List<ChatUser> users, ChatMessage message) async {
    int successCount = 0;
    for (var user in users) {
      String conversationId;
      final existing = _conversations.firstWhere(
        (c) => c.participantIds.contains(user.id),
        orElse: () => Conversation(id: '', participantIds: []),
      );

      if (existing.id.isNotEmpty) {
        conversationId = existing.id;
      } else {
        conversationId = await _chatService.createConversation([
          _chatService.currentUserId!,
          user.id
        ]);
      }

      final forwardedMsg = message.copyWith(
        senderId: _chatService.currentUserId!,
        timestamp: DateTime.now(),
        isForwarded: true,
      );

      await _chatService.sendMessage(conversationId, forwardedMsg);
      successCount++;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$successCount kişiye iletildi.'))
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: Colors.indigo,
            title: _isSearching
                ? TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Ara...',
                      hintStyle: TextStyle(color: Colors.white70),
                      border: InputBorder.none,
                    ),
                    onChanged: _onSearchChanged,
                    autofocus: true,
                  )
                : const Text('Mesajlaşma', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _isSearching = !_isSearching;
                    if (!_isSearching) {
                      _searchController.clear();
                      _onSearchChanged('');
                    }
                  });
                },
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(text: 'Sohbetler'),
                Tab(text: 'Kişiler'),
              ],
            ),
          ),
          body: isWide ? _buildWideLayout() : _buildMobileLayout(),
        );
      },
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        SizedBox(
          width: 350,
          child: TabBarView(
            controller: _tabController,
            children: [
              ChatListWidget(
                conversations: _filteredConversations,
                selectedConversationId: _selectedConversation?.id,
                onConversationSelected: (c) => setState(() => _selectedConversation = c),
                contacts: _contacts,
              ),
              _buildContactsList(),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selectedConversation != null
              ? ChatDetailWidget(
                  key: ValueKey(_selectedConversation!.id),
                  conversation: _selectedConversation!,
                  contacts: _contacts,
                )
              : const Center(child: Text('Bir sohbet seçin')),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return TabBarView(
      controller: _tabController,
      children: [
        ChatListWidget(
          conversations: _filteredConversations,
          onConversationSelected: (c) {
            setState(() => _selectedConversation = c);
            final isWide = MediaQuery.of(context).size.width > 800;
            if (!isWide) {
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
            }
          },
          contacts: _contacts,
        ),
        _buildContactsList(),
      ],
    );
  }

  Widget _buildContactsList() {
    if (_isLoadingContacts) return const Center(child: CircularProgressIndicator());
    if (_filteredContacts.isEmpty) return const Center(child: Text('Kişi bulunamadı.'));

    final managers = _filteredContacts.where((u) => u.userType == 'staff').toList();
    final students = _filteredContacts.where((u) => u.userType == 'student').toList();
    final parents = _filteredContacts.where((u) => u.userType == 'parent').toList();

    return ListView(
      children: [
        if (managers.isNotEmpty) ...[
          _buildSectionHeader('Yöneticiler'),
          ...managers.map(_buildContactTile),
        ],
        if (students.isNotEmpty) ...[
          _buildSectionHeader('Öğrenciler'),
          ...students.map(_buildContactTile),
        ],
        if (parents.isNotEmpty) ...[
          _buildSectionHeader('Veliler'),
          ...parents.map(_buildContactTile),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
    );
  }

  Widget _buildContactTile(ChatUser user) {
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
        child: user.avatarUrl == null ? Text(user.name[0].toUpperCase()) : null,
      ),
      title: Text(user.name),
      subtitle: Text(user.role ?? ''),
      onTap: () => _startConversationWith(user),
    );
  }
}
