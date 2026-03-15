import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/announcement_service.dart';
import 'announcement_detail_screen.dart';

class SentAnnouncementsScreen extends StatefulWidget {
  const SentAnnouncementsScreen({super.key});

  @override
  State<SentAnnouncementsScreen> createState() =>
      _SentAnnouncementsScreenState();
}

class _SentAnnouncementsScreenState extends State<SentAnnouncementsScreen> {
  final AnnouncementService _announcementService = AnnouncementService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _recipientSearchController =
      TextEditingController();
  DateTimeRange? _dateRange;
  String? _selectedRecipientFilter;

  Stream<QuerySnapshot> _getSentAnnouncements() async* {
    try {
      final schoolId = await _announcementService.getSchoolId();
      print('School ID: $schoolId');

      if (schoolId == null) {
        print('School ID null, boş stream döndürülüyor');
        yield* Stream.empty();
        return;
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('Kullanıcı null, boş stream döndürülüyor');
        yield* Stream.empty();
        return;
      }

      print('Gönderilen duyurular yükleniyor: ${currentUser.email}');

      // Sadece kullanıcının kendi gönderdiği duyuruları getir
      yield* FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('announcements')
          .where('createdBy', isEqualTo: currentUser.email)
          .orderBy('createdAt', descending: true)
          .snapshots();
    } catch (e, stackTrace) {
      print('Gönderilen duyurular alınırken hata: $e');
      print('Stack trace: $stackTrace');
      yield* Stream.empty();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _recipientSearchController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gönderilen Duyurular')),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Filtre Alanı
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Başlık veya içerikte ara...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () =>
                                      setState(() => _searchController.clear()),
                                )
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _recipientSearchController,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Alıcı adı ara (örn: Zafer)...',
                          prefixIcon: const Icon(Icons.person_search),
                          suffixIcon: _recipientSearchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => setState(
                                    () => _recipientSearchController.clear(),
                                  ),
                                )
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickDateRange,
                              icon: const Icon(Icons.calendar_today, size: 18),
                              label: Text(
                                _dateRange == null
                                    ? 'Tarih Aralığı'
                                    : '${_dateRange!.start.day}/${_dateRange!.start.month} - ${_dateRange!.end.day}/${_dateRange!.end.month}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: _dateRange != null
                                    ? Colors.blue[50]
                                    : null,
                              ),
                            ),
                          ),
                          if (_dateRange != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () =>
                                  setState(() => _dateRange = null),
                              tooltip: 'Tarih Filtresini Temizle',
                            ),
                          ],
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Alıcı Filtresi'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          title: const Text('Tümü'),
                                          leading: Radio<String?>(
                                            value: null,
                                            groupValue:
                                                _selectedRecipientFilter,
                                            onChanged: (val) {
                                              setState(
                                                () => _selectedRecipientFilter =
                                                    val,
                                              );
                                              Navigator.pop(ctx);
                                            },
                                          ),
                                        ),
                                        ListTile(
                                          title: const Text('Öğrenciler'),
                                          leading: Radio<String?>(
                                            value: 'students',
                                            groupValue:
                                                _selectedRecipientFilter,
                                            onChanged: (val) {
                                              setState(
                                                () => _selectedRecipientFilter =
                                                    val,
                                              );
                                              Navigator.pop(ctx);
                                            },
                                          ),
                                        ),
                                        ListTile(
                                          title: const Text('Personel'),
                                          leading: Radio<String?>(
                                            value: 'staff',
                                            groupValue:
                                                _selectedRecipientFilter,
                                            onChanged: (val) {
                                              setState(
                                                () => _selectedRecipientFilter =
                                                    val,
                                              );
                                              Navigator.pop(ctx);
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.people, size: 18),
                              label: Text(
                                _selectedRecipientFilter == null
                                    ? 'Alıcı Türü'
                                    : _selectedRecipientFilter == 'students'
                                    ? 'Öğrenciler'
                                    : 'Personel',
                                style: const TextStyle(fontSize: 12),
                              ),
                              style: OutlinedButton.styleFrom(
                                backgroundColor:
                                    _selectedRecipientFilter != null
                                    ? Colors.green[50]
                                    : null,
                              ),
                            ),
                          ),
                          if (_selectedRecipientFilter != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () => setState(
                                () => _selectedRecipientFilter = null,
                              ),
                              tooltip: 'Alıcı Filtresini Temizle',
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Duyuru Listesi
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _getSentAnnouncements(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 64,
                              color: Colors.red[300],
                            ),
                            const SizedBox(height: 16),
                            const Text('Duyurular yüklenirken hata oluştu'),
                            const SizedBox(height: 8),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                snapshot.error.toString(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.send_outlined,
                              size: 100,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Henüz Duyuru Göndermediniz',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final announcements = snapshot.data!.docs;

                    // Filtreleme
                    final searchText = _searchController.text.toLowerCase();
                    final recipientSearchText = _recipientSearchController.text
                        .toLowerCase();
                    final filteredAnnouncements = announcements.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final title = (data['title'] ?? '')
                          .toString()
                          .toLowerCase();
                      final content = (data['content'] ?? '')
                          .toString()
                          .toLowerCase();
                      final createdAt = data['createdAt'] as Timestamp?;
                      final recipients =
                          data['recipients'] as List<dynamic>? ?? [];

                      // Metin araması
                      if (searchText.isNotEmpty &&
                          !title.contains(searchText) &&
                          !content.contains(searchText)) {
                        return false;
                      }

                      // Alıcı adı araması - recipient ID'lerinde ara
                      if (recipientSearchText.isNotEmpty) {
                        final hasMatchingRecipient = recipients.any((r) {
                          final recipientStr = r.toString().toLowerCase();
                          // user:, unit:, school:, class:, group: içindeki metinlerde ara
                          return recipientStr.contains(recipientSearchText);
                        });
                        if (!hasMatchingRecipient) {
                          return false;
                        }
                      }

                      // Tarih aralığı filtresi
                      if (_dateRange != null && createdAt != null) {
                        final date = createdAt.toDate();
                        if (date.isBefore(_dateRange!.start) ||
                            date.isAfter(
                              _dateRange!.end.add(const Duration(days: 1)),
                            )) {
                          return false;
                        }
                      }

                      // Alıcı türü filtresi
                      if (_selectedRecipientFilter != null &&
                          recipients.isNotEmpty) {
                        final hasStudents = recipients.any(
                          (r) =>
                              r.toString().contains('school:') ||
                              r.toString().contains('class:'),
                        );
                        final hasStaff = recipients.any(
                          (r) =>
                              r.toString().startsWith('user:') ||
                              r.toString().startsWith('unit:'),
                        );

                        if (_selectedRecipientFilter == 'students' &&
                            !hasStudents) {
                          return false;
                        }
                        if (_selectedRecipientFilter == 'staff' && !hasStaff) {
                          return false;
                        }
                      }

                      return true;
                    }).toList();

                    if (filteredAnnouncements.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Arama kriterlerine uygun duyuru bulunamadı',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: filteredAnnouncements.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final doc = filteredAnnouncements[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final title = data['title'] ?? 'Başlıksız';
                        final createdAt = data['createdAt'] as Timestamp?;
                        final publishDate = data['publishDate'] as Timestamp?;
                        final status = data['status'] ?? 'published';
                        final sendSms = data['sendSms'] as bool? ?? false;
                        final readBy = data['readBy'] as List<dynamic>? ?? [];

                        final statusText = status == 'scheduled'
                            ? 'Beklemede'
                            : 'Gönderildi';
                        final statusColor = status == 'scheduled'
                            ? Colors.orange
                            : Colors.green;
                        final publishDateTime = publishDate?.toDate();
                        final createdDateTime = createdAt?.toDate();

                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: statusColor),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            status == 'scheduled'
                                                ? Icons.schedule
                                                : Icons.check_circle,
                                            size: 16,
                                            color: statusColor,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            statusText,
                                            style: TextStyle(
                                              color: statusColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    FilledButton.tonal(
                                      onPressed: () async {
                                        final schoolId =
                                            await _announcementService
                                                .getSchoolId();
                                        if (schoolId != null && mounted) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (ctx) =>
                                                  AnnouncementDetailScreen(
                                                    announcementId: doc.id,
                                                    schoolId: schoolId,
                                                  ),
                                            ),
                                          );
                                        }
                                      },
                                      child: const Text('Detay'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 8,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.send,
                                          size: 14,
                                          color: Colors.grey[600],
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Gönderim: ${createdDateTime != null ? '${createdDateTime.day}/${createdDateTime.month}/${createdDateTime.year} ${createdDateTime.hour.toString().padLeft(2, '0')}:${createdDateTime.minute.toString().padLeft(2, '0')}' : '-'}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.publish,
                                          size: 14,
                                          color: Colors.grey[600],
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Yayın: ${publishDateTime != null ? '${publishDateTime.day}/${publishDateTime.month}/${publishDateTime.year} ${publishDateTime.hour.toString().padLeft(2, '0')}:${publishDateTime.minute.toString().padLeft(2, '0')}' : '-'}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          size: 14,
                                          color: Colors.green[600],
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${readBy.length} okundu',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.green[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (sendSms)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.sms,
                                            size: 14,
                                            color: Colors.blue[600],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'SMS',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.blue[700],
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
