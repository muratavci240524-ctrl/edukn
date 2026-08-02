import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Cross-Platform WebRTC Peer-to-Peer Arama Servisi
/// 
/// flutter_webrtc paketi kullanarak Web, Android ve iOS'ta
/// Firebase Firestore üzerinden sinyalleşme (signaling) yaparak
/// iki cihaz arasında doğrudan (P2P) ses ve görüntü aktarımı sağlar.
class WebRtcService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ========== STATE ==========
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  StreamSubscription? _answerSubscription;
  StreamSubscription? _candidateSubscription;
  StreamSubscription? _offerSubscription;

  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isDisposed = false;

  // ========== CALLBACKS ==========
  /// Remote stream hazır olduğunda çağrılır (karşı tarafın kamerası/mikrofonu)
  VoidCallback? onRemoteStreamReady;
  /// Local stream hazır olduğunda çağrılır (kendi kameramız/mikrofonumuz)
  VoidCallback? onLocalStreamReady;
  /// P2P bağlantı durumu değiştiğinde çağrılır
  ValueChanged<String>? onConnectionStateChanged;
  /// ICE bağlantısı kurulduğunda çağrılır (medya gerçekten akmaya başladı)
  VoidCallback? onMediaConnected;

  // ========== GETTERS ==========
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  bool get isMuted => _isMuted;
  bool get isCameraOff => _isCameraOff;

  // ========== STUN/TURN SUNUCULARI ==========
  /// Google'ın ücretsiz STUN sunucuları. NAT arkasındaki cihazların
  /// birbirini bulmasını sağlar.
  static const Map<String, dynamic> _iceConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
    ],
  };

  // ====================================================================
  // 1) LOCAL STREAM — Kamera ve Mikrofon Erişimi
  // ====================================================================

  /// Kullanıcının kamera ve mikrofon akışını alır.
  /// [isVideo] true ise hem kamera hem mikrofon açılır,
  /// false ise sadece mikrofon açılır (sesli arama).
  Future<MediaStream?> initLocalStream({required bool isVideo}) async {
    if (_isDisposed) return null;
    try {
      final constraints = <String, dynamic>{
        'audio': true,
        'video': isVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 480},
              }
            : false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      
      debugPrint('[WebRTC] Local stream alındı: ${_localStream?.id}, '
          'audio tracks: ${_localStream?.getAudioTracks().length}, '
          'video tracks: ${_localStream?.getVideoTracks().length}');
      onLocalStreamReady?.call();
      return _localStream;
    } catch (e) {
      debugPrint('[WebRTC] Kamera/Mikrofon erişim hatası: $e');
      return null;
    }
  }

  // ====================================================================
  // 2) PEER CONNECTION — RTCPeerConnection Oluşturma
  // ====================================================================

  /// RTCPeerConnection objesini oluşturur ve event listener'ları bağlar.
  Future<RTCPeerConnection> _createPeerConnection() async {
    final pc = await createPeerConnection(_iceConfiguration);

    // Bağlantı durumu değişikliklerini dinle
    pc.onConnectionState = (RTCPeerConnectionState state) {
      final stateStr = state.toString().split('.').last;
      debugPrint('[WebRTC] Connection state: $stateStr');
      onConnectionStateChanged?.call(stateStr);
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      final stateStr = state.toString().split('.').last;
      debugPrint('[WebRTC] ICE connection state: $stateStr');
      onConnectionStateChanged?.call(stateStr);
      
      // ICE bağlantısı kuruldu — medya gerçekten akmaya başladı
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        debugPrint('[WebRTC] ✅ Medya bağlantısı kuruldu!');
        onMediaConnected?.call();
      }
    };

    pc.onIceGatheringState = (RTCIceGatheringState state) {
      debugPrint('[WebRTC] ICE gathering state: ${state.toString().split('.').last}');
    };

    // Remote stream geldiğinde (karşı tarafın medyası)
    // onTrack kullanılır (modern WebRTC API)
    pc.onTrack = (RTCTrackEvent event) {
      debugPrint('[WebRTC] onTrack fired: kind=${event.track.kind}, '
          'streams=${event.streams.length}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        debugPrint('[WebRTC] Remote stream alındı: ${_remoteStream?.id}, '
            'tracks: ${_remoteStream?.getTracks().length}');
        onRemoteStreamReady?.call();
      }
    };

    // Fallback: onAddStream (eski tarayıcılar için)
    pc.onAddStream = (MediaStream stream) {
      if (_remoteStream == null) {
        _remoteStream = stream;
        debugPrint('[WebRTC] Remote stream (onAddStream fallback): ${stream.id}');
        onRemoteStreamReady?.call();
      }
    };

    return pc;
  }

  /// Local stream'deki track'leri PeerConnection'a ekler (addTrack API)
  void _addLocalTracks(RTCPeerConnection pc) {
    if (_localStream == null) return;
    
    for (final track in _localStream!.getTracks()) {
      pc.addTrack(track, _localStream!);
      debugPrint('[WebRTC] Track eklendi: ${track.kind} (${track.id})');
    }
    
    debugPrint('[WebRTC] Toplam ${_localStream!.getTracks().length} track eklendi');
  }

  // ====================================================================
  // 3) OFFER — Arama Başlatan Taraf (Caller)
  // ====================================================================

  /// Arama başlatan taraf (Caller) için:
  /// 1. PeerConnection oluşturur
  /// 2. Local stream'i ekler
  /// 3. SDP Offer üretir
  /// 4. Offer'ı Firestore'a yazar
  /// 5. ICE Candidate'leri senkronize eder
  /// 6. Answer'ı dinlemeye başlar
  Future<void> createOffer({
    required String callId,
    required String localUserId,
  }) async {
    if (_isDisposed) return;

    _peerConnection = await _createPeerConnection();
    _addLocalTracks(_peerConnection!);

    // ICE Candidate'leri Firestore'a yaz
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (!_isDisposed) {
        _firestore
            .collection('calls')
            .doc(callId)
            .collection('candidates')
            .add({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'from': localUserId,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    };

    // SDP Offer oluştur
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await _peerConnection!.setLocalDescription(offer);

    debugPrint('[WebRTC] Offer oluşturuldu, Firestore\'a yazılıyor...');
    debugPrint('[WebRTC] SDP type: ${offer.type}, sdp length: ${offer.sdp?.length}');

    // Offer'ı Firestore'a yaz
    await _firestore.collection('calls').doc(callId).update({
      'offer': {
        'type': offer.type,
        'sdp': offer.sdp,
      },
    });

    // Answer'ı dinle
    _listenForAnswer(callId);

    // Karşı tarafın ICE candidate'lerini dinle
    _listenForCandidates(callId, localUserId);
  }

  /// Karşı tarafın answer'ını dinler ve PeerConnection'a set eder.
  void _listenForAnswer(String callId) {
    _answerSubscription?.cancel();
    _answerSubscription = _firestore
        .collection('calls')
        .doc(callId)
        .snapshots()
        .listen((snapshot) async {
      if (_isDisposed || _peerConnection == null) return;

      final data = snapshot.data();
      if (data == null) return;

      final answer = data['answer'] as Map<String, dynamic>?;
      if (answer != null && answer['type'] == 'answer' && answer['sdp'] != null) {
        // Answer zaten set edilmiş mi kontrol et
        final currentRemote = await _peerConnection!.getRemoteDescription();
        if (currentRemote == null) {
          debugPrint('[WebRTC] Answer alındı, remote description set ediliyor...');
          final remoteDesc = RTCSessionDescription(
            answer['sdp'] as String,
            answer['type'] as String,
          );
          await _peerConnection!.setRemoteDescription(remoteDesc);
          debugPrint('[WebRTC] Remote description başarıyla set edildi');
        }
      }
    });
  }

  // ====================================================================
  // 4) ANSWER — Aramayı Kabul Eden Taraf (Receiver)
  // ====================================================================

  /// Aramayı kabul eden taraf (Receiver) için:
  /// 1. PeerConnection oluşturur
  /// 2. Local stream'i ekler
  /// 3. Firestore'dan offer'ı okur ve remote description olarak set eder
  /// 4. SDP Answer üretir
  /// 5. Answer'ı Firestore'a yazar
  /// 6. ICE Candidate'leri senkronize eder
  Future<void> createAnswer({
    required String callId,
    required String localUserId,
  }) async {
    if (_isDisposed) return;

    _peerConnection = await _createPeerConnection();
    _addLocalTracks(_peerConnection!);

    // ICE Candidate'leri Firestore'a yaz
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (!_isDisposed) {
        _firestore
            .collection('calls')
            .doc(callId)
            .collection('candidates')
            .add({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'from': localUserId,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    };

    // Firestore'dan offer'ı oku
    final callDoc = await _firestore.collection('calls').doc(callId).get();
    final callData = callDoc.data();
    if (callData == null) {
      debugPrint('[WebRTC] Call document bulunamadı!');
      return;
    }

    final offer = callData['offer'] as Map<String, dynamic>?;
    if (offer == null || offer['sdp'] == null) {
      debugPrint('[WebRTC] Offer bulunamadı, dinlemeye başlıyoruz...');
      // Offer henüz yazılmamış olabilir, dinle
      _listenForOffer(callId, localUserId);
      return;
    }

    // Offer'ı set et
    final remoteDesc = RTCSessionDescription(
      offer['sdp'] as String,
      offer['type'] as String,
    );
    await _peerConnection!.setRemoteDescription(remoteDesc);
    debugPrint('[WebRTC] Remote description (offer) set edildi');

    // Answer oluştur
    final answer = await _peerConnection!.createAnswer({});
    await _peerConnection!.setLocalDescription(answer);

    debugPrint('[WebRTC] Answer oluşturuldu, Firestore\'a yazılıyor...');

    // Answer'ı Firestore'a yaz
    await _firestore.collection('calls').doc(callId).update({
      'answer': {
        'type': answer.type,
        'sdp': answer.sdp,
      },
    });

    // Karşı tarafın ICE candidate'lerini dinle
    _listenForCandidates(callId, localUserId);
  }

  /// Offer henüz yazılmamışsa dinler (race condition koruması)
  void _listenForOffer(String callId, String localUserId) {
    _offerSubscription?.cancel();
    _offerSubscription = _firestore
        .collection('calls')
        .doc(callId)
        .snapshots()
        .listen((snapshot) async {
      if (_isDisposed || _peerConnection == null) return;

      final data = snapshot.data();
      if (data == null) return;

      final offer = data['offer'] as Map<String, dynamic>?;
      if (offer != null && offer['sdp'] != null) {
        _offerSubscription?.cancel();

        final remoteDesc = RTCSessionDescription(
          offer['sdp'] as String,
          offer['type'] as String,
        );
        await _peerConnection!.setRemoteDescription(remoteDesc);

        final answer = await _peerConnection!.createAnswer({});
        await _peerConnection!.setLocalDescription(answer);

        await _firestore.collection('calls').doc(callId).update({
          'answer': {
            'type': answer.type,
            'sdp': answer.sdp,
          },
        });

        _listenForCandidates(callId, localUserId);
      }
    });
  }

  // ====================================================================
  // 5) ICE CANDIDATES — Bağlantı Noktası Senkronizasyonu
  // ====================================================================

  /// Karşı taraftan gelen ICE candidate'leri dinler ve PeerConnection'a ekler.
  /// [localUserId] ile kendi candidate'lerimizi filtreleriz.
  void _listenForCandidates(String callId, String localUserId) {
    _candidateSubscription?.cancel();
    _candidateSubscription = _firestore
        .collection('calls')
        .doc(callId)
        .collection('candidates')
        .snapshots()
        .listen((snapshot) {
      if (_isDisposed || _peerConnection == null) return;

      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data == null) continue;

          // Sadece karşı taraftan gelen candidate'leri ekle
          if (data['from'] != localUserId && data['candidate'] != null) {
            try {
              final candidate = RTCIceCandidate(
                data['candidate'] as String,
                data['sdpMid'] as String?,
                data['sdpMLineIndex'] as int?,
              );
              _peerConnection!.addCandidate(candidate);
              debugPrint('[WebRTC] Remote ICE candidate eklendi');
            } catch (e) {
              debugPrint('[WebRTC] ICE candidate ekleme hatası: $e');
            }
          }
        }
      }
    });
  }

  // ====================================================================
  // 6) MİKROFON / KAMERA KONTROL
  // ====================================================================

  /// Mikrofonu susturur veya açar
  bool toggleMute() {
    if (_localStream == null) return _isMuted;

    _isMuted = !_isMuted;
    final audioTracks = _localStream!.getAudioTracks();
    for (final track in audioTracks) {
      track.enabled = !_isMuted;
    }
    debugPrint('[WebRTC] Mikrofon: ${_isMuted ? "KAPALI" : "AÇIK"}');
    return _isMuted;
  }

  /// Kamerayı kapatır veya açar
  bool toggleCamera() {
    if (_localStream == null) return _isCameraOff;

    _isCameraOff = !_isCameraOff;
    final videoTracks = _localStream!.getVideoTracks();
    for (final track in videoTracks) {
      track.enabled = !_isCameraOff;
    }
    debugPrint('[WebRTC] Kamera: ${_isCameraOff ? "KAPALI" : "AÇIK"}');
    return _isCameraOff;
  }

  // ====================================================================
  // 7) DISPOSE — Temizlik ve Kaynak Serbest Bırakma
  // ====================================================================

  /// Tüm kaynakları serbest bırakır:
  /// - Kamera/Mikrofon donanımları
  /// - PeerConnection
  /// - Firestore listener'ları
  /// - Firestore'daki signaling verilerini temizler
  Future<void> dispose(String callId) async {
    if (_isDisposed) return;
    _isDisposed = true;

    debugPrint('[WebRTC] Dispose başlıyor: $callId');

    // Firestore listener'ları iptal et
    _answerSubscription?.cancel();
    _candidateSubscription?.cancel();
    _offerSubscription?.cancel();
    _answerSubscription = null;
    _candidateSubscription = null;
    _offerSubscription = null;

    // Local stream'deki track'leri durdur (kamera/mikrofon donanımını serbest bırak)
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }

    // Remote stream temizle
    if (_remoteStream != null) {
      await _remoteStream!.dispose();
      _remoteStream = null;
    }

    // PeerConnection kapat
    if (_peerConnection != null) {
      await _peerConnection!.close();
      await _peerConnection!.dispose();
      _peerConnection = null;
    }

    // Firestore'daki signaling verilerini temizle (offer, answer, candidates)
    try {
      // Candidates alt koleksiyonunu sil
      final candidatesSnapshot = await _firestore
          .collection('calls')
          .doc(callId)
          .collection('candidates')
          .get();

      final batch = _firestore.batch();
      for (final doc in candidatesSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // Offer ve answer alanlarını temizle
      await _firestore.collection('calls').doc(callId).update({
        'offer': FieldValue.delete(),
        'answer': FieldValue.delete(),
      });

      debugPrint('[WebRTC] Firestore signaling verileri temizlendi');
    } catch (e) {
      debugPrint('[WebRTC] Firestore temizlik hatası (önemsiz): $e');
    }

    debugPrint('[WebRTC] Dispose tamamlandı');
  }
}
