import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _userId;

  Map<String, bool> _settings = {
    'announcements': true,
    'studies': true,
    'homeworks': true,
    'messages': true,
    'exams': true,
    'socialMedia': true,
  };

  final List<_NotifItem> _items = [
    _NotifItem('announcements', 'Duyurular',
        'Okul duyuruları ve bilgilendirmeler', Icons.campaign_outlined, const Color(0xFF6366F1)),
    _NotifItem('studies', 'Etüt ve Ek Dersler',
        'Etüt programı ve ek ders bildirimleri', Icons.school_outlined, const Color(0xFF8B5CF6)),
    _NotifItem('homeworks', 'Ödevler',
        'Ödev atama ve teslim bildirimleri', Icons.assignment_outlined, const Color(0xFF3B82F6)),
    _NotifItem('messages', 'Mesajlar',
        'Yeni mesaj ve sohbet bildirimleri', Icons.forum_outlined, const Color(0xFF10B981)),
    _NotifItem('exams', 'Sınav Sonuçları',
        'Sınav sonuçları ve not bildirimleri', Icons.analytics_outlined, const Color(0xFFF59E0B)),
    _NotifItem('socialMedia', 'Sosyal Medya',
        'Yeni paylaşım ve beğeni bildirimleri', Icons.thumb_up_outlined, const Color(0xFFEC4899)),
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Önce UID ile dene
      var userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      // UID ile bulunamazsa email ile ara
      if (!userDoc.exists || userDoc.data() == null) {
        final query = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: user.email?.toLowerCase())
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          _userId = query.docs.first.id;
          final data = query.docs.first.data();
          if (data.containsKey('notificationSettings')) {
            final raw = Map<String, dynamic>.from(data['notificationSettings']);
            raw.forEach((k, v) {
              if (_settings.containsKey(k) && v is bool) _settings[k] = v;
            });
          }
        }
      } else {
        _userId = user.uid;
        final data = userDoc.data()!;
        if (data.containsKey('notificationSettings')) {
          final raw = Map<String, dynamic>.from(data['notificationSettings']);
          raw.forEach((k, v) {
            if (_settings.containsKey(k) && v is bool) _settings[k] = v;
          });
        }
      }
    } catch (e) {
      debugPrint('Bildirim ayarları yüklenirken hata: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleSetting(String key, bool value) async {
    setState(() => _settings[key] = value);
    try {
      final ref = _userId != null
          ? FirebaseFirestore.instance.collection('users').doc(_userId)
          : null;
      if (ref != null) {
        await ref.update({'notificationSettings.$key': value});
      }
    } catch (e) {
      debugPrint('Kayıt hatası: $e');
      // Hata olursa eski değere geri dön
      if (mounted) setState(() => _settings[key] = !value);
    }
  }

  Future<void> _saveAll() async {
    if (_userId == null) return;
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .update({'notificationSettings': _settings});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Bildirim ayarları kaydedildi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.indigo),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Bildirim Ayarları',
          style: GoogleFonts.inter(
            color: Colors.grey.shade900,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _isSaving ? null : _saveAll,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigo),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(_isSaving ? 'Kaydediliyor...' : 'Kaydet',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(foregroundColor: Colors.indigo),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Açıklama kartı
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.indigo.shade50, Colors.purple.shade50],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.indigo.shade100),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.notifications_active_outlined,
                                  color: Colors.indigo, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Bildirim Tercihleri',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.indigo.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'İstediğiniz bildirim türlerini açıp kapatabilirsiniz.',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: Colors.indigo.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Bildirim toggle listesi
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: _items.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final item = entry.value;
                            final isLast = idx == _items.length - 1;
                            return Column(
                              children: [
                                _buildToggleTile(item),
                                if (!isLast)
                                  Divider(
                                    height: 1,
                                    indent: 70,
                                    endIndent: 16,
                                    color: Colors.grey.shade100,
                                  ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Tümünü aç/kapat
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                for (final k in _settings.keys) {
                                  _toggleSetting(k, false);
                                }
                              },
                              icon: const Icon(Icons.notifications_off_outlined, size: 18),
                              label: Text('Tümünü Kapat',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade600,
                                side: BorderSide(color: Colors.red.shade200),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                for (final k in _settings.keys) {
                                  _toggleSetting(k, true);
                                }
                              },
                              icon: const Icon(Icons.notifications_active_outlined, size: 18),
                              label: Text('Tümünü Aç',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.green.shade700,
                                side: BorderSide(color: Colors.green.shade200),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildToggleTile(_NotifItem item) {
    final isOn = _settings[item.key] ?? true;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: item.color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.grey.shade900,
                  ),
                ),
                Text(
                  item.description,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: isOn,
            onChanged: (v) => _toggleSetting(item.key, v),
            activeColor: item.color,
            activeTrackColor: item.color.withOpacity(0.25),
            inactiveThumbColor: Colors.grey.shade400,
            inactiveTrackColor: Colors.grey.shade200,
          ),
        ],
      ),
    );
  }
}

class _NotifItem {
  final String key;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  const _NotifItem(this.key, this.label, this.description, this.icon, this.color);
}
