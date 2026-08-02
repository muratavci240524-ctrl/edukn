import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_models.dart';
import 'package:google_fonts/google_fonts.dart';

class ChatListWidget extends StatelessWidget {
  final List<Conversation> conversations;
  final String? selectedConversationId;
  final Function(Conversation) onConversationSelected;
  final Function(Conversation)? onArchive;
  final Function(Conversation)? onDelete;
  final List<ChatUser> contacts;
  final String currentUserRole;

  const ChatListWidget({
    Key? key,
    required this.conversations,
    this.selectedConversationId,
    required this.onConversationSelected,
    this.onArchive,
    this.onDelete,
    this.contacts = const [],
    this.currentUserRole = 'manager',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final activeConversations = conversations.where(
      (c) => c.lastMessage != null && c.lastMessage!.content.trim().isNotEmpty,
    ).toList();

    if (activeConversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'Henüz mesajlaşma bulunmuyor.',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey),
              ),
              const SizedBox(height: 4),
              Text(
                'Kişiler sekmesinden yeni sohbet başlatabilirsiniz.',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: activeConversations.length,
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        indent: 70,
        endIndent: 16,
        color: Color(0xFFE9EDEF),
      ),
      itemBuilder: (context, index) {
        final conversation = activeConversations[index];
        final isSelected = conversation.id == selectedConversationId;

        // Resolve chat title/image
        String displayTitle = conversation.chatName ?? '';
        String? displayImage = conversation.chatImage;

        final currentUserId = FirebaseAuth.instance.currentUser?.uid;

        if (displayTitle.isEmpty ||
            displayTitle.startsWith('Kullanıcı') ||
            displayTitle.startsWith('kullanıcı')) {
          String otherId = '';
          if (conversation.participantIds.isNotEmpty) {
            otherId = conversation.participantIds.firstWhere(
              (id) => id != currentUserId,
              orElse: () => conversation.participantIds.first,
            );
          }

          if (otherId.isNotEmpty && otherId != currentUserId) {
            try {
              final user = contacts.firstWhere(
                (u) => u.id == otherId,
                orElse: () => ChatUser(id: 'notFound', name: ''),
              );

              if (user.id != 'notFound' && user.name.isNotEmpty) {
                displayTitle = user.name;
                displayImage ??= user.avatarUrl;
              }
            } catch (_) {}
          }
        }

        if (displayTitle.isEmpty) {
          displayTitle = 'Bilinmeyen';
        }

        final chatTitle = displayTitle;
        final lastMsg = conversation.lastMessage;

        return InkWell(
          onTap: () => onConversationSelected(conversation),
          child: Container(
            color: isSelected ? const Color(0xFFF0F2F5) : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.grey.shade300,
                  backgroundImage: (displayImage != null && displayImage.isNotEmpty)
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
                          : const Icon(Icons.person, color: Colors.white, size: 28))
                      : null,
                ),
                const SizedBox(width: 12),
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
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
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
                                color: lastMsg!.isRead ? const Color(0xFF53BDEB) : Colors.grey,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              lastMsg?.content ?? '',
                              style: TextStyle(
                                fontSize: 13,
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
                              margin: const EdgeInsets.only(left: 6),
                              width: 10,
                              height: 10,
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
                PopupMenuButton<String>(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 8,
                  icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade600, size: 20),
                  tooltip: 'Seçenekler',
                  onSelected: (value) {
                    if (value == 'archive') {
                      if (onArchive != null) onArchive!(conversation);
                    } else if (value == 'delete' || value == 'clear') {
                      if (onDelete != null) onDelete!(conversation);
                    } else if (value == 'mute') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Bildirimler sessize alındı')),
                      );
                    } else if (value == 'mark_unread') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Okunmadı olarak işaretlendi')),
                      );
                    } else if (value == 'favorite') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Favorilere eklendi')),
                      );
                    } else if (value == 'exit_group') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Gruptan ayrılındı')),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'archive',
                      height: 38,
                      child: Row(
                        children: [
                          Icon(
                            conversation.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
                            color: Colors.indigo,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            conversation.isArchived ? 'Sohbeti arşivden çıkar' : 'Sohbeti arşivle',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'mute',
                      height: 38,
                      child: Row(
                        children: [
                          const Icon(Icons.notifications_off_outlined, color: Colors.blueGrey, size: 18),
                          const SizedBox(width: 12),
                          Text('Bildirimleri sessize al', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                          const Spacer(),
                          const Icon(Icons.arrow_right, size: 16, color: Colors.grey),
                        ],
                      ),
                    ),
                    if (currentUserRole != 'teacher')
                    PopupMenuItem(
                      value: 'pin',
                      height: 38,
                      child: Row(
                        children: [
                          Icon(
                            conversation.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                            color: Colors.amber.shade800,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            conversation.isPinned ? 'Sohbetin Sabitlemesini Kaldır' : 'Sohbeti Sabitle',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'mark_unread',
                      height: 38,
                      child: Row(
                        children: [
                          const Icon(Icons.mark_chat_unread_outlined, color: Colors.teal, size: 18),
                          const SizedBox(width: 12),
                          Text('Okunmadı olarak işaretle', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'favorite',
                      height: 38,
                      child: Row(
                        children: [
                          const Icon(Icons.favorite_border_rounded, color: Colors.pink, size: 18),
                          const SizedBox(width: 12),
                          Text('Favoriler\'e ekle', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'add_to_list',
                      height: 38,
                      child: Row(
                        children: [
                          const Icon(Icons.playlist_add_rounded, color: Colors.blue, size: 18),
                          const SizedBox(width: 12),
                          Text('Listeye ekle', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                          const Spacer(),
                          const Icon(Icons.arrow_right, size: 16, color: Colors.grey),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(height: 1),
                    PopupMenuItem(
                      value: 'clear',
                      height: 38,
                      child: Row(
                        children: [
                          const Icon(Icons.do_not_disturb_on_outlined, color: Colors.redAccent, size: 18),
                          const SizedBox(width: 12),
                          Text('Sohbeti temizle', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.redAccent)),
                        ],
                      ),
                    ),
                    if (conversation.isGroup)
                      PopupMenuItem(
                        value: 'exit_group',
                        height: 38,
                        child: Row(
                          children: [
                            const Icon(Icons.exit_to_app_rounded, color: Colors.redAccent, size: 18),
                            const SizedBox(width: 12),
                            Text('Gruptan çık', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.redAccent)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
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
      const turkishDays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
      return turkishDays[date.weekday - 1];
    } else {
      return DateFormat('dd.MM.yy').format(date);
    }
  }
}
