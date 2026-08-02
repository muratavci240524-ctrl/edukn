import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_models.dart';
import 'call_service.dart';
import 'webrtc_service.dart';

class CallScreenDialog extends StatefulWidget {
  final CallSession callSession;
  final bool isIncoming;

  const CallScreenDialog({
    Key? key,
    required this.callSession,
    this.isIncoming = false,
  }) : super(key: key);

  static String? _activeCallId;
  static bool get hasActiveCall => _activeCallId != null;

  static Future<void> showCall({
    required BuildContext context,
    required CallSession callSession,
    bool isIncoming = false,
  }) async {
    if (_activeCallId == callSession.id) return;
    if (_activeCallId != null) {
      debugPrint("Aktif arama mevcut ($_activeCallId), yeni arama engellendi: ${callSession.id}");
      return;
    }
    _activeCallId = callSession.id;

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => CallScreenDialog(
          callSession: callSession,
          isIncoming: isIncoming,
        ),
      );
    } finally {
      _activeCallId = null;
    }
  }

  @override
  State<CallScreenDialog> createState() => _CallScreenDialogState();
}

class _CallScreenDialogState extends State<CallScreenDialog>
    with SingleTickerProviderStateMixin {
  final CallService _callService = CallService();
  StreamSubscription<CallSession?>? _statusSubscription;
  late CallSession _currentSession;
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  final AudioPlayer _ringbackPlayer = AudioPlayer(); // Arayan taraf çalma sesi

  Timer? _durationTimer;
  int _callSeconds = 0;

  late AnimationController _pulseController;

  String? _resolvedName;
  String? _resolvedRole;

  bool _isCallConnected = false;
  bool _isRingtonePlaying = false;
  bool _isRingbackPlaying = false;
  Timer? _ringbackTimer;

  // ========== WEBRTC ==========
  WebRtcService? _webRtcService;
  bool _isWebRtcInitialized = false;
  bool _isMuted = false;
  bool _isCameraOff = false;

  // flutter_webrtc Video Renderers (cross-platform)
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _localRendererInitialized = false;
  bool _remoteRendererInitialized = false;
  bool _hasRemoteStream = false;
  bool _isMediaConnected = false; // ICE bağlantısı gerçekten kuruldu mu?

  @override
  void initState() {
    super.initState();
    _currentSession = widget.callSession;
    _resolveUserInfo();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    // Video renderer'ları initialize et
    _initRenderers();

    _listenToCallState();

    if (widget.isIncoming && _currentSession.status == CallStatus.ringing) {
      _startRingtone();
    } else if (!widget.isIncoming && _currentSession.status == CallStatus.ringing) {
      // Arayan taraf: dıııt dıııt çalma sesi başlat
      _startRingbackTone();
    }

    // Eğer zaten accepted ise (gecikmeli açılış) direkt WebRTC başlat
    if (_currentSession.status == CallStatus.accepted) {
      _isCallConnected = true;
      _startCallTimer();
      _initWebRtc(isCaller: !widget.isIncoming);
    }
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    _localRendererInitialized = true;
    await _remoteRenderer.initialize();
    _remoteRendererInitialized = true;
    if (mounted) setState(() {});
  }

  Future<void> _resolveUserInfo() async {
    final targetId = widget.isIncoming ? _currentSession.callerId : _currentSession.receiverId;
    final details = await _callService.getUserDetailsPublic(targetId);
    if (mounted) {
      setState(() {
        if (details['name'] != null && details['name']!.isNotEmpty) {
          _resolvedName = details['name'];
        }
        if (details['role'] != null && details['role']!.isNotEmpty) {
          _resolvedRole = details['role'];
        }
      });
    }
  }

  // ========== WEBRTC ENTEGRASYONU ==========

  Future<void> _initWebRtc({required bool isCaller}) async {
    if (_isWebRtcInitialized) return;
    _isWebRtcInitialized = true;

    final isVideo = _currentSession.callType == CallType.video;
    final localUserId = FirebaseAuth.instance.currentUser?.uid ?? 'local_user';

    _webRtcService = WebRtcService();

    // Remote stream callback
    _webRtcService!.onRemoteStreamReady = () {
      if (mounted && _remoteRendererInitialized) {
        _remoteRenderer.srcObject = _webRtcService!.remoteStream;
        setState(() => _hasRemoteStream = true);
        debugPrint('[CallScreen] Remote stream renderer\'a bağlandı');
      }
    };

    // Medya bağlantısı kuruldu callback (ICE connected)
    _webRtcService!.onMediaConnected = () {
      if (mounted && !_isMediaConnected) {
        setState(() => _isMediaConnected = true);
        debugPrint('[CallScreen] ✅ Medya bağlantısı kuruldu, animasyon kaldırılıyor');
      }
    };

    // Connection state callback
    _webRtcService!.onConnectionStateChanged = (state) {
      debugPrint('[CallScreen] WebRTC bağlantı durumu: $state');
      if (state == 'RTCPeerConnectionStateDisconnected' || 
          state == 'RTCPeerConnectionStateFailed' || 
          state == 'RTCPeerConnectionStateClosed' ||
          state == 'disconnected' || 
          state == 'failed' || 
          state == 'closed') {
        if (mounted && _isCallConnected) {
          debugPrint('[CallScreen] Bağlantı kesildi');
        }
      }
    };

    // 1. Local stream'i al (kamera + mikrofon)
    final localStream = await _webRtcService!.initLocalStream(isVideo: isVideo);
    if (localStream == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kamera/Mikrofon erişimi reddedildi. Lütfen tarayıcı izinlerini kontrol edin.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // 2. Local video'yu renderer'a bağla
    if (_localRendererInitialized) {
      _localRenderer.srcObject = localStream;
    }

    // 3. Caller mı Receiver mı?
    if (isCaller) {
      await _webRtcService!.createOffer(
        callId: _currentSession.id,
        localUserId: localUserId,
      );
    } else {
      await _webRtcService!.createAnswer(
        callId: _currentSession.id,
        localUserId: localUserId,
      );
    }

    if (mounted) setState(() {});
  }

  void _stopWebRtc() {
    // Renderer'ların stream bağlantısını kes
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;

    // WebRTC servisini dispose et
    if (_webRtcService != null) {
      _webRtcService!.dispose(_currentSession.id);
      _webRtcService = null;
    }

    _isWebRtcInitialized = false;
    _hasRemoteStream = false;
  }

  // ========== ARAMA DURUMU ==========

  /// Gelen arama zil sesi (receiver tarafı)
  void _startRingtone() async {
    if (_isRingtonePlaying) return;
    try {
      _isRingtonePlaying = true;
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.play(
        UrlSource('https://assets.mixkit.co/active_storage/sfx/1359/1359-preview.mp3'),
      );
    } catch (e) {
      debugPrint("Ringtone error: $e");
    }
  }

  void _stopRingtone() async {
    if (!_isRingtonePlaying) return;
    _isRingtonePlaying = false;
    try {
      await _ringtonePlayer.stop();
      await _ringtonePlayer.release();
    } catch (_) {}
  }

  /// Arayan taraf çalma sesi — klasik telefon paterni:
  /// tüüt (1.5sn) → sessizlik (3sn) → tüüt (1.5sn) → sessizlik (3sn) ...
  void _startRingbackTone() async {
    if (_isRingbackPlaying) return;
    _isRingbackPlaying = true;

    // İlk tüüt'ü hemen çal
    await _playRingbackBeep();

    // Sonra her 4.5 saniyede bir tekrarla (1.5sn ses + 3sn sessizlik)
    _ringbackTimer = Timer.periodic(const Duration(milliseconds: 4500), (_) {
      if (_isRingbackPlaying) {
        _playRingbackBeep();
      }
    });
  }

  /// Tek bir "tüüt" sesi çalar (1.5 saniye), sonra otomatik durur
  Future<void> _playRingbackBeep() async {
    try {
      await _ringbackPlayer.setReleaseMode(ReleaseMode.release);
      await _ringbackPlayer.play(
        UrlSource('https://assets.mixkit.co/active_storage/sfx/2862/2862-preview.mp3'),
      );
      await _ringbackPlayer.setVolume(0.4);

      // 1.5 saniye sonra sesi kes (sessizlik bölümü başlasın)
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (_isRingbackPlaying) {
          _ringbackPlayer.stop();
        }
      });
    } catch (e) {
      debugPrint("Ringback beep error: $e");
    }
  }

  void _stopRingbackTone() async {
    if (!_isRingbackPlaying) return;
    _isRingbackPlaying = false;
    _ringbackTimer?.cancel();
    _ringbackTimer = null;
    try {
      await _ringbackPlayer.stop();
      await _ringbackPlayer.release();
    } catch (_) {}
  }

  @override
  void dispose() {
    _stopRingtone();
    _stopRingbackTone();
    _stopWebRtc();
    _ringtonePlayer.dispose();
    _ringbackPlayer.dispose();
    _statusSubscription?.cancel();
    _durationTimer?.cancel();
    _pulseController.dispose();
    // Renderer'ları temizle
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _listenToCallState() {
    _statusSubscription = _callService
        .listenToCallStatus(_currentSession.id)
        .listen((updatedSession) {
      if (updatedSession == null || !mounted) return;

      final previousStatus = _currentSession.status;
      setState(() => _currentSession = updatedSession);

      if (updatedSession.status == CallStatus.accepted && !_isCallConnected) {
        _isCallConnected = true;
        _stopRingtone();
        _stopRingbackTone(); // Arayan tarafın çalma sesini durdur
        _startCallTimer();
        // Arayan taraf: kabul geldi, WebRTC başlat (Offer oluştur)
        // Alıcı taraf: zaten _buildIncomingControls'de başlatılıyor
        if (!widget.isIncoming) {
          _initWebRtc(isCaller: true);
        }
      } else if (updatedSession.status == CallStatus.rejected) {
        _stopRingtone();
        _stopRingbackTone();
        _showToastAndClose('Arama Reddedildi');
      } else if (updatedSession.status == CallStatus.ended) {
        _stopRingtone();
        _stopRingbackTone();
        _stopWebRtc();
        if (previousStatus == CallStatus.accepted) {
          _showToastAndClose('Arama Sonlandırıldı');
        } else {
          _closeDialog();
        }
      }
    });
  }

  void _startCallTimer() {
    if (_durationTimer != null) return;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _callSeconds++);
    });
  }

  void _showToastAndClose(String message) {
    _durationTimer?.cancel();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      _closeDialog();
    }
  }

  void _closeDialog() {
    _stopRingtone();
    _stopRingbackTone();
    _stopWebRtc();
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _getStatusText() {
    if (_currentSession.status == CallStatus.accepted) {
      return _formatDuration(_callSeconds);
    }
    if (widget.isIncoming) {
      return _currentSession.callType == CallType.video
          ? 'Gelen Görüntülü Arama...'
          : 'Gelen Sesli Arama...';
    }
    return 'Çalıyor...';
  }

  // ========== BUILD ==========

  @override
  Widget build(BuildContext context) {
    final isVideo = _currentSession.callType == CallType.video;
    final isAccepted = _currentSession.status == CallStatus.accepted;

    bool isRealName(String? s) {
      if (s == null || s.trim().isEmpty) return false;
      final clean = s.trim();
      if (clean.contains('@')) return false;
      if (RegExp(r'^\d+$').hasMatch(clean)) return false;
      if (clean == 'Kullanıcı' || clean == 'Siz' || clean == 'İsimsiz') return false;
      return true;
    }

    final rawName = widget.isIncoming
        ? _currentSession.callerName
        : _currentSession.receiverName;
    final rawRole = widget.isIncoming
        ? _currentSession.callerRole
        : _currentSession.receiverRole;

    final displayName = isRealName(_resolvedName)
        ? _resolvedName!
        : (isRealName(rawName) ? rawName : (rawName.contains('@') ? rawName.split('@').first : 'Kullanıcı'));

    final displayRole = (_resolvedRole != null && _resolvedRole!.isNotEmpty)
        ? _resolvedRole!
        : (rawRole ?? 'PERSONEL');

    final displayAvatar = widget.isIncoming
        ? _currentSession.callerAvatar
        : _currentSession.receiverAvatar;

    return Dialog.fullscreen(
      backgroundColor: const Color(0xFF0F172A),
      child: SafeArea(
        child: isAccepted
            // ===== KABUL EDİLMİŞ ARAMA: WebRTC Video Layout =====
            ? Stack(
                children: [
                  // Remote Video (Tam ekran arka plan)
                  Positioned.fill(
                    child: _buildRemoteVideo(isVideo),
                  ),

                  // Üst bilgi bandı (gradient overlay ile)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFF0F172A).withOpacity(0.9),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: _buildTopInfoBar(displayName, displayRole, displayAvatar, isVideo, isAccepted),
                    ),
                  ),

                  // Local Video (PiP - sağ üst köşe, küçük)
                  if (isVideo && _localRendererInitialized)
                    Positioned(
                      top: 70,
                      right: 16,
                      child: _buildLocalVideoPip(),
                    ),

                  // Sesli aramada merkez avatar (sadece bağlantı kurulduysa göster)
                  if (!isVideo && _isMediaConnected)
                    Center(
                      child: _buildVoiceCallAvatar(displayName, displayAvatar),
                    ),

                  // Alt kontrol butonları (gradient overlay ile)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            const Color(0xFF0F172A).withOpacity(0.9),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                      child: _buildActiveCallControls(),
                    ),
                  ),
                ],
              )
            // ===== BEKLEYEN ARAMA: Stack layout (güzel UI) =====
            : Stack(
                children: [
                  // Arka plan gradient
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 1.2,
                          colors: [
                            Colors.indigo.shade900,
                            const Color(0xFF0F172A),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Üst bilgi bandı
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildTopInfoBar(displayName, displayRole, displayAvatar, isVideo, isAccepted),
                  ),
                  // Merkez: Nabız atan avatar
                  Center(
                    child: ScaleTransition(
                      scale: Tween(begin: 0.95, end: 1.05).animate(_pulseController),
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.indigo.shade800,
                          border: Border.all(color: Colors.white24, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.1),
                              blurRadius: 30,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          backgroundColor: Colors.indigo.shade900,
                          backgroundImage: (displayAvatar != null && displayAvatar.isNotEmpty)
                              ? NetworkImage(displayAvatar)
                              : null,
                          child: (displayAvatar == null || displayAvatar.isEmpty)
                              ? Text(
                                  displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                                  style: GoogleFonts.inter(
                                    fontSize: 48,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  // Alt kontrol butonları
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      child: widget.isIncoming
                          ? _buildIncomingControls()
                          : _buildOutgoingWaitControls(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ========== VIDEO WIDGETS ==========

  /// Remote video (karşı tarafın görüntüsü) — tam ekran
  Widget _buildRemoteVideo(bool isVideo) {
    // Sesli arama
    if (!isVideo) {
      // Bağlantı kurulana kadar animasyon göster
      if (!_isMediaConnected) {
        return _buildConnectingAnimation();
      }
      return Container(color: const Color(0xFF0F172A));
    }

    // Görüntülü arama — medya bağlantısı kuruldu ve remote stream var
    if (_isMediaConnected && _hasRemoteStream && _remoteRendererInitialized) {
      return RTCVideoView(
        _remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }

    // Bağlantı kuruluyor animasyonu
    return _buildConnectingAnimation();
  }

  /// Şık "Bağlantı kuruluyor" animasyonu (her iki taraf için)
  Widget _buildConnectingAnimation() {
    return Container(
      color: const Color(0xFF0F172A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing ring animasyonu
            AnimatedBuilder(
              animation: _pulseController,
              builder: (_, __) {
                return Container(
                  width: 80 + (_pulseController.value * 20),
                  height: 80 + (_pulseController.value * 20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF25D366).withOpacity(0.3 + _pulseController.value * 0.3),
                      width: 3,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF25D366).withOpacity(0.15),
                      ),
                      child: const Icon(
                        Icons.wifi_calling_3_rounded,
                        color: Color(0xFF25D366),
                        size: 28,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Bağlantı kuruluyor',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            // Animated dots
            _buildAnimatedDots(),
            const SizedBox(height: 8),
            Text(
              'Uçtan uca şifrelenmiş bağlantı',
              style: GoogleFonts.inter(
                color: Colors.white38,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "..." animasyonlu noktalar
  Widget _buildAnimatedDots() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) {
        final dotCount = (_pulseController.value * 3).floor() + 1;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < dotCount
                    ? const Color(0xFF25D366)
                    : const Color(0xFF25D366).withOpacity(0.2),
              ),
            );
          }),
        );
      },
    );
  }

  /// Local video PiP (kendi görüntümüz) — sağ üst köşe
  Widget _buildLocalVideoPip() {
    return GestureDetector(
      child: Container(
        width: 120,
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: _isCameraOff
              ? Container(
                  color: const Color(0xFF1E293B),
                  child: const Center(
                    child: Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 32),
                  ),
                )
              : (_localRendererInitialized
                  ? RTCVideoView(
                      _localRenderer,
                      mirror: true,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : Container(color: const Color(0xFF1E293B))),
        ),
      ),
    );
  }

  /// Sesli aramada büyük avatar
  Widget _buildVoiceCallAvatar(String displayName, String? displayAvatar) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.indigo.shade800,
            border: Border.all(
              color: const Color(0xFF25D366),
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF25D366).withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: CircleAvatar(
            backgroundColor: Colors.indigo.shade900,
            backgroundImage: (displayAvatar != null && displayAvatar.isNotEmpty)
                ? NetworkImage(displayAvatar)
                : null,
            child: (displayAvatar == null || displayAvatar.isEmpty)
                ? Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                    style: GoogleFonts.inter(
                      fontSize: 44,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 20),
        // Ses seviyesi animasyonu (basit dalga efekti)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (i) {
            return AnimatedBuilder(
              animation: _pulseController,
              builder: (_, __) {
                final scale = 0.3 + (_pulseController.value * 0.7 * ((i % 2 == 0) ? 1 : 0.6));
                return Container(
                  width: 4,
                  height: 20 * scale,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withOpacity(0.7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              },
            );
          }),
        ),
      ],
    );
  }

  // ========== INFO BAR ==========

  Widget _buildTopInfoBar(String displayName, String displayRole, String? displayAvatar, bool isVideo, bool isAccepted) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.indigo.shade800,
              border: Border.all(
                color: isAccepted ? const Color(0xFF25D366) : Colors.white24,
                width: 2,
              ),
            ),
            child: CircleAvatar(
              backgroundColor: Colors.indigo.shade900,
              backgroundImage: (displayAvatar != null && displayAvatar.isNotEmpty)
                  ? NetworkImage(displayAvatar)
                  : null,
              child: (displayAvatar == null || displayAvatar.isEmpty)
                  ? Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                      style: GoogleFonts.inter(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    if (displayRole.isNotEmpty) ...[
                      Text(displayRole, style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
                      const SizedBox(width: 6),
                    ],
                    if (isVideo)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.videocam_rounded, color: Color(0xFF25D366), size: 13),
                      ),
                    Text(
                      _getStatusText(),
                      style: GoogleFonts.inter(
                        color: isAccepted ? const Color(0xFF25D366) : Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // Şifreleme göstergesi (P2P güvenlik)
                    if (isAccepted) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.lock_rounded, color: Color(0xFF25D366), size: 11),
                      const SizedBox(width: 2),
                      Text(
                        'P2P',
                        style: GoogleFonts.inter(color: const Color(0xFF25D366), fontSize: 10, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========== KONTROL BUTONLARI ==========

  /// Gelen Arama Butonları (Kabul Et / Reddet)
  Widget _buildIncomingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Reddet
        GestureDetector(
          onTap: () async {
            _stopRingtone();
            _stopRingbackTone();
            await _callService.rejectCall(_currentSession.id);
            await _callService.logCallMessageToChat(
              callerId: _currentSession.callerId,
              receiverId: _currentSession.receiverId,
              callType: _currentSession.callType,
              status: CallStatus.rejected,
              durationSeconds: 0,
            );
            _closeDialog();
          },
          child: Container(
            width: 70,
            height: 70,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.red, blurRadius: 20, spreadRadius: 2)],
            ),
            child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 32),
          ),
        ),

        // Kabul Et
        GestureDetector(
          onTap: () async {
            _stopRingtone();
            _stopRingbackTone();
            _isCallConnected = true;
            await _callService.acceptCall(_currentSession.id);
            if (mounted) {
              setState(() {
                _currentSession = _currentSession.copyWith(status: CallStatus.accepted);
              });
              _startCallTimer();
              // Receiver tarafı: Answer oluştur
              _initWebRtc(isCaller: false);
            }
          },
          child: Container(
            width: 70,
            height: 70,
            decoration: const BoxDecoration(
              color: Color(0xFF25D366),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0xFF25D366), blurRadius: 20, spreadRadius: 2)],
            ),
            child: const Icon(Icons.call_rounded, color: Colors.white, size: 32),
          ),
        ),
      ],
    );
  }

  /// Arayan taraf beklerken gösterilen kontroller (sadece sonlandır)
  Widget _buildOutgoingWaitControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () async {
            _stopRingtone();
            _stopRingbackTone();
            _stopWebRtc();
            await _callService.endCall(_currentSession.id);
            await _callService.logCallMessageToChat(
              callerId: _currentSession.callerId,
              receiverId: _currentSession.receiverId,
              callType: _currentSession.callType,
              status: CallStatus.ended,
              durationSeconds: 0,
            );
            _closeDialog();
          },
          child: Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.red, blurRadius: 20, spreadRadius: 2)],
            ),
            child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Aramayı Sonlandır',
          style: GoogleFonts.inter(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// Aktif arama kontrolleri (Mute, Camera, Hangup)
  Widget _buildActiveCallControls() {
    final isVideo = _currentSession.callType == CallType.video;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Mikrofon Mute/Unmute
        _buildControlButton(
          icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: _isMuted ? 'Aç' : 'Sustur',
          backgroundColor: _isMuted ? Colors.white : Colors.white.withOpacity(0.2),
          iconColor: _isMuted ? const Color(0xFF0F172A) : Colors.white,
          onTap: () {
            if (_webRtcService != null) {
              setState(() {
                _isMuted = _webRtcService!.toggleMute();
              });
            }
          },
        ),

        // Kamera Aç/Kapa (sadece görüntülü aramada)
        if (isVideo)
          _buildControlButton(
            icon: _isCameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
            label: _isCameraOff ? 'Kamera Aç' : 'Kamera Kapa',
            backgroundColor: _isCameraOff ? Colors.white : Colors.white.withOpacity(0.2),
            iconColor: _isCameraOff ? const Color(0xFF0F172A) : Colors.white,
            onTap: () {
              if (_webRtcService != null) {
                setState(() {
                  _isCameraOff = _webRtcService!.toggleCamera();
                });
              }
            },
          ),

        // Aramayı Sonlandır
        _buildControlButton(
          icon: Icons.call_end_rounded,
          label: 'Bitir',
          backgroundColor: Colors.red,
          iconColor: Colors.white,
          size: 64,
          onTap: () async {
            _stopRingtone();
            _stopRingbackTone();
            _stopWebRtc();
            await _callService.endCall(_currentSession.id);
            await _callService.logCallMessageToChat(
              callerId: _currentSession.callerId,
              receiverId: _currentSession.receiverId,
              callType: _currentSession.callType,
              status: (_isCallConnected || _currentSession.status == CallStatus.accepted)
                  ? CallStatus.accepted
                  : CallStatus.ended,
              durationSeconds: _callSeconds,
            );
            _closeDialog();
          },
        ),
      ],
    );
  }

  /// Tek bir kontrol butonu widget'ı
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color iconColor,
    required VoidCallback onTap,
    double size = 52,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: backgroundColor.withOpacity(0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: size * 0.45),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
