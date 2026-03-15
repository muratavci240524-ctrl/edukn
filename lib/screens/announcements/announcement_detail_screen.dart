import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/user_permission_service.dart';
import 'announcement_form_sheet.dart';

class AnnouncementDetailScreen extends StatefulWidget {
  static const routeName = '/announcement-detail';
  final String announcementId;
  final String schoolId;

  const AnnouncementDetailScreen({
    super.key,
    required this.announcementId,
    required this.schoolId,
  });

  @override
  State<AnnouncementDetailScreen> createState() =>
      _AnnouncementDetailScreenState();
}

class _AnnouncementDetailScreenState extends State<AnnouncementDetailScreen> {
  bool _showRecipients = false;
  Map<String, dynamic>? _announcementData;
  List<Map<String, dynamic>> _recipientDetails = [];
  bool _isLoading = true;

  // Yetkilendirme için
  Map<String, dynamic>? userData;

  @override
  void initState() {
    super.initState();
    _loadUserPermissions();
    _loadAnnouncementData();
    _markAsRead();
  }

  // Kullanıcı yetkilendirme bilgilerini yükle
  Future<void> _loadUserPermissions() async {
    final data = await UserPermissionService.loadUserData();
    if (mounted) {
      setState(() => userData = data);
    }
  }

  // Duyuru modülüne düzenleme yetkisi var mı?
  bool _canEditAnnouncements() {
    return UserPermissionService.canEdit('genel_duyurular', userData);
  }

  Future<void> _loadAnnouncementData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('announcements')
          .doc(widget.announcementId)
          .get();

