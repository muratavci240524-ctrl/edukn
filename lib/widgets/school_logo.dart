import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/user_permission_service.dart';
import 'edukn_logo.dart';
import 'web_image_renderer.dart';

/// Okul logosunun TEK kaynağı.
/// Logo `schools` koleksiyonundaki okul dokümanının `logoUrl` alanından okunur.
/// "Okul Bilgileri" ekranında logo değiştirilince [update] çağrılır ve
/// tüm app bar'lar anında yeni logoyu gösterir.
class SchoolLogoService {
  SchoolLogoService._();

  /// Güncel okul logosu (data URL veya http URL). Yoksa null → eduKN varsayılan logosu.
  static final ValueNotifier<String?> logoUrl = ValueNotifier<String?>(null);

  static String? _loadedInstId;
  static Future<void>? _loading;

  /// Verilen (veya oturumdaki) kurumun logosunu yükler. Aynı kurum için tekrar sorgulamaz.
  static Future<void> ensureLoaded([String? institutionId]) {
    final instId = (institutionId ??
            UserPermissionService.getCachedUserData()?['institutionId'])
        ?.toString()
        .toUpperCase();

    if (instId == null || instId.isEmpty) {
      // Kullanıcı verisi henüz yoksa yükleyip tekrar dene
      if (institutionId == null && _loading == null) {
        _loading = () async {
          try {
            final data = await UserPermissionService.loadUserData();
            final id = data?['institutionId']?.toString().toUpperCase();
            _loading = null;
            if (id != null && id.isNotEmpty) await ensureLoaded(id);
          } catch (_) {
            _loading = null;
          }
        }();
      }
      return _loading ?? Future.value();
    }

    if (_loadedInstId == instId && logoUrl.value != null) return _loading ?? Future.value();

    // Farklı bir okula geçildi veya logo henüz yüklenemedi: logoyu tazele
    _loadedInstId = instId;
    if (logoUrl.value == null) {
      _loading = _fetch(instId).whenComplete(() => _loading = null);
      return _loading!;
    }
    return Future.value();
  }

  static Future<void> _fetch(String instId) async {
    try {
      final variants = {instId, instId.toLowerCase(), instId.toUpperCase()}.toList();
      
      // 1. institutionId alanına göre sorgu
      final snap = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', whereIn: variants)
          .limit(1)
          .get();
      if (_loadedInstId != instId) return;
      if (snap.docs.isNotEmpty) {
        final d = snap.docs.first.data();
        final url = (d['logoUrl'] ?? d['logo'] ?? d['photoUrl'])?.toString();
        if (url != null && url.isNotEmpty) {
          logoUrl.value = url;
          return;
        }
      }

      // 2. Doküman ID'si doğrudan kurum kodu olan okul dokümanı
      final byId = await FirebaseFirestore.instance.collection('schools').doc(instId).get();
      if (_loadedInstId != instId) return;
      if (byId.exists) {
        final d = byId.data();
        final url = (d?['logoUrl'] ?? d?['logo'] ?? d?['photoUrl'])?.toString();
        if (url != null && url.isNotEmpty) {
          logoUrl.value = url;
          return;
        }
      }

      // 3. Kullanıcı dokümanındaki schoolId üzerinden sorgu
      final data = UserPermissionService.getCachedUserData() ?? await UserPermissionService.loadUserData();
      final sid = data?['schoolId']?.toString();
      if (sid != null && sid.isNotEmpty) {
        final sDoc = await FirebaseFirestore.instance.collection('schools').doc(sid).get();
        if (_loadedInstId != instId) return;
        if (sDoc.exists) {
          final d = sDoc.data();
          final url = (d?['logoUrl'] ?? d?['logo'] ?? d?['photoUrl'])?.toString();
          if (url != null && url.isNotEmpty) {
            logoUrl.value = url;
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('[SchoolLogoService] logo yüklenemedi: $e');
    }
  }

  /// Okul Bilgileri ekranında logo kaydedilince çağrılır.
  static void update(String institutionId, String? url) {
    _loadedInstId = institutionId.toUpperCase();
    logoUrl.value = (url != null && url.isNotEmpty) ? url : null;
  }

  /// Çıkış yapılırken çağrılır.
  static void clear() {
    _loadedInstId = null;
    _loading = null;
    logoUrl.value = null;
  }
}

/// App bar'larda kullanılan okul logosu. Okulun logosu yoksa eduKN logosu gösterilir.
class SchoolLogoImage extends StatefulWidget {
  final double width;
  final double height;
  final String? institutionId;

  /// true ise logo yokken sadece eduKN ikonu gösterilir (dar ekranlar için).
  final bool compact;

  const SchoolLogoImage({
    Key? key,
    this.width = 200,
    this.height = 38,
    this.institutionId,
    this.compact = false,
  }) : super(key: key);

  @override
  State<SchoolLogoImage> createState() => _SchoolLogoImageState();
}

class _SchoolLogoImageState extends State<SchoolLogoImage> {
  String? _lastUrl;
  Uint8List? _lastBytes;

  @override
  void initState() {
    super.initState();
    SchoolLogoService.ensureLoaded(widget.institutionId);
  }

  @override
  void didUpdateWidget(covariant SchoolLogoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.institutionId != widget.institutionId) {
      SchoolLogoService.ensureLoaded(widget.institutionId);
    }
  }

  Uint8List? _decode(String url) {
    if (_lastUrl == url) return _lastBytes;
    try {
      final comma = url.indexOf(',');
      final bytes = base64Decode(comma >= 0 ? url.substring(comma + 1) : url);
      _lastUrl = url;
      _lastBytes = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Widget _fallback() {
    if (widget.compact) {
      return EduKnLogo(iconSize: widget.height * 0.85, type: EduKnLogoType.iconOnly);
    }
    return buildWebImage(
      'assets/images/google_auth_full_logo_light.png',
      width: widget.width,
      height: widget.height,
      fit: BoxFit.contain,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: SchoolLogoService.logoUrl,
      builder: (context, url, _) {
        if (url == null || url.isEmpty) return _fallback();

        final Widget image;
        if (url.startsWith('http')) {
          image = Image.network(
            url,
            height: widget.height,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _fallback(),
          );
        } else {
          final bytes = _decode(url);
          if (bytes == null) return _fallback();
          image = Image.memory(
            bytes,
            height: widget.height,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => _fallback(),
          );
        }
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.width, maxHeight: widget.height),
          child: image,
        );
      },
    );
  }
}
