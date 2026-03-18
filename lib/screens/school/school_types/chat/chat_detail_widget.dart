import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'chat_models.dart';
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

  void _toggleStar(String messageId) {
    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final msg = _messages[index];
        final newStarredState = !msg.isStarred;

        final updatedMsg = msg.copyWith(isStarred: newStarredState);
        _messages[index] = updatedMsg;

        // Sync with Global List
        if (newStarredState) {
          if (!globalStarredMessages.any((m) => m.id == msg.id)) {
            globalStarredMessages.add(updatedMsg);
          }
        } else {
          globalStarredMessages.removeWhere((m) => m.id == msg.id);
        }
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
    FilePickerResult? result = await FilePicker.platform.pickFiles(
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
                          String subtitle = 'Çevrimiçi';
                          try {
                            // Assuming 1-on-1 chat for now, pick first participant that is not 'me' (if we had 'me')
                            // data here usually contains the partner ID.
                            if (widget.conversation.participantIds.isNotEmpty) {
                              final partnerId =
                                  widget.conversation.participantIds.first;
                              final user = widget.contacts.firstWhere(
                                (u) => u.id == partnerId,
                                orElse: () =>
                                    ChatUser(id: '', name: '', role: ''),
                              );
                              if (user.role != null && user.role!.isNotEmpty) {
                                subtitle = user.role!;
                              }
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
                icon: const Icon(Icons.search),
                onPressed: () {},
                color: Colors.grey.shade600,
                splashRadius: 24,
              ),
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {},
                color: Colors.grey.shade600,
                splashRadius: 24,
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
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    final isMe =
                        message.senderId == _chatService.currentUserId ||
                        message.senderId == 'me';

                    return MouseRegion(
                      onEnter: (_) =>
                          setState(() => _hoveredMessageId = message.id),
                      onExit: (_) => setState(() => _hoveredMessageId = null),
                      child: Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Stack(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.only(
                                left: 10,
                                right: 10, // constant padding
                                top: 6,
                                bottom: 6,
                              ),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.65,
                                minWidth: 100,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? const Color(0xFFD9FDD3)
                                    : Colors.white,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(12),
                                  topRight: const Radius.circular(12),
                                  bottomLeft: isMe
                                      ? const Radius.circular(12)
                                      : const Radius.circular(0),
                                  bottomRight: isMe
                                      ? const Radius.circular(0)
                                      : const Radius.circular(12),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    offset: const Offset(0, 1),
                                    blurRadius: 1,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildMessageContent(message, isMe),
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      // Star Indicator
                                      if (message.isStarred)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 4,
                                          ),
                                          child: Icon(
                                            Icons.star,
                                            size: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      const SizedBox(
                                        width: 20,
                                      ), // Spacing for timestamp
                                      Text(
                                        DateFormat.Hm().format(
                                          message.timestamp,
                                        ),
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
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Hover Menu - Bottom Right position & Opacity fix
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Opacity(
                                opacity: _hoveredMessageId == message.id
                                    ? 1.0
                                    : 0.0,
                                child: IgnorePointer(
                                  ignoring: _hoveredMessageId != message.id,
                                  child: Container(
                                    margin: const EdgeInsets.only(
                                      bottom: 2,
                                      right: 2,
                                    ),
                                    width: 28,
                                    height: 28,
                                    // Decoration removed to show only the arrow icon
                                    child: PopupMenuButton<String>(
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down,
                                        size: 20,
                                        color: Colors.grey,
                                      ),
                                      padding: EdgeInsets.zero,
                                      tooltip: 'Mesaj işlemleri',
                                      onSelected: (value) {
                                        if (value == 'reply') {
                                          _replyToMessage(message);
                                        } else if (value == 'star') {
                                          _toggleStar(message.id);
                                        } else if (value == 'forward') {
                                          _forwardMessage(message);
                                        } else if (value == 'delete') {
                                          setState(() {
                                            _messages.removeAt(index);
                                          });
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'reply',
                                          child: Text('Yanıtla'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'forward',
                                          child: Text('İlet'),
                                        ),
                                        PopupMenuItem(
                                          value: 'star',
                                          child: Text(
                                            message.isStarred
                                                ? 'Yıldızı Kaldır'
                                                : 'Yıldızla',
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Sil'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        // Input Area
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
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.indigo,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                offset: const Offset(0, -1),
                blurRadius: 5,
              ),
            ],
          ),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 120),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7F9),
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.emoji_emotions_outlined),
                  color: Colors.grey.shade600,
                  onPressed: _showEmojiPicker,
                  splashRadius: 20,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 48,
                  ),
                  padding: EdgeInsets.zero,
                ),
                IconButton(
                  icon: const Icon(Icons.attach_file_rounded),
                  color: Colors.grey.shade600,
                  onPressed: _pickFile,
                  splashRadius: 20,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 48,
                  ),
                  padding: EdgeInsets.zero,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    maxLines: null,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    style: const TextStyle(fontSize: 16),
                    decoration: const InputDecoration(
                      hintText: 'Bir mesaj yazın',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      hoverColor: Colors.transparent,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 8,
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (_) {
                      if (_messageController.text.trim().isNotEmpty)
                        _sendMessage();
                    },
                  ),
                ),
                // Send or Mic Button integrated
                // Send or Mic Button integrated
                IconButton(
                  icon: Icon(
                    _messageController.text.trim().isNotEmpty
                        ? Icons.send
                        : (_isRecording
                              ? Icons.stop
                              : Icons.mic), // Dynamic Icon
                  ),
                  color: _isRecording ? Colors.red : Colors.indigo,
                  onPressed: () {
                    if (_messageController.text.trim().isNotEmpty) {
                      _sendMessage();
                    } else {
                      _handleMicButton(); // Handle Record/Stop
                    }
                  },
                  splashRadius: 24,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