      if (doc.exists) {
        _announcementData = doc.data();
        await _loadRecipientDetails();
      }
    } catch (e) {
      print('Duyuru yüklenirken hata: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRecipientDetails() async {
    if (_announcementData == null) return;

    final recipients = _announcementData!['recipients'] as List<dynamic>? ?? [];
    final readBy = _announcementData!['readBy'] as List<dynamic>? ?? [];
    final List<Map<String, dynamic>> details = [];

    for (final recipientId in recipients) {
      if (recipientId.toString().startsWith('user:')) {
        final userId = recipientId.toString().substring(5);
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get();

          if (userDoc.exists) {
            final userData = userDoc.data()!;
            details.add({
              'id': userId,
              'name': userData['fullName'] ?? userData['name'] ?? 'İsimsiz',
              'role': userData['role'] ?? 'Kullanıcı',
              'isRead': readBy.contains(userId),
            });
          }
        } catch (e) {
          print('Kullanıcı yüklenirken hata: $e');
        }
      }
    }

    if (mounted) {
      setState(() => _recipientDetails = details);
    }
  }

  Future<void> _markAsRead() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Get current user's ID from users collection
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: currentUser.email)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) return;
      final userId = userQuery.docs.first.id;

      // Add to readBy array if not already there
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('announcements')
          .doc(widget.announcementId)
          .update({
            'readBy': FieldValue.arrayUnion([userId]),
          });
    } catch (e) {
      print('Okundu işaretlenirken hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Duyuru Detayı')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_announcementData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Duyuru Detayı')),
        body: const Center(child: Text('Duyuru bulunamadı')),
      );
    }

    final title = _announcementData!['title'] ?? 'Başlıksız';
    final content = _announcementData!['content'] ?? '';
    final creatorName = _announcementData!['creatorName'] ?? 'Bilinmeyen';
    final createdAt = _announcementData!['createdAt'] as Timestamp?;
    final sendSms = _announcementData!['sendSms'] as bool? ?? false;
    final links = _announcementData!['links'] as List<dynamic>? ?? [];

    final totalRecipients = _recipientDetails.length;
    final readCount = _recipientDetails
        .where((r) => r['isRead'] == true)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Duyuru Detayı'),
        actions: [
          // Sadece editor yetkisi olanlar düzenleyebilir ve silebilir
          if (_canEditAnnouncements()) ...[
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Düzenle',
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (ctx) => AnnouncementFormSheet(
                    announcementId: widget.announcementId,
                    announcementData: _announcementData,
                  ),
                ).then((_) {
                  // Düzenleme sonrası yenile
                  _loadAnnouncementData();
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: 'Sil',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Duyuruyu Sil'),
                    content: const Text(
                      'Bu duyuruyu silmek istediğinizden emin misiniz?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('İptal'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Sil'),
                      ),
                    ],
                  ),
                );

                if (confirm == true && mounted) {
                  try {
                    await FirebaseFirestore.instance
                        .collection('schools')
                        .doc(widget.schoolId)
                        .collection('announcements')
                        .doc(widget.announcementId)
                        .delete();

                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Duyuru silindi')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Silme hatası: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
            ),
          ],
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // İstatistikler
              Card(
                elevation: 2,
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Icon(
                              Icons.people,
                              size: 32,
                              color: Colors.blue[700],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$totalRecipients',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[900],
                              ),
                            ),
                            Text(
                              'Alıcı',
                              style: TextStyle(color: Colors.blue[700]),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 60, color: Colors.blue[200]),
                      Expanded(
                        child: Column(
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 32,
                              color: Colors.green[700],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$readCount',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[900],
                              ),
                            ),
                            Text(
                              'Okuyan',
                              style: TextStyle(color: Colors.green[700]),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 60, color: Colors.blue[200]),
                      Expanded(
                        child: Column(
                          children: [
                            Icon(
                              Icons.pending,
                              size: 32,
                              color: Colors.orange[700],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${totalRecipients - readCount}',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[900],
                              ),
                            ),
                            Text(
                              'Bekleyen',
                              style: TextStyle(color: Colors.orange[700]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Duyuru içeriği
              Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.person, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            creatorName,
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                          const SizedBox(width: 16),
                          Icon(
                            Icons.access_time,
                            size: 16,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            createdAt != null
                                ? '${createdAt.toDate().day}/${createdAt.toDate().month}/${createdAt.toDate().year}'
                                : 'Bilinmiyor',
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                          if (sendSms) ...[
                            const SizedBox(width: 16),
                            Icon(Icons.sms, size: 16, color: Colors.green[600]),
                            const SizedBox(width: 4),
                            Text(
                              'SMS gönderildi',
                              style: TextStyle(color: Colors.green[700]),
                            ),
                          ],
                        ],
                      ),
                      const Divider(height: 32),
                      Text(
                        content,
                        style: const TextStyle(fontSize: 16, height: 1.5),
                      ),
                      if (links.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 12),
                        Text(
                          'Bağlantılar',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...links.map((link) {
                          final linkData = link is Map
                              ? link
                              : {'name': 'Bağlantı', 'url': link.toString()};
                          final linkName = linkData['name'] ?? 'Bağlantı';
                          final linkUrl = linkData['url'] ?? '';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Icon(
                                Icons.link,
                                color: Colors.blue[700],
                              ),
                              title: Text(
                                linkName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                linkUrl,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.copy, size: 20),
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: linkUrl),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Link kopyalandı'),
                                    ),
                                  );
                                },
                                tooltip: 'Linki Kopyala',
                              ),
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: linkUrl));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '$linkName kopyalandı: $linkUrl',
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Alıcılar
              Card(
                elevation: 1,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.people, color: Colors.indigo[700]),
                      title: const Text(
                        'Alıcı Listesi',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '$readCount / $totalRecipients kişi okudu',
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          _showRecipients
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                        onPressed: () =>
                            setState(() => _showRecipients = !_showRecipients),
                      ),
                    ),
                    if (_showRecipients) ...[
                      const Divider(height: 1),
                      if (_recipientDetails.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Alıcı bilgisi yüklenemedi'),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _recipientDetails.length,
                          itemBuilder: (context, index) {
                            final recipient = _recipientDetails[index];
                            final isRead = recipient['isRead'] as bool;

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isRead
                                    ? Colors.green[100]
                                    : Colors.grey[200],
                                child: Icon(
                                  isRead ? Icons.check_circle : Icons.pending,
                                  color: isRead
                                      ? Colors.green[700]
                                      : Colors.grey[600],
                                  size: 20,
                                ),
                              ),
                              title: Text(recipient['name']),
                              subtitle: Text(recipient['role']),
                              trailing: isRead
                                  ? Chip(
                                      label: const Text(
                                        'Okundu',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      backgroundColor: Colors.green[100],
                                      labelPadding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    )
                                  : Chip(
                                      label: const Text(
                                        'Bekliyor',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      backgroundColor: Colors.grey[200],
                                      labelPadding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                            );
                          },
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
