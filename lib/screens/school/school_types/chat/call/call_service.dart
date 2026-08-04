import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'call_models.dart';
import '../chat_models.dart';

class CallService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  /// FCM Token Verisini Firestore'a Kaydetme
  Future<void> registerFcmToken() async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await messaging.getToken();
      if (token != null) {
        await _firestore.collection('users').doc(uid).set({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      messaging.onTokenRefresh.listen((newToken) {
        _firestore.collection('users').doc(uid).set({
          'fcmToken': newToken,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint("FCM token kayıt hatası: $e");
    }
  }

  /// Arama Başlatma (Caller)
  Future<CallSession?> startCall({
    required String receiverId,
    required String receiverName,
    String? receiverRole,
    String? receiverAvatar,
    required CallType callType,
    required String callerName,
    String? callerRole,
    String? callerAvatar,
  }) async {
    // Arama modülü etkin mi kontrol et (Super Admin panelinden yönetilir)
    try {
      final configDoc = await _firestore.collection('appConfig').doc('callModule').get();
      if (configDoc.exists && configDoc.data() != null) {
        final enabled = configDoc.data()!['enabled'] ?? true;
        if (enabled == false) {
          debugPrint('Arama modülü devre dışı');
          return null;
        }
      }
    } catch (_) {}

    final uid = currentUserId ?? 'local_user';

    // 📞 MEŞGUL KONTROLÜ: Aranan kişi başka bir görüşmede mi?
    final busyStatus = await isUserBusy(receiverId);
    if (busyStatus != null) {
      debugPrint('📵 ${receiverName} şu anda meşgul (${busyStatus})');
      throw CallBusyException(
        '${receiverName} şu anda başka bir görüşmede. Lütfen daha sonra tekrar deneyin.',
      );
    }

    // 📞 Arayan kişi de başka bir görüşmede mi? (Çift yönlü kontrol)
    final callerBusy = await isUserBusy(uid);
    if (callerBusy != null) {
      debugPrint('📵 Arayan kişi zaten görüşmede ($callerBusy)');
      throw CallBusyException(
        'Zaten aktif bir görüşmeniz var. Lütfen önce mevcut görüşmeyi sonlandırın.',
      );
    }

    String resolvedCallerName = callerName;
    String? resolvedCallerRole = callerRole;
    String? resolvedCallerAvatar = callerAvatar;

    String resolvedReceiverName = receiverName;
    String? resolvedReceiverRole = receiverRole;
    String? resolvedReceiverAvatar = receiverAvatar;

    bool isRealName(String? s) {
      if (s == null || s.trim().isEmpty) return false;
      final clean = s.trim();
      if (clean.contains('@')) return false;
      if (RegExp(r'^\d+$').hasMatch(clean)) return false;
      if (clean == 'Kullanıcı' || clean == 'Siz' || clean == 'İsimsiz') return false;
      return true;
    }

    // Caller Details Resolution (If email, numeric username or generic placeholder)
    final callerInfo = await _getUserDetails(uid);
    if (!isRealName(resolvedCallerName) && callerInfo['name'] != null && isRealName(callerInfo['name'])) {
      resolvedCallerName = callerInfo['name']!;
    }
    if (resolvedCallerRole == null || resolvedCallerRole.isEmpty || resolvedCallerRole == 'Personel' || resolvedCallerRole == 'Kullanıcı') {
      if (callerInfo['role'] != null && callerInfo['role']!.isNotEmpty) {
        resolvedCallerRole = callerInfo['role']!;
      }
    }
    if (resolvedCallerAvatar == null && callerInfo['avatar'] != null) {
      resolvedCallerAvatar = callerInfo['avatar'];
    }

    // Receiver Details Resolution (If email, numeric username or generic placeholder)
    final receiverInfo = await _getUserDetails(receiverId);
    if (!isRealName(resolvedReceiverName) && receiverInfo['name'] != null && isRealName(receiverInfo['name'])) {
      resolvedReceiverName = receiverInfo['name']!;
    }
    if (resolvedReceiverRole == null || resolvedReceiverRole.isEmpty || resolvedReceiverRole == 'Kullanıcı' || resolvedReceiverRole == 'Personel') {
      if (receiverInfo['role'] != null && receiverInfo['role']!.isNotEmpty) {
        resolvedReceiverRole = receiverInfo['role']!;
      }
    }
    if (resolvedReceiverAvatar == null && receiverInfo['avatar'] != null) {
      resolvedReceiverAvatar = receiverInfo['avatar'];
    }

    final session = CallSession(
      id: 'call_${DateTime.now().millisecondsSinceEpoch}',
      callerId: uid,
      callerName: resolvedCallerName,
      callerRole: _formatDisplayRole(resolvedCallerRole),
      callerAvatar: resolvedCallerAvatar,
      receiverId: receiverId,
      receiverName: resolvedReceiverName,
      receiverRole: _formatDisplayRole(resolvedReceiverRole),
      receiverAvatar: resolvedReceiverAvatar,
      callType: callType,
      status: CallStatus.ringing,
      createdAt: DateTime.now(),
    );

    try {
      final docRef = _firestore.collection('calls').doc(session.id);
      await docRef.set(session.toMap());
    } catch (e) {
      debugPrint("Firestore call write permission fallback: $e");
    }

    return session;
  }

  /// 📵 Kullanıcının aktif bir görüşmesi var mı kontrol et
  /// Dönüş: null = müsait, String = meşgul durumu açıklaması
  Future<String?> isUserBusy(String userId) async {
    try {
      // Kullanıcı arayan mı? (caller olarak aktif arama)
      final callerCalls = await _firestore
          .collection('calls')
          .where('callerId', isEqualTo: userId)
          .where('status', whereIn: ['ringing', 'accepted'])
          .limit(1)
          .get();

      if (callerCalls.docs.isNotEmpty) {
        final callData = callerCalls.docs.first.data();
        final createdAt = callData['createdAt'] as dynamic;
        
        // 60 saniyeden eski "ringing" aramaları otomatik sonlandır (asılı kalmayı önle)
        if (callData['status'] == 'ringing' && createdAt != null) {
          DateTime callTime;
          if (createdAt is DateTime) {
            callTime = createdAt;
          } else if (createdAt.toDate != null) {
            callTime = createdAt.toDate();
          } else {
            callTime = DateTime.now();
          }
          
          if (DateTime.now().difference(callTime).inSeconds > 60) {
            // Eski asılı kalmış arama, otomatik temizle
            await _firestore.collection('calls').doc(callerCalls.docs.first.id).update({
              'status': 'ended',
            });
            return null; // Müsait
          }
        }
        
        return 'Arayan olarak görüşmede';
      }

      // Kullanıcı aranan mı? (receiver olarak aktif arama)
      final receiverCalls = await _firestore
          .collection('calls')
          .where('receiverId', isEqualTo: userId)
          .where('status', whereIn: ['ringing', 'accepted'])
          .limit(1)
          .get();

      if (receiverCalls.docs.isNotEmpty) {
        final callData = receiverCalls.docs.first.data();
        final createdAt = callData['createdAt'] as dynamic;
        
        // 60 saniyeden eski "ringing" aramaları otomatik sonlandır
        if (callData['status'] == 'ringing' && createdAt != null) {
          DateTime callTime;
          if (createdAt is DateTime) {
            callTime = createdAt;
          } else if (createdAt.toDate != null) {
            callTime = createdAt.toDate();
          } else {
            callTime = DateTime.now();
          }
          
          if (DateTime.now().difference(callTime).inSeconds > 60) {
            await _firestore.collection('calls').doc(receiverCalls.docs.first.id).update({
              'status': 'ended',
            });
            return null; // Müsait
          }
        }
        
        return 'Aranan olarak görüşmede';
      }

      return null; // Müsait
    } catch (e) {
      debugPrint('Meşgul kontrolü hatası: $e');
      return null; // Hata durumunda aramaya izin ver
    }
  }

  /// Rolü Kullanıcı İsteğine Göre Biçimlendirme (GENEL MÜDÜR, MÜDÜR, ÖĞRETMEN, ÖĞRENCİ, VELİ, PERSONEL)
  String _formatDisplayRole(String? rawRole, [Map<String, dynamic>? data]) {
    if (data != null) {
      final userType = (data['type'] ?? data['userType'] ?? '').toString().toLowerCase();
      final role = (data['role'] ?? '').toString().toLowerCase();
      final title = (data['title'] ?? '').toString();

      if (role == 'genel_mudur' || role == 'genel mudur' || title.toLowerCase().contains('genel müdür') || title.toLowerCase().contains('genel mudur')) {
        return 'GENEL MÜDÜR';
      }
      if (role == 'mudur' || role == 'müdür' || role == 'manager' || role == 'school_manager' || title.toLowerCase().contains('müdür')) {
        return 'MÜDÜR';
      }
      if (userType == 'teacher' || role == 'ogretmen' || role == 'öğretmen' || role == 'teacher') {
        return 'ÖĞRETMEN';
      }
      if (userType == 'student' || role == 'ogrenci' || role == 'öğrenci' || role == 'student') {
        return 'ÖĞRENCİ';
      }
      if (userType == 'parent' || role == 'veli' || role == 'parent') {
        return 'VELİ';
      }
      if (title.isNotEmpty) return title.toUpperCase();
    }

    if (rawRole == null || rawRole.isEmpty) return 'PERSONEL';
    final lower = rawRole.toLowerCase().trim();

    if (lower.contains('genel müdür') || lower.contains('genel_mudur') || lower == 'genel mudur') return 'GENEL MÜDÜR';
    if (lower.contains('müdür') || lower.contains('mudur') || lower == 'manager' || lower == 'school_manager') return 'MÜDÜR';
    if (lower.contains('öğretmen') || lower.contains('ogretmen') || lower == 'teacher') return 'ÖĞRETMEN';
    if (lower.contains('öğrenci') || lower.contains('ogrenci') || lower == 'student') return 'ÖĞRENCİ';
    if (lower.contains('veli') || lower == 'parent') return 'VELİ';

    return rawRole.toUpperCase();
  }

  /// Kullanıcının Gerçek Ad Soyad, Rol ve Avatarını Firestore'dan Çözümleme
  Future<Map<String, String?>> _getUserDetails(String userId) async {
    try {
      bool isRealName(String? s) {
        if (s == null || s.trim().isEmpty) return false;
        final clean = s.trim();
        if (clean.contains('@')) return false;
        if (RegExp(r'^\d+$').hasMatch(clean)) return false; // Sadece rakamlardan oluşuyorsa (Kullanıcı Adı/TC No) gerçek ad soyad değildir
        if (clean == 'Kullanıcı' || clean == 'Siz' || clean == 'İsimsiz') return false;
        return true;
      }

      String extractName(Map<String, dynamic> data) {
        if (isRealName(data['fullName']?.toString())) return data['fullName'].toString().trim();
        if (isRealName(data['displayName']?.toString())) return data['displayName'].toString().trim();
        if (isRealName(data['adSoyad']?.toString())) return data['adSoyad'].toString().trim();
        
        final combined = '${data['name'] ?? ''} ${data['surname'] ?? ''}'.trim();
        if (isRealName(combined)) return combined;

        final firstLast = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
        if (isRealName(firstLast)) return firstLast;

        return '';
      }

      // 1. Personel / Yöneticiler Koleksiyonu (docId veya uid)
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        final realName = extractName(data);
        final role = _formatDisplayRole(data['title'] ?? data['branch'] ?? data['role'], data);
        final avatar = data['photoUrl'] ?? data['avatarUrl'];
        if (realName.isNotEmpty) {
          return {
            'name': realName,
            'role': role,
            'avatar': avatar?.toString(),
          };
        }
      }

      // 2. Öğrenciler Koleksiyonu
      final studentDoc = await _firestore.collection('students').doc(userId).get();
      if (studentDoc.exists) {
        final data = studentDoc.data()!;
        final realName = extractName(data);
        final role = 'ÖĞRENCİ';
        final avatar = data['photoUrl'] ?? data['avatarUrl'];
        if (realName.isNotEmpty) {
          return {
            'name': realName,
            'role': role,
            'avatar': avatar?.toString(),
          };
        }
      }

      // 3. Veliler Koleksiyonu
      final parentDoc = await _firestore.collection('parents').doc(userId).get();
      if (parentDoc.exists) {
        final data = parentDoc.data()!;
        final realName = extractName(data);
        final role = 'VELİ';
        final avatar = data['photoUrl'] ?? data['avatarUrl'];
        if (realName.isNotEmpty) {
          return {
            'name': realName,
            'role': role,
            'avatar': avatar?.toString(),
          };
        }
      }

      // 4. Kullanıcı Adı / Email İle Sorgulama Fallback (users collection)
      final queryByUsername = await _firestore
          .collection('users')
          .where('username', isEqualTo: userId)
          .limit(1)
          .get();
      if (queryByUsername.docs.isNotEmpty) {
        final data = queryByUsername.docs.first.data();
        final realName = extractName(data);
        final role = _formatDisplayRole(data['title'] ?? data['branch'] ?? data['role'], data);
        if (realName.isNotEmpty) {
          return {
            'name': realName,
            'role': role,
            'avatar': data['photoUrl']?.toString(),
          };
        }
      }
    } catch (e) {
      debugPrint("Kullanıcı detayları alma hatası: $e");
    }

    return {};
  }

  /// Aramayı Kabul Etme (Receiver)
  Future<void> acceptCall(String callId) async {
    try {
      await _firestore.collection('calls').doc(callId).update({
        'status': 'accepted',
      });
    } catch (e) {
      debugPrint("Arama kabul edildi (local state sync active)");
    }
  }

  /// Aramayı Reddetme (Receiver)
  Future<void> rejectCall(String callId) async {
    try {
      await _firestore.collection('calls').doc(callId).update({
        'status': 'rejected',
      });
    } catch (e) {
      debugPrint("Arama reddedildi (local state sync active)");
    }
  }

  /// Aramayı Sonlandırma / Kapatma (Caller veya Receiver)
  Future<void> endCall(String callId) async {
    try {
      await _firestore.collection('calls').doc(callId).update({
        'status': 'ended',
      });
    } catch (e) {
      debugPrint("Arama sonlandırıldı (local state sync active)");
    }
  }

  /// Arama Kaydını Sohbet İçerisine Yazma (WhatsApp Style Call Log)
  Future<void> logCallMessageToChat({
    required String callerId,
    required String receiverId,
    required CallType callType,
    required CallStatus status,
    int durationSeconds = 0,
  }) async {
    try {
      final isVideo = callType == CallType.video;
      final typeLabel = isVideo ? '📹 Görüntülü Arama' : '📞 Sesli Arama';

      String content = typeLabel;
      if (status == CallStatus.accepted) {
        final min = (durationSeconds ~/ 60).toString().padLeft(2, '0');
        final sec = (durationSeconds % 60).toString().padLeft(2, '0');
        content = '$typeLabel ($min:$sec)';
      } else if (status == CallStatus.rejected) {
        content = '$typeLabel (Reddedildi)';
      } else {
        content = '$typeLabel (Cevapsız Arama)';
      }

      final conversationsQuery = await _firestore
          .collection('conversations')
          .where('participantIds', arrayContains: callerId)
          .get();

      String? convId;
      for (var doc in conversationsQuery.docs) {
        final parts = List<String>.from(doc.data()['participantIds'] ?? []);
        if (parts.contains(receiverId) && parts.length <= 2) {
          convId = doc.id;
          break;
        }
      }

      if (convId == null) {
        final newDoc = await _firestore.collection('conversations').add({
          'participantIds': [callerId, receiverId],
          'unreadCount': 0,
          'isArchived': false,
          'isGroup': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        convId = newDoc.id;
      }

      final msg = ChatMessage(
        id: 'msg_call_${DateTime.now().millisecondsSinceEpoch}',
        senderId: callerId,
        content: content,
        timestamp: DateTime.now(),
        type: MessageType.call,
      );

      await _firestore
          .collection('conversations')
          .doc(convId)
          .collection('messages')
          .doc(msg.id)
          .set(msg.toMap());

      await _firestore.collection('conversations').doc(convId).update({
        'lastMessage': msg.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Call log write error: $e");
    }
  }

  /// Kullanıcının Gerçek Ad Soyad, Rol ve Avatarını Firestore'dan Çözümleme
  Future<Map<String, String?>> getUserDetailsPublic(String userId) async {
    return _getUserDetails(userId);
  }

  /// Gelen Aramaları Canlı Dinleme (Receiver için - İndeks Gecikmesiz Hızlı Stream)
  Stream<List<CallSession>> listenForIncomingCalls() {
    final uid = currentUserId;
    if (uid == null) return const Stream.empty();

    return _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((d) => CallSession.fromMap(d.data(), d.id))
          .where((s) => s.status == CallStatus.ringing)
          .toList();
    });
  }

  /// Aramanın Anlık Durumunu Dinleme (Status Stream)
  Stream<CallSession?> listenToCallStatus(String callId) {
    return _firestore
        .collection('calls')
        .doc(callId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) return null;
      return CallSession.fromMap(snapshot.data()!, snapshot.id);
    });
  }

  /// Arama modülü yapılandırmasını Firestore'dan oku
  /// Dönen Map: { enabled }
  /// Not: WebRTC P2P kullanıldığı için medya sunucusu yapılandırması gerekmez.
  Future<Map<String, dynamic>?> getCallModuleConfig() async {
    try {
      final doc = await _firestore.collection('appConfig').doc('callModule').get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!;
      }
    } catch (e) {
      debugPrint('Arama modülü yapılandırma okuma hatası: $e');
    }
    return null;
  }
}
