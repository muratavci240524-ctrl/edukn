import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_models.dart';

class ChatListWidget extends StatelessWidget {
  final List<Conversation> conversations;
  final String? selectedConversationId;
  final Function(Conversation) onConversationSelected;
  final Function(Conversation)? onArchive;
  final List<ChatUser> contacts;

  const ChatListWidget({
    Key? key,
    required this.conversations,
    this.selectedConversationId,
    required this.onConversationSelected,
    this.onArchive,
    this.contacts = const [],
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: conversations.length,
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        indent: 70,
        endIndent: 16,
        color: Color(0xFFE9EDEF),
      ),
      itemBuilder: (context, index) {
        final conversation = conversations[index];
        final isSelected = conversation.id == selectedConversationId;

        // Resolve chat title/image
        String displayTitle = conversation.chatName ?? '';
        String? displayImage = conversation.chatImage;

        // Use FirebaseAuth directly to be safe
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;

        if (displayTitle.isEmpty ||
            displayTitle.startsWith('Kullanıcı') ||
            displayTitle.startsWith('kullanıcı')) {
          // Find the "other" participant
          String otherId = '';
          if (conversation.participantIds.isNotEmpty) {
            otherId = conversation.participantIds.firstWhere(
              (id) => id != currentUserId,
              orElse: () => conversation
                  .participantIds
                  .first, // Fallback to first if only me or none found
            );
          }

          if (otherId.isNotEmpty && otherId != currentUserId) {
            // Look up in contacts
            try {
              final user = contacts.firstWhere(
                (u) => u.id == otherId,
                orElse: () => ChatUser(id: 'notFound', name: ''),
              );

              if (user.id != 'notFound' && user.name.isNotEmpty) {
                displayTitle = user.name;
                displayImage ??= user.avatarUrl;
              }
            } catch (e) {
              // Ignore
            }
          }
        }

        // Final fallback if displayTitle is still empty
        if (displayTitle.isEmpty) {
          displayTitle = 'Bilinmeyen';
        }

        final chatTitle = displayTitle;
        final lastMsg = conversation.lastMessage;

        return Dismissible(
          key: Key(conversation.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: const Color(0xFF008069), // WhatsApp Archive Color
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Icon(Icons.archive, color: Colors.white),
          ),
          onDismissed: (direction) {
            if (onArchive != null) {
              onArchive!(conversation);
            }
          },
          child: InkWell(
            onTap: () => onConversationSelected(conversation),
            child: Container(
              color: isSelected ? const Color(0xFFF0F2F5) : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.grey.shade300,
                    backgroundImage:
                        (displayImage != null && displayImage.isNotEmpty)
                        ? NetworkImage(displayImage)
                        : null,
                    child: (displayImage == null || displayImage.isEmpty)
                        ? (displayTitle.isNotEmpty
                              ? Text(
                                  displayTitle[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                )
                              : const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 28,
                                ))
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                chatTitle,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.normal,
                                  color: Color(0xFF111B21),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (lastMsg != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: Text(
                                  _formatDate(lastMsg.timestamp),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: (conversation.unreadCounts[currentUserId] ?? 0) > 0
                                        ? const Color(0xFF25D366)
                                        : const Color(0xFF667781),
                                    fontWeight: (conversation.unreadCounts[currentUserId] ?? 0) > 0
                                        ? FontWeight.w500
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (lastMsg?.senderId == 'me')
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(
                                  Icons.done_all,
                                  size: 16,
                                  color: lastMsg!.isRead
                                      ? const Color(0xFF53BDEB)
                                      : Colors.grey,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                lastMsg?.content ?? '',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: (lastMsg?.isForwarded ?? false)
                                      ? Colors.grey.shade600
                                      : const Color(0xFF667781),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if ((conversation.unreadCounts[currentUserId] ?? 0) > 0 &&
                                lastMsg?.senderId != currentUserId)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF25D366),
                                  shape: BoxShape.circle,
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
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return DateFormat.Hm().format(date);
    } else if (now.difference(date).inDays < 7) {
      return DateFormat.E().format(date); // Day name
    } else {
      return DateFormat('dd.MM.yy').format(date);
    }
  }
}
