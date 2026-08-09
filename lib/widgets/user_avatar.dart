import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Uygulama genelinde kullanılan akıllı kullanıcı avatar widget'ı.
/// - profileImageUrl varsa → fotoğrafı gösterir
/// - yoksa → renkli isim baş harfleri gösterir
/// - userId verilirse Firestore'dan otomatik çeker (cache'li)
class UserAvatar extends StatelessWidget {
  final String? imageUrl;    // Doğrudan URL (varsa Firestore sorgusu atlanır)
  final String? userId;      // Firestore'dan çekmek için UID
  final String displayName;  // Fallback için isim
  final double radius;
  final Color? backgroundColor;

  const UserAvatar({
    Key? key,
    this.imageUrl,
    this.userId,
    this.displayName = '',
    this.radius = 20,
    this.backgroundColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Eğer URL doğrudan verilmişse hemen göster
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return _buildAvatar(imageUrl);
    }

    // userId varsa cache'den veya Firestore'dan çek
    if (userId != null && userId!.isNotEmpty) {
      final cached = UserAvatarCache.get(userId!);
      if (cached != null) {
        return _buildAvatar(cached.isEmpty ? null : cached);
      }
      return FutureBuilder<String?>(
        future: UserAvatarCache.fetch(userId!),
        builder: (context, snapshot) {
          return _buildAvatar(snapshot.data);
        },
      );
    }

    // Hiçbir şey yoksa sadece baş harf
    return _buildAvatar(null);
  }

  Widget _buildAvatar(String? url) {
    final bgColor = backgroundColor ?? _colorFromName(displayName);
    final initials = _initials(displayName);

    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bgColor,
        backgroundImage: NetworkImage(url),
        onBackgroundImageError: (_, __) {},
        child: null,
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: bgColor,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }

  String _initials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  Color _colorFromName(String name) {
    if (name.isEmpty) return const Color(0xFF6366F1);
    final colors = [
      const Color(0xFF6366F1),
      const Color(0xFF8B5CF6),
      const Color(0xFF3B82F6),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF06B6D4),
      const Color(0xFFEC4899),
    ];
    int hash = 0;
    for (final c in name.codeUnits) {
      hash = (hash * 31 + c) & 0xFFFFFFFF;
    }
    return colors[hash % colors.length];
  }
}

/// In-memory cache — uygulama hayatı boyunca Firestore sorgularını azaltır
class UserAvatarCache {
  static final Map<String, String> _cache = {};

  static String? get(String userId) => _cache[userId];

  static Future<String?> fetch(String userId) async {
    if (_cache.containsKey(userId)) return _cache[userId];
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final url = doc.data()?['profileImageUrl'] as String? ?? '';
      _cache[userId] = url;
      return url.isEmpty ? null : url;
    } catch (_) {
      return null;
    }
  }

  static void invalidate(String userId) => _cache.remove(userId);
  static void set(String userId, String url) => _cache[userId] = url;
}
