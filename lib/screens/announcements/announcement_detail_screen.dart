import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/user_permission_service.dart';
import '../../services/announcement_service.dart';
import 'create_announcement_screen_v2.dart';

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
    return UserPermissionService.canEditSubModule('haberlesme', 'genel_duyurular', userData);
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

    final readBy = _announcementData!['readBy'] as List<dynamic>? ?? [];
    final recipients = _announcementData!['recipients'] as List<dynamic>? ?? [];
    final recipientNames = _announcementData!['recipientNames'] as Map<String, dynamic>? ?? {};
    final schoolTypeId = _announcementData!['schoolTypeId'] as String?;
    final recipientStringList = recipients.map((e) => e.toString()).toList();

    // 1. EĞER Duyuruda Gruplar (Sınıf, Şube, Birim, Okul vb.) Varsa:
    // Dinamik olarak o gruptaki GERÇEK öğrencileri, öğretmenleri ve velileri kişi kişi çözümler!
    final hasGroups = recipientStringList.any((id) =>
        id.startsWith('class:') ||
        id.startsWith('branch:') ||
        id.startsWith('unit:') ||
        id.startsWith('school:') ||
        id.startsWith('group:') ||
        id == 'ALL' ||
        id == 'TEACHER');

    if (hasGroups) {
      try {
        final service = AnnouncementService();
        final resolved = await service.resolveRecipientUsers(
          recipientStringList,
          schoolTypeId: schoolTypeId,
        );

        if (resolved.isNotEmpty) {
          final List<Map<String, dynamic>> details = resolved.map((user) {
            final uid = (user['id'] ?? '').toString();
            return {
              'id': uid,
              'name': user['name'] ?? user['fullName'] ?? 'İsimsiz',
              'role': user['role'] ?? 'Kullanıcı',
              'group': user['group'] ?? user['role'] ?? 'Genel',
              'isRead': readBy.contains(uid) || readBy.contains('user:$uid'),
            };
          }).toList();

          if (mounted) setState(() => _recipientDetails = details);
          return;
        }
      } catch (e) {
        print('Alıcı çözümleme hatası: $e');
      }
    }

    // 2. EĞER zaten kayıt esnasında çözümlenmiş gerçek kişiler varsa:
    final resolvedRecipients = _announcementData!['resolvedRecipients'] as List<dynamic>?;
    if (resolvedRecipients != null && resolvedRecipients.isNotEmpty) {
      final List<Map<String, dynamic>> details = resolvedRecipients.map((r) {
        final user = r as Map<String, dynamic>;
        final uid = user['id']?.toString() ?? '';
        return {
          'id': uid,
          'name': user['name'] ?? user['fullName'] ?? 'İsimsiz',
          'role': user['role'] ?? 'Kullanıcı',
          'group': user['group'] ?? user['role'] ?? 'Genel',
          'isRead': readBy.contains(uid) || readBy.contains('user:$uid'),
        };
      }).toList();

      if (mounted) setState(() => _recipientDetails = details);
      return;
    }

    // Fallback: Eski davranış (bireysel user: bazlı)
    final List<Map<String, dynamic>> details = [];
    for (final recipientId in recipientStringList) {
      final rId = recipientId.toString();

      if (recipientNames.containsKey(rId)) {
        details.add({
          'id': rId,
          'name': recipientNames[rId],
          'role': _getRoleFromId(rId),
          'group': rId,
          'isRead': readBy.contains(rId) ||
              (rId.startsWith('user:') && readBy.contains(rId.substring(5))),
        });
        continue;
      }

      if (rId.startsWith('user:')) {
        final userId = rId.substring(5);
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
      } else {
        details.add({
          'id': rId,
          'name': rId.split(':').last,
          'role': _getRoleFromId(rId),
          'group': rId,
          'isRead': readBy.contains(rId),
        });
      }
    }

    if (mounted) {
      setState(() => _recipientDetails = details);
    }
  }

  String _getRoleFromId(String id) {
    if (id.startsWith('user:')) return 'Kullanıcı';
    if (id.startsWith('unit:')) return 'Birim';
    if (id.startsWith('school:')) return 'Okul Türü';
    if (id.startsWith('branch:')) return 'Şube';
    if (id.startsWith('class:')) return 'Sınıf Seviyesi';
    if (id.startsWith('group:')) return 'Grup';
    if (id == 'ALL') return 'Herkes';
    if (id == 'TEACHER') return 'Tüm Öğretmenler';
    return 'Alıcı';
  }

  Future<void> _markAsRead() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: currentUser.email)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) return;
      final userId = userQuery.docs.first.id;

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

  // Gruplandırılmış alıcı verilerini oluşturur (Örn: 801-Öğrenciler -> [22/23 okundu])
  List<Map<String, dynamic>> _getGroupedRecipientData() {
    final recipientNames = _announcementData?['recipientNames'] as Map<String, dynamic>? ?? {};
    final Map<String, List<Map<String, dynamic>>> groupsMap = {};
    final Map<String, String> groupTitleMap = {};

    for (var user in _recipientDetails) {
      final groupKey = user['group']?.toString() ?? user['role']?.toString() ?? 'Genel';
      final title = recipientNames[groupKey]?.toString() ?? groupKey;

      groupsMap.putIfAbsent(groupKey, () => []);
      groupsMap[groupKey]!.add(user);
      groupTitleMap[groupKey] = title;
    }

    final List<Map<String, dynamic>> result = [];
    groupsMap.forEach((key, users) {
      final total = users.length;
      final readCount = users.where((u) => u['isRead'] == true).length;
      final percentage = total > 0 ? ((readCount / total) * 100).round() : 0;

      result.add({
        'groupKey': key,
        'title': groupTitleMap[key] ?? key,
        'total': total,
        'readCount': readCount,
        'percentage': percentage,
        'users': users,
      });
    });

    // Başlığa göre sırala
    result.sort((a, b) => (a['title'] as String).compareTo(b['title'] as String));
    return result;
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Duyuruyu Sil'),
        content: const Text('Bu duyuruyu silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Duyuru silindi')));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Silme hatası: $e'), backgroundColor: Colors.red));
      }
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
    final links = _announcementData!['links'] as List<dynamic>? ?? [];
    final sendSms = _announcementData!['sendSms'] as bool? ?? false;
    final totalRecipients = _recipientDetails.length;
    final readCount = _recipientDetails.where((r) => r['isRead'] == true).length;

    final groupedData = _getGroupedRecipientData();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Duyuru Detayı'),
        actions: [
          if (_canEditAnnouncements()) ...[
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CreateAnnouncementScreenV2(
                      announcementId: widget.announcementId,
                      announcementData: _announcementData,
                      schoolTypeId: _announcementData?['schoolTypeId'],
                    ),
                  ),
                ).then((value) {
                  if (value == true) _loadAnnouncementData();
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _confirmDelete(context),
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // İstatistik Kartları
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Icon(Icons.people, size: 28, color: Colors.blue[700]),
                              const SizedBox(height: 6),
                              Text('$totalRecipients', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue[900])),
                              Text('Alıcı', style: TextStyle(color: Colors.blue[700], fontSize: 12)),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 45, color: Colors.grey[300]),
                        Expanded(
                          child: Column(
                            children: [
                              Icon(Icons.check_circle, size: 28, color: Colors.green[700]),
                              const SizedBox(height: 6),
                              Text('$readCount', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green[900])),
                              Text('Okuyan', style: TextStyle(color: Colors.green[700], fontSize: 12)),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 45, color: Colors.grey[300]),
                        Expanded(
                          child: Column(
                            children: [
                              Icon(Icons.pending, size: 28, color: Colors.orange[700]),
                              const SizedBox(height: 6),
                              Text('${totalRecipients - readCount}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange[900])),
                              Text('Bekleyen', style: TextStyle(color: Colors.orange[700], fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Duyuru İçeriği
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.person, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(creatorName, style: TextStyle(color: Colors.grey[700])),
                            const SizedBox(width: 16),
                            Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(createdAt != null ? '${createdAt.toDate().day}/${createdAt.toDate().month}/${createdAt.toDate().year}' : 'Bilinmiyor', style: TextStyle(color: Colors.grey[700])),
                            if (sendSms) ...[
                              const SizedBox(width: 16),
                              Icon(Icons.sms, size: 16, color: Colors.green[600]),
                              const SizedBox(width: 4),
                              Text('SMS gönderildi', style: TextStyle(color: Colors.green[700])),
                            ],
                          ],
                        ),
                        const Divider(height: 32),
                        Text(content, style: const TextStyle(fontSize: 16, height: 1.5)),
                        if (links.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 12),
                          Text('Bağlantılar', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[800])),
                          const SizedBox(height: 8),
                          ...links.map((link) {
                            final linkData = link is Map ? link : {'name': 'Bağlantı', 'url': link.toString()};
                            final linkName = linkData['name'] ?? 'Bağlantı';
                            final linkUrl = linkData['url'] ?? '';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(Icons.link, color: Colors.blue[700]),
                                title: Text(linkName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(linkUrl, style: TextStyle(color: Colors.grey[600], fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: IconButton(
                                  icon: const Icon(Icons.copy, size: 20),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: linkUrl));
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link kopyalandı')));
                                  },
                                  tooltip: 'Linki Kopyala',
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Alıcı Listesi (Gruplandırılmış ve Hızlı Açılır Akordeon)
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
                          child: Icon(Icons.groups_rounded, color: Colors.indigo[700]),
                        ),
                        title: const Text('Alıcı Listesi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Text('$readCount / $totalRecipients kişi okudu (%${totalRecipients > 0 ? ((readCount / totalRecipients) * 100).round() : 0})'),
                        trailing: IconButton(
                          icon: Icon(_showRecipients ? Icons.expand_less : Icons.expand_more, size: 28),
                          onPressed: () => setState(() => _showRecipients = !_showRecipients),
                        ),
                      ),
                      if (_showRecipients) ...[
                        const Divider(height: 1),
                        if (_recipientDetails.isEmpty)
                          const Padding(padding: EdgeInsets.all(16), child: Text('Alıcı bilgisi yüklenemedi'))
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: groupedData.length,
                            separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                            itemBuilder: (context, index) {
                              final group = groupedData[index];
                              final String title = group['title'];
                              final int total = group['total'];
                              final int groupRead = group['readCount'];
                              final int percentage = group['percentage'];
                              final List<Map<String, dynamic>> users = group['users'];

                              IconData groupIcon = Icons.class_outlined;
                              Color iconColor = Colors.indigo;
                              if (title.contains('Öğrenci')) { groupIcon = Icons.school_outlined; iconColor = Colors.blue; }
                              else if (title.contains('Veli')) { groupIcon = Icons.family_restroom_outlined; iconColor = Colors.orange; }
                              else if (title.contains('Öğretmen')) { groupIcon = Icons.badge_outlined; iconColor = Colors.teal; }

                              return ExpansionTile(
                                leading: CircleAvatar(radius: 18, backgroundColor: iconColor.withOpacity(0.12), child: Icon(groupIcon, size: 20, color: iconColor)),
                                title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: total > 0 ? groupRead / total : 0,
                                            backgroundColor: Colors.grey[200],
                                            color: groupRead == total ? Colors.green : Colors.blue,
                                            minHeight: 6,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('$groupRead / $total', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                                    ],
                                  ),
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: groupRead == total ? Colors.green.shade50 : (groupRead > 0 ? Colors.blue.shade50 : Colors.grey.shade100),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: groupRead == total ? Colors.green.shade200 : (groupRead > 0 ? Colors.blue.shade200 : Colors.grey.shade300)),
                                  ),
                                  child: Text('%$percentage', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: groupRead == total ? Colors.green.shade800 : (groupRead > 0 ? Colors.blue.shade800 : Colors.grey.shade700))),
                                ),
                                children: users.map((user) {
                                  final isRead = user['isRead'] as bool;
                                  return ListTile(
                                    contentPadding: const EdgeInsets.only(left: 32, right: 16),
                                    leading: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: isRead ? Colors.green.shade100 : Colors.grey.shade200,
                                      child: Icon(isRead ? Icons.check : Icons.access_time, color: isRead ? Colors.green.shade800 : Colors.grey.shade600, size: 14),
                                    ),
                                    title: Text(user['name'], style: const TextStyle(fontSize: 14)),
                                    subtitle: Text(user['role'], style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                    trailing: isRead
                                        ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(4)), child: Text('Okundu', style: TextStyle(fontSize: 11, color: Colors.green.shade900, fontWeight: FontWeight.w600)))
                                        : Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)), child: Text('Bekliyor', style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
                                  );
                                }).toList(),
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
      ),
    );
  }
}
