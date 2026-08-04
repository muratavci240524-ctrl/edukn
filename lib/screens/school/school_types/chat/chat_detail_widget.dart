import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'chat_models.dart';
import 'call/call_models.dart';
import 'call/call_service.dart';
import 'call/call_screen_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'package:flutter/foundation.dart'; // for kIsWeb
import 'forward_selection_sheet.dart';
import '../../../../../services/chat_service.dart';

class ChatDetailWidget extends StatefulWidget {
  final Conversation conversation;
  final VoidCallback? onBack; // For mobile to go back
  final List<ChatUser> contacts;
  final Function(List<ChatUser>, ChatMessage)? onForwardMessages;

  const ChatDetailWidget({
    Key? key,
    required this.conversation,
    this.onBack,
    this.contacts = const [],
    this.onForwardMessages,
  }) : super(key: key);

  @override
  State<ChatDetailWidget> createState() => _ChatDetailWidgetState();
}

class _ChatDetailWidgetState extends State<ChatDetailWidget> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Dummy messages for demo
  List<ChatMessage> _messages = [];

  // Cache for local files (mock backend storage)
  // ID -> Map: {'bytes': Uint8List?, 'path': String?, 'name': String}
  final Map<String, PlatformFile> _localFiles = {};

  // Audio
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  String? _currentlyPlayingId;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _durationSubscription;

  final ChatService _chatService = ChatService();
  StreamSubscription<List<ChatMessage>>? _messagesSubscription;
  late String _conversationId;

  // UI State
  String? _hoveredMessageId;
  ChatMessage? _replyingTo;
  bool _showScrollToBottom = false;

  void _toggleStar(String messageId) {
    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final msg = _messages[index];
        final newStarredState = !msg.isStarred;

        final updatedMsg = msg.copyWith(isStarred: newStarredState);
        _messages[index] = updatedMsg;

        // Persist to Firestore database!
        _chatService.toggleStarMessage(widget.conversation.id, messageId, newStarredState);

        // Sync with Global List
        if (newStarredState) {
          if (!globalStarredMessages.any((m) => m.id == msg.id)) {
            globalStarredMessages.add(updatedMsg);
          }
        } else {
          globalStarredMessages.removeWhere((m) => m.id == msg.id);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStarredState ? 'Mesaj yıldızlandı ⭐' : 'Yıldız kaldırıldı',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  void _replyToMessage(ChatMessage message) {
    setState(() {
      _replyingTo = message;
    });
    // Focus or ensure input is visible?
  }

  void _dismissReply() {
    setState(() {
      _replyingTo = null;
    });
  }

  int _activeChannelIndex = 0; // 0: Öğrenci, 1: Veli

  /// Karşıdaki kullanıcının öğrenci olup olmadığını kontrol eder
  bool get _isOtherUserStudent {
    if (widget.conversation.isGroup) return false;
    final currentUserId = _chatService.currentUserId;
    final otherId = widget.conversation.participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );
    if (otherId.isEmpty) return false;
    try {
      final user = widget.contacts.firstWhere(
        (u) => u.id == otherId,
        orElse: () => ChatUser(id: otherId, name: ''),
      );
      return user.userType == 'student';
    } catch (_) {
      return false;
    }
  }

  List<ChatMessage> get _displayMessages {
    // Öğrenci olmayan kişilerle sohbette kanal filtrelemesi yapma
    if (!_isOtherUserStudent) {
      return _messages.toList();
    }
    final targetChannel = _activeChannelIndex == 0 ? 'student' : 'parent';
    return _messages.where((msg) {
      if (msg.recipientChannel == null) {
        // Untagged legacy messages belong to student channel
        return targetChannel == 'student';
      }
      return msg.recipientChannel == targetChannel;
    }).toList();
  }

  bool _isSearchingInChat = false;
  final TextEditingController _chatSearchController = TextEditingController();
  final List<int> _matchingMessageIndices = [];
  int _currentMatchIndex = 0;

  void _onChatSearchQueryChanged(String query) {
    setState(() {
      _matchingMessageIndices.clear();
      _currentMatchIndex = 0;
      if (query.trim().isNotEmpty) {
        final normalized = TurkishStringUtils.normalizeForSearch(query);
        final list = _displayMessages;
        for (int i = 0; i < list.length; i++) {
          final content = TurkishStringUtils.normalizeForSearch(list[i].content);
          if (content.contains(normalized)) {
            _matchingMessageIndices.add(i);
          }
        }
      }
    });

    if (_matchingMessageIndices.isNotEmpty) {
      _scrollToMatchingMessage(0);
    }
  }

  void _scrollToMatchingMessage(int index) {
    if (index >= 0 && index < _matchingMessageIndices.length) {
      setState(() {
        _currentMatchIndex = index;
      });
      final targetMsgIndex = _matchingMessageIndices[index];
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final totalMsgs = _displayMessages.length;
        final calcOffset = (targetMsgIndex / (totalMsgs > 1 ? totalMsgs : 1)) * maxScroll;

        _scrollController.animateTo(
          calcOffset.clamp(0.0, maxScroll),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _forwardMessage(ChatMessage message) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ForwardSelectionSheet(
        contacts: widget.contacts,
        onForward: (selectedUsers) {
          if (widget.onForwardMessages != null) {
            widget.onForwardMessages!(selectedUsers, message);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${selectedUsers.length} kişiye iletildi.'),
              ),
            );
          }
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversation.id;

    // Subscribe if real conversation
    if (!_conversationId.startsWith('temp_')) {
      _subscribeToMessages();
    } else {
      // Is new/temp, messages empty initially
      _messages = [];
    }

    // _loadMockMessages(); // Removed as per request
    // Rebuild when text changes to toggle send button state
    _messageController.addListener(() {
      setState(() {});
    });

    // Audio Player Listeners
    _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((
      state,
    ) {
      if (state == PlayerState.completed) {
        setState(() {
          _currentlyPlayingId = null;
          _currentPosition = Duration.zero;
        });
      }
    });

    _markAsRead(); // Initial mark as read

    _positionSubscription = _audioPlayer.onPositionChanged.listen((pos) {
      setState(() {
        _currentPosition = pos;
      });
    });

    _durationSubscription = _audioPlayer.onDurationChanged.listen((dur) {
      setState(() {
        _totalDuration = dur;
      });
    });

    _scrollController.addListener(() {
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final currentScroll = _scrollController.offset;
        final shouldShow = maxScroll - currentScroll > 50;
        if (shouldShow != _showScrollToBottom) {
          setState(() {
            _showScrollToBottom = shouldShow;
          });
        }
      }
    });
  }

  bool _isCallStarting = false;

  void _handleStartCall(CallType callType) async {
    // Zaten bir arama başlatılıyorsa engelle
    if (_isCallStarting) return;
    // Zaten aktif bir arama varsa engelle
    if (CallScreenDialog.hasActiveCall) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Zaten aktif bir arama mevcut.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _isCallStarting = true;

    try {
      // Veli - Öğretmen saat kısıtlaması (08:30 - 18:00)
      final isManager = _chatService.isManagerRole('');
      if (!_chatService.isWithinWorkingHours(isAdminOrManager: isManager)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sesli / Görüntülü arama mesai saatleri (08:30 - 18:00) dışındadır. Lütfen mesai saatlerinde tekrar deneyiniz.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final partnerId = widget.conversation.participantIds.firstWhere(
        (id) => id != _chatService.currentUserId,
        orElse: () => '',
      );
      if (partnerId.isEmpty) return;

      final partnerUser = widget.contacts.firstWhere(
        (u) => u.id == partnerId,
        orElse: () => ChatUser(
          id: partnerId,
          name: widget.conversation.chatName ?? 'Kullanıcı',
          role: 'Kullanıcı',
        ),
      );

      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final currentUser = widget.contacts.firstWhere(
        (u) => u.id == currentUid,
        orElse: () => ChatUser(id: currentUid, name: _chatService.currentUserEmail ?? 'Kullanıcı', role: 'Personel'),
      );

      final session = await CallService().startCall(
        receiverId: partnerId,
        receiverName: partnerUser.name,
        receiverRole: partnerUser.role,
        receiverAvatar: partnerUser.avatarUrl,
        callType: callType,
        callerName: currentUser.name,
        callerRole: currentUser.role,
        callerAvatar: currentUser.avatarUrl,
      );

      if (session != null && mounted) {
        CallScreenDialog.showCall(
          context: context,
          callSession: session,
          isIncoming: false,
        );
      }
    } on CallBusyException catch (e) {
      // 📵 Meşgul hatası - kullanıcıya bildir
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.phone_disabled, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(e.message)),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Arama başlatma hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Arama başlatılamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _isCallStarting = false;
    }
  }

  void _subscribeToMessages() {
    _messagesSubscription?.cancel();
    _messagesSubscription = _chatService.getMessages(_conversationId).listen((
      messages,
    ) {
      if (mounted) {
        setState(() {
          _messages = messages;
        });
        _markAsRead(); // Mark as read on new message receipt
        _scrollToBottom();
      }
    });
  }

  Future<void> _markAsRead() async {
    if (!_conversationId.startsWith('temp_')) {
      await _chatService.markAsRead(_conversationId);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _messagesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final text = _messageController.text.trim();
    _messageController.clear();

    // Check if we need to create conversation first
    if (_conversationId.startsWith('temp_')) {
      final participants = widget.conversation.participantIds;
      // Ensure current user is in participants? (Service assumes so if passed, or we add self)
      // widget.conversation.participantIds from ChatScreen startConversationWith usually has just the other person?
      // Let's check ChatScreen. It adds [user.id].
      // ChatScreen forwards logic sends [currentUser, otherUser].
      // We should ensure we include current user.
      final allParticipants = List<String>.from(participants);
      if (_chatService.currentUserId != null &&
          !allParticipants.contains(_chatService.currentUserId)) {
        allParticipants.add(_chatService.currentUserId!);
      }

      _conversationId = await _chatService.createConversation(allParticipants);
      _subscribeToMessages();
    }

    final newMessage = ChatMessage(
      id: '', // Service handles ID
      senderId: _chatService.currentUserId ?? 'me',
      content: text,
      timestamp: DateTime.now(),
      repliedMessage: _replyingTo, // Set reply reference
      recipientChannel: _activeChannelIndex == 0 ? 'student' : 'parent',
    );

    setState(() {
      _replyingTo = null; // Clear reply state
    });

    await _chatService.sendMessage(_conversationId, newMessage);
    _scrollToBottom();
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        // We need a path mostly for mobile, but on web it handles it.
        // On web we pass Stream/Bytes usually or it returns Blob URL.
        // For simplicity we use standard start.

        // Use mp3 or m4a on supported platforms.
        // On web Record outputs Blob URL or PCM?
        // Let's rely on default encoder.

        await _audioRecorder.start(const RecordConfig(), path: '');
        setState(() {
          _isRecording = true;
        });
      }
    } catch (e) {
      debugPrint('Error starting record: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
      });

      if (path != null) {
        if (_conversationId.startsWith('temp_')) {
          // handle creation repeated logic - duplicate code but keeps it local
          final allParticipants = List<String>.from(
            widget.conversation.participantIds,
          );
          if (_chatService.currentUserId != null &&
              !allParticipants.contains(_chatService.currentUserId)) {
            allParticipants.add(_chatService.currentUserId!);
          }
          _conversationId = await _chatService.createConversation(
            allParticipants,
          );
          _subscribeToMessages();
        }

        final audioMsg = ChatMessage(
          id: '',
          senderId: _chatService.currentUserId ?? 'me',
          content: path, // We store the path/url as content for audio
          timestamp: DateTime.now(),
          type: MessageType.audio,
          recipientChannel: _activeChannelIndex == 0 ? 'student' : 'parent',
        );

        await _chatService.sendMessage(_conversationId, audioMsg);
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Error stopping record: $e');
    }
  }

  // Toggle Logic
  void _handleMicButton() {
    if (_isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  Future<void> _pickFile() async {
    // on Web bytes is populated with pickFiles().
    // We explicitly request data to be safe cross-platform.
    FilePickerResult? result = await FilePicker.pickFiles(
      withData: true,
    );

    if (result != null) {
      PlatformFile file = result.files.first;
      String fileName = file.name;
      String id = DateTime.now()
          .toString(); // Local storage still needs ID key usually
      // Store locally for file access before upload (mock upload)
      _localFiles[id] = file;
      // Ideally we upload to Storage here, get URL.
      // For MVP we just use fileName/local ID reference or mock.
      // Firestore will just store filename.

      if (_conversationId.startsWith('temp_')) {
        final allParticipants = List<String>.from(
          widget.conversation.participantIds,
        );
        if (_chatService.currentUserId != null &&
            !allParticipants.contains(_chatService.currentUserId)) {
          allParticipants.add(_chatService.currentUserId!);
        }
        _conversationId = await _chatService.createConversation(
          allParticipants,
        );
        _subscribeToMessages();
      }

      final fileMsg = ChatMessage(
        id: id, // Use generated ID for local file map mostly
        senderId: _chatService.currentUserId ?? 'me',
        content: fileName,
        timestamp: DateTime.now(),
        type: MessageType.file,
        recipientChannel: _activeChannelIndex == 0 ? 'student' : 'parent',
      );

      // We pass `id` to service but service ignores it for doc ID usually,
      // BUT we used ID for localFiles map.
      // ChatService creates new doc ID.
      // So _localFiles map might break if we rely on docId matching initial ID.
      // We should probably use file path or name or upload it.
      // For now, we persist message.
      await _chatService.sendMessage(_conversationId, fileMsg);

      _scrollToBottom();
    }
  }

  void _showEmojiPicker() {
    // Dismiss keyboard if open
    FocusScope.of(context).unfocus();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true, // Allow full height control
      builder: (context) {
        return Container(
          height: 350, // Talle picker
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2),
            ],
          ),
          child: DefaultTabController(
            length: _emojiCategories.length,
            child: Column(
              children: [
                // Handle/Gripper
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 5),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Category Tabs
                TabBar(
                  isScrollable: true,
                  labelColor: const Color(0xFF00A884),
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: const Color(0xFF00A884),
                  indicatorSize: TabBarIndicatorSize.label,
                  tabs: _emojiCategories.keys.map((category) {
                    return Tab(
                      icon: Text(
                        _getCategoryIcon(category),
                        style: const TextStyle(fontSize: 20),
                      ),
                    );
                  }).toList(),
                ),
                const Divider(height: 1),
                // Grids
                Expanded(
                  child: TabBarView(
                    children: _emojiCategories.values.map((emojis) {
                      return GridView.builder(
                        padding: const EdgeInsets.all(10),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 8,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                            ),
                        itemCount: emojis.length,
                        itemBuilder: (context, index) {
                          return InkWell(
                            onTap: () {
                              _messageController.text =
                                  _messageController.text + emojis[index];
                              _messageController.selection =
                                  TextSelection.fromPosition(
                                    TextPosition(
                                      offset: _messageController.text.length,
                                    ),
                                  );
                              setState(() {});
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Center(
                              child: Text(
                                emojis[index],
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          );
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getCategoryIcon(String category) {
    switch (category) {
      case 'Smileys':
        return '😀';
      case 'Animals':
        return '🐻';
      case 'Food':
        return '🍔';
      case 'Activities':
        return '⚽';
      case 'Objects':
        return '💡';
      default:
        return '😀';
    }
  }

  // Categorized Emojis for "Beautiful" look
  final Map<String, List<String>> _emojiCategories = {
    'Smileys': [
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '😂',
      '🤣',
      '🥲',
      '😊',
      '😇',
      '🙂',
      '🙃',
      '😉',
      '😌',
      '😍',
      '🥰',
      '😘',
      '😗',
      '😙',
      '😚',
      '😋',
      '😛',
      '😝',
      '😜',
      '🤪',
      '🤨',
      '🧐',
      '🤓',
      '😎',
      '🥸',
      '🤩',
      '🥳',
      '😏',
      '😒',
      '😞',
      '😔',
      '😟',
      '😕',
      '🙁',
      '☹️',
      '😣',
      '😖',
      '😫',
      '😩',
      '🥺',
      '😢',
      '😭',
      '😤',
      '😠',
    ],
    'Animals': [
      '🐶',
      '🐱',
      '🐭',
      '🐹',
      '🐰',
      '🦊',
      '🐻',
      '🐼',
      '🐻‍❄️',
      '🐨',
      '🐯',
      '🦁',
      'dV',
      '🐮',
      '🐷',
      '🐽',
      '🐸',
      '🐵',
      '🙈',
      '🙉',
      '🙊',
      '🐒',
      '🐔',
      '🐧',
      '🐦',
      '🐤',
      '🐣',
      '🐥',
      'duck',
      '🦅',
      '🦉',
      'bat',
      '🐺',
      '🐗',
      '🐴',
      '🦄',
      '🐝',
      '🪱',
      '🐛',
      '🦋',
    ],
    'Food': [
      '🍏',
      '🍎',
      '🍐',
      '🍊',
      '🍋',
      '🍌',
      '🍉',
      '🍇',
      '🍓',
      '🫐',
      '🍈',
      '🍒',
      '🍑',
      '🥭',
      '🍍',
      '🥥',
      '🥝',
      '🍅',
      '🍆',
      '🥑',
      '🥦',
      '🥬',
      '🥒',
      '🌶',
      '🫑',
      '🌽',
      '🥕',
      '🫒',
      '🧄',
      '🧅',
      '🥔',
      '🍠',
      '🥐',
      '🥯',
      '🍞',
      '🥖',
      '🥨',
      '🧀',
      '🥚',
      '🍳',
    ],
    'Activities': [
      '⚽',
      '🏀',
      '🏈',
      '⚾',
      '🥎',
      '🎾',
      '🏐',
      '🏉',
      '🥏',
      '🎱',
      '🪀',
      '🏓',
      '🏸',
      '🏒',
      '🏑',
      '🥍',
      '🏏',
      '🪃',
      '🥅',
      '⛳',
      '🪁',
      '🏹',
      '🎣',
      '🤿',
      '🥊',
      '🥋',
      '🎽',
      '🛹',
      '🛼',
      '🛷',
      '⛸',
      '🥌',
      '🎿',
      '⛷',
      '🏂',
      '🪂',
      '🏋️',
      '🤼',
      '🤸',
      '⛹️',
    ],
    'Objects': [
      '⌚',
      '📱',
      '📲',
      '💻',
      '⌨️',
      '🖥',
      '🖨',
      '🖱',
      '🖲',
      '🕹',
      '🗜',
      '💽',
      '💾',
      '💿',
      '📀',
      '📼',
      '📷',
      '📸',
      '📹',
      '🎥',
      '📽',
      '🎞',
      '📞',
      '☎️',
      '📟',
      '📠',
      '📺',
      '📻',
      '🎙',
      '🎚',
      '🎛',
      '🧭',
      '⏱',
      '⏲',
      '⏰',
      '🕰',
      '⌛',
      '⏳',
      '📡',
      '🔋',
    ],
  };

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildMessageContent(ChatMessage message, bool isMe) {
    // 1. Check for Reply
    Widget? replyWidget;
    if (message.repliedMessage != null) {
      final replied = message.repliedMessage!;
      replyWidget = Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(4),
          border: const Border(
            left: BorderSide(color: Colors.indigo, width: 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              replied.senderId == 'me' ? 'Siz' : 'Kişi',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: Colors.indigo,
              ),
            ),
            Text(
              replied.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
      );
    }

    // Check for Forwarded
    Widget? forwardedWidget;
    if (message.isForwarded) {
      forwardedWidget = Container(
        margin: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forward, size: 12, color: Colors.grey),
            const SizedBox(width: 4),
            Text(
              'İletildi',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    Widget contentWidget;
    if (message.type == MessageType.file) {
      contentWidget = InkWell(
        onTap: () async {
          // Check local cache first
          if (_localFiles.containsKey(message.id)) {
            final file = _localFiles[message.id]!;
            if (file.bytes != null) {
              await FileSaver.instance.saveFile(
                name: file.name,
                bytes: file.bytes!,
                ext: file.extension ?? '',
              );
            }
          } else {
            // Mock download for received files
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Dosya indiriliyor... (Mock)')),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.file_present_rounded,
                color: Colors.grey,
                size: 28,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.content,
                      style: TextStyle(
                        color: isMe ? Colors.black87 : Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Text(
                      'İndirmek için dokunun',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else if (message.type == MessageType.audio) {
      final isPlaying = _currentlyPlayingId == message.id;

      contentWidget = Container(
        width: 200,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              ),
              iconSize: 36,
              color: isMe ? Colors.grey.shade600 : const Color(0xFF00A884),
              onPressed: () async {
                if (isPlaying) {
                  await _audioPlayer.pause();
                  setState(() {
                    _currentlyPlayingId = null;
                  });
                } else {
                  await _audioPlayer.stop(); // Stop potential other
                  await _audioPlayer.play(UrlSource(message.content));
                  setState(() {
                    _currentlyPlayingId = message.id;
                  });
                }
              },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mock Visualizer
                  Container(
                    height: 4,
                    color: Colors.grey.shade400,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor:
                          isPlaying && _totalDuration.inMilliseconds > 0
                          ? _currentPosition.inMilliseconds /
                                _totalDuration.inMilliseconds
                          : 0,
                      child: Container(color: Colors.black54),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isPlaying
                        ? '${_currentPosition.inMinutes}:${(_currentPosition.inSeconds % 60).toString().padLeft(2, '0')}'
                        : 'Ses Kaydı',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.mic, size: 16, color: Colors.grey),
          ],
        ),
      );
    } else if (message.type == MessageType.call) {
      final isVideo = message.content.contains('Görüntülü') || message.content.contains('📹');
      final isMissed = message.content.contains('Cevapsız') || message.content.contains('Reddedildi');

      contentWidget = InkWell(
        onTap: () {
          final otherUser = widget.contacts.firstWhere(
            (u) => u.id == (isMe ? widget.conversation.participantIds.firstWhere((id) => id != message.senderId, orElse: () => '') : message.senderId),
            orElse: () => ChatUser(id: '', name: 'Kullanıcı'),
          );

          if (otherUser.id.isNotEmpty) {
            // Zaten aktif bir arama varsa engelle
            if (CallScreenDialog.hasActiveCall) return;

            final currentUser = widget.contacts.firstWhere(
              (u) => u.id == FirebaseAuth.instance.currentUser?.uid,
              orElse: () => ChatUser(id: '', name: 'Siz'),
            );

            CallService().startCall(
              receiverId: otherUser.id,
              receiverName: otherUser.name,
              receiverRole: otherUser.role,
              receiverAvatar: otherUser.avatarUrl,
              callType: isVideo ? CallType.video : CallType.voice,
              callerName: currentUser.name,
              callerRole: currentUser.role,
              callerAvatar: currentUser.avatarUrl,
            ).then((session) {
              if (session != null) {
            CallScreenDialog.showCall(
                  context: context,
                  callSession: session,
                  isIncoming: false,
                );
              }
            }).catchError((e) {
              if (e is CallBusyException && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade600),
                );
              }
            });
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isMissed ? Colors.red.shade50 : (isMe ? const Color(0xFFD9FDD3) : Colors.teal.shade50),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isMissed ? Colors.red.shade100 : (isMe ? Colors.white70 : Colors.teal.shade100),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isMissed
                      ? (isVideo ? Icons.videocam_off_rounded : Icons.phone_missed_rounded)
                      : (isVideo ? Icons.videocam_rounded : Icons.phone_in_talk_rounded),
                  color: isMissed ? Colors.red.shade700 : (isMe ? const Color(0xFF008069) : Colors.teal.shade800),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isMissed ? Colors.red.shade900 : const Color(0xFF111B21),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          size: 12,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            isMissed ? 'Geri aramak için dokunun' : 'Tıklayıp tekrar arayın',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      contentWidget = Text(
        message.content,
        style: const TextStyle(
          fontSize: 14.5,
          color: Color(0xFF111B21),
          height: 1.3,
        ),
      );
    }

    // Combine Forward + Reply + Content
    final children = <Widget>[];

    if (forwardedWidget != null) children.add(forwardedWidget);
    if (replyWidget != null) children.add(replyWidget);
    children.add(contentWidget);

    if (children.length > 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    } else {
      return contentWidget;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine chat title/image
    String chatTitle = widget.conversation.chatName ?? "Kullanıcı";
    String? chatImage = widget.conversation.chatImage;

    // Resolve name if it looks like a generic ID or default
    if (chatTitle.isEmpty || chatTitle.startsWith('Kullanıcı')) {
      final currentUserId = _chatService.currentUserId; // Use service directly
      final otherId = widget.conversation.participantIds.firstWhere(
        (id) => id != currentUserId,
        orElse: () => '',
      );

      if (otherId.isNotEmpty) {
        final user = widget.contacts.firstWhere(
          (u) => u.id == otherId,
          orElse: () => ChatUser(id: otherId, name: chatTitle), // Fallback
        );
        // Only update if we found a real user
        if (user.name != chatTitle && user.name != 'Kullanıcı $otherId') {
          chatTitle = user.name;
        } else if (user.name.isEmpty) {
          // If user not found in contacts, keep 'Kullanıcı' or try to show ID nicely?
          // But usually contacts should have it.
        }
        chatImage ??= user.avatarUrl;
      }
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFFF0F2F5),
            border: Border(
              bottom: BorderSide(color: Color(0xFFE0E0E0), width: 1),
            ),
          ),
          child: Row(
            children: [
              if (widget.onBack != null)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: widget.onBack,
                  color: Colors.grey.shade700,
                  splashRadius: 20,
                ),
              CircleAvatar(
                backgroundColor: Colors.grey.shade300,
                backgroundImage: chatImage != null
                    ? NetworkImage(chatImage!)
                    : null,
                child: chatImage == null
                    ? const Icon(Icons.person, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () {}, // Open contact info
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chatTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Builder(
                        builder: (context) {
                          // Find user details if possible
                          String subtitle = '';
                          try {
                            if (widget.conversation.participantIds.isNotEmpty) {
                              final partnerId = widget.conversation.participantIds.firstWhere((id) => id != _chatService.currentUserId, orElse: () => '');
                              final user = widget.contacts.firstWhere(
                                (u) => u.id == partnerId,
                                orElse: () => ChatUser(id: '', name: '', role: ''),
                              );
                              subtitle = user.role ?? 'Çevrimiçi';
                            }
                          } catch (_) {}

                          return Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.call_rounded),
                tooltip: 'Sesli Arama',
                onPressed: () => _handleStartCall(CallType.voice),
                color: Colors.indigo,
                splashRadius: 24,
              ),
              IconButton(
                icon: const Icon(Icons.videocam_rounded),
                tooltip: 'Görüntülü Arama',
                onPressed: () => _handleStartCall(CallType.video),
                color: Colors.indigo,
                splashRadius: 24,
              ),
              IconButton(
                icon: Icon(_isSearchingInChat ? Icons.close : Icons.search),
                tooltip: 'Sohbette Ara',
                onPressed: () {
                  setState(() {
                    _isSearchingInChat = !_isSearchingInChat;
                    if (!_isSearchingInChat) {
                      _chatSearchController.clear();
                      _matchingMessageIndices.clear();
                    }
                  });
                },
                color: Colors.indigo,
                splashRadius: 24,
              ),
            ],
          ),
        ),

        // In-Chat Message Search Bar Widget
        if (_isSearchingInChat)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatSearchController,
                    onChanged: _onChatSearchQueryChanged,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Sohbette mesaj aratın...',
                      prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      fillColor: const Color(0xFFF0F2F5),
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                if (_matchingMessageIndices.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '${_currentMatchIndex + 1} / ${_matchingMessageIndices.length}',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_up, color: Colors.indigo),
                    onPressed: _currentMatchIndex > 0
                        ? () => _scrollToMatchingMessage(_currentMatchIndex - 1)
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down, color: Colors.indigo),
                    onPressed: _currentMatchIndex < _matchingMessageIndices.length - 1
                        ? () => _scrollToMatchingMessage(_currentMatchIndex + 1)
                        : null,
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () {
                    setState(() {
                      _isSearchingInChat = false;
                      _chatSearchController.clear();
                      _matchingMessageIndices.clear();
                    });
                  },
                ),
              ],
            ),
          ),

        // Quick Student / Parent Channel Switcher Bar (sadece öğrenci ile sohbette gösterilir)
        if (_isOtherUserStudent)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _activeChannelIndex = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _activeChannelIndex == 0 ? Colors.indigo : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _activeChannelIndex == 0 ? Colors.indigo : Colors.transparent,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.school_rounded,
                          size: 16,
                          color: _activeChannelIndex == 0 ? Colors.white : Colors.indigo,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Öğrenciye Yaz',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _activeChannelIndex == 0 ? Colors.white : Colors.blueGrey.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _activeChannelIndex = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _activeChannelIndex == 1 ? const Color(0xFF008069) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _activeChannelIndex == 1 ? const Color(0xFF008069) : Colors.transparent,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.family_restroom_rounded,
                          size: 16,
                          color: _activeChannelIndex == 1 ? Colors.white : const Color(0xFF008069),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Velisine Yaz',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _activeChannelIndex == 1 ? Colors.white : Colors.blueGrey.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Messages Area
        Expanded(
          child: Container(
            color: const Color(0xFFEFEAE2), // Authentic WhatsApp Web BG
            child: Stack(
              children: [
                // Optional: Add a doodle pattern image here with low opacity
                // For now, solid color is fine for "Better" than previous.
                ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: _displayMessages.length,
                  itemBuilder: (context, index) {
                    final message = _displayMessages[index];
                    final isMe =
                        message.senderId == _chatService.currentUserId ||
                        message.senderId == 'me';

                    final isMatching = _isSearchingInChat && _matchingMessageIndices.contains(index);
                    final isCurrentFocus = isMatching && _matchingMessageIndices.isNotEmpty && _matchingMessageIndices[_currentMatchIndex] == index;

                    Color bubbleColor = isMe ? const Color(0xFFD9FDD3) : Colors.white;
                    if (isCurrentFocus) {
                      bubbleColor = const Color(0xFFFFD54F); // Vibrant Yellow for Active Search Focus
                    } else if (isMatching) {
                      bubbleColor = const Color(0xFFFFF59D); // Soft Yellow for Search Match
                    }

                    return MouseRegion(
                      onEnter: (_) => setState(() => _hoveredMessageId = message.id),
                      onExit: (_) => setState(() => _hoveredMessageId = null),
                      child: Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Stack(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.only(
                                left: 10,
                                right: 10,
                                top: 6,
                                bottom: 6,
                              ),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.65,
                                minWidth: 100,
                              ),
                              decoration: BoxDecoration(
                                color: bubbleColor,
                                border: isCurrentFocus ? Border.all(color: Colors.amber.shade900, width: 1.5) : null,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(12),
                                  topRight: const Radius.circular(12),
                                  bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(0),
                                  bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    offset: const Offset(0, 1),
                                    blurRadius: 1,
                                  ),
                                ],
                              ),
                              child: IntrinsicWidth(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildMessageContent(message, isMe),
                                    const SizedBox(height: 2),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        // Düzenlendi etiketi
                                        if (message.isEdited)
                                          Padding(
                                            padding: const EdgeInsets.only(right: 4),
                                            child: Text(
                                              'Düzenlendi',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontStyle: FontStyle.italic,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ),
                                        // Star Indicator
                                        if (message.isStarred)
                                          Padding(
                                            padding: const EdgeInsets.only(right: 4),
                                            child: Icon(
                                              Icons.star,
                                              size: 13,
                                              color: Colors.amber.shade800,
                                            ),
                                          ),
                                        Text(
                                          DateFormat.Hm().format(message.timestamp),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      if (isMe) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.done_all,
                                          size: 16,
                                          color: message.isRead
                                              ? const Color(0xFF53BDEB)
                                              : Colors.grey,
                                        ),
                                      ],
                                      const SizedBox(width: 4),

                                      // Downward arrow dropdown menu right next to checkmarks!
                                      SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: PopupMenuButton<String>(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          elevation: 4,
                                          icon: const Icon(
                                            Icons.keyboard_arrow_down,
                                            size: 16,
                                            color: Colors.grey,
                                          ),
                                          padding: EdgeInsets.zero,
                                          tooltip: 'İşlemler',
                                          onSelected: (value) async {
                                            if (value == 'reply') {
                                              _replyToMessage(message);
                                            } else if (value == 'edit') {
                                              _showEditMessageSheet(message, index);
                                            } else if (value == 'star') {
                                              _toggleStar(message.id);
                                            } else if (value == 'forward') {
                                              _forwardMessage(message);
                                            } else if (value == 'delete') {
                                              final isManager = _chatService.isManagerRole('');
                                              if (!isManager) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text('Mesaj silme yetkisi sadece okul yöneticilerine aittir.'),
                                                    backgroundColor: Colors.orange,
                                                  ),
                                                );
                                                return;
                                              }
                                              setState(() {
                                                _messages.removeAt(index);
                                              });
                                              await _chatService.deleteMessage(
                                                conversationId: widget.conversation.id,
                                                messageId: message.id,
                                                userRole: 'manager',
                                              );
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem(
                                              value: 'reply',
                                              height: 36,
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.reply, size: 16, color: Colors.indigo),
                                                  const SizedBox(width: 8),
                                                  Text('Yanıtla', style: GoogleFonts.inter(fontSize: 13)),
                                                ],
                                              ),
                                            ),
                                            // Düzenle seçeneği: sadece kendi mesajım + text + 10dk içinde
                                            if (isMe && message.type == MessageType.text &&
                                                DateTime.now().difference(message.timestamp).inMinutes < 10)
                                              PopupMenuItem(
                                                value: 'edit',
                                                height: 36,
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.edit_outlined, size: 16, color: Colors.teal),
                                                    const SizedBox(width: 8),
                                                    Text('Düzenle', style: GoogleFonts.inter(fontSize: 13)),
                                                  ],
                                                ),
                                              ),
                                            PopupMenuItem(
                                              value: 'forward',
                                              height: 36,
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.shortcut_rounded, size: 16, color: Colors.indigo),
                                                  const SizedBox(width: 8),
                                                  Text('İlet', style: GoogleFonts.inter(fontSize: 13)),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'star',
                                              height: 36,
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    message.isStarred ? Icons.star_border : Icons.star,
                                                    size: 16,
                                                    color: Colors.amber,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    message.isStarred ? 'Yıldızı Kaldır' : 'Yıldızla',
                                                    style: GoogleFonts.inter(fontSize: 13),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              height: 36,
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                                  const SizedBox(width: 8),
                                                  Text('Sil', style: GoogleFonts.inter(fontSize: 13, color: Colors.red)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                  },
                ),
                // Floating Scroll-to-Bottom Button (WhatsApp Web Style)
                if (_showScrollToBottom)
                Positioned(
                  bottom: 12,
                  right: 16,
                  child: InkWell(
                    onTap: () {
                      if (_scrollController.hasClients) {
                        _scrollController.animateTo(
                          _scrollController.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFF54656F),
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Input Area
        if (_replyingTo != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(
                top: BorderSide(color: Colors.grey.shade300),
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Yanıtlanıyor',
                        style: TextStyle(
                          color: Colors.indigo,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _replyingTo!.content,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: _dismissReply,
                  splashRadius: 20,
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFFF0F2F5),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 26),
                color: const Color(0xFF54656F),
                onPressed: _pickFile,
                tooltip: 'Medya Ekle',
                splashRadius: 20,
              ),
              IconButton(
                icon: const Icon(Icons.sentiment_satisfied_alt_rounded, size: 24),
                color: const Color(0xFF54656F),
                onPressed: _showEmojiPicker,
                tooltip: 'Emoji',
                splashRadius: 20,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: _messageController,
                    maxLines: null,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    style: const TextStyle(fontSize: 15),
                    decoration: const InputDecoration(
                      hintText: 'Bir mesaj yazın',
                      hintStyle: TextStyle(color: Color(0xFF8696A0), fontSize: 15),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      hoverColor: Colors.transparent,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (_) {
                      if (_messageController.text.trim().isNotEmpty) _sendMessage();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  if (_messageController.text.trim().isNotEmpty) {
                    _sendMessage();
                  } else {
                    _handleMicButton();
                  }
                },
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _messageController.text.trim().isNotEmpty
                        ? const Color(0xFF008069)
                        : (_isRecording ? Colors.red : Colors.transparent),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _messageController.text.trim().isNotEmpty
                        ? Icons.send_rounded
                        : (_isRecording ? Icons.stop : Icons.mic_rounded),
                    color: _messageController.text.trim().isNotEmpty
                        ? Colors.white
                        : (_isRecording ? Colors.white : const Color(0xFF54656F)),
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// WhatsApp tarzı mesaj düzenleme bottom sheet
  void _showEditMessageSheet(ChatMessage message, int index) {
    final editController = TextEditingController(text: message.content);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Başlık
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => Navigator.pop(ctx),
                        borderRadius: BorderRadius.circular(20),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close, size: 22),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Mesajı düzenleyin',
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Orijinal mesaj önizlemesi (WhatsApp chat background ile)
                Container(
                  width: double.infinity,
                  color: const Color(0xFFEFE7DE),
                  padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 16),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD9FDD3),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          offset: const Offset(0, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.content,
                          style: GoogleFonts.inter(fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Düzenlendi ${DateFormat.Hm().format(message.timestamp)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.done_all, size: 14, color: Color(0xFF53BDEB)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Düzenleme alanı
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      // Emoji butonu (dekoratif)
                      IconButton(
                        icon: Icon(Icons.emoji_emotions_outlined, color: Colors.grey.shade600),
                        onPressed: () {},
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                      // Text alanı
                      Expanded(
                        child: TextField(
                          controller: editController,
                          autofocus: true,
                          maxLines: 5,
                          minLines: 1,
                          style: GoogleFonts.inter(fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'Mesajı düzenleyin...',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 15,
                              color: Colors.grey.shade500,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                      // Kaydet butonu
                      Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFF008069),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.check, color: Colors.white, size: 22),
                          onPressed: () async {
                            final newContent = editController.text.trim();
                            if (newContent.isEmpty || newContent == message.content) {
                              Navigator.pop(ctx);
                              return;
                            }

                            // Firestore'da güncelle
                            await _chatService.editMessage(
                              conversationId: widget.conversation.id,
                              messageId: message.id,
                              newContent: newContent,
                            );

                            // Lokal listeyi güncelle
                            if (mounted) {
                              setState(() {
                                _messages[index] = message.copyWith(
                                  content: newContent,
                                  isEdited: true,
                                );
                              });
                            }

                            Navigator.pop(ctx);
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
