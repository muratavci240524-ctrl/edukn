import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../../widgets/edukn_app_bar.dart';
import '../../../../models/school/noise_meter_model.dart';
import '../../../../utils/fullscreen_helper.dart';

class NoiseMeterHubScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;

  const NoiseMeterHubScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
  });

  @override
  State<NoiseMeterHubScreen> createState() => _NoiseMeterHubScreenState();
}

class _NoiseMeterHubScreenState extends State<NoiseMeterHubScreen>
    with TickerProviderStateMixin {
  // ─── Mikrofon & Ses Stream Yönetimi ──────────────────────────────────────
  late final AudioRecorder _audioRecorder;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  StreamSubscription<List<int>>? _recordStreamSubscription;
  Timer? _pollingTimer;
  bool _isListening = false;
  bool _isSimulationMode = false;
  String? _errorMessage;

  // ─── Desibel (dB) ve Akış Değerleri ──────────────────────────────────────
  double _smoothDb = 35.0; // Yumuşatılmış akıcı dB
  double _maxDb = 35.0; // Oturum boyu tepe dB
  double _thresholdDb = 55.0; // Seçili kırmızı eşik değeri (dB)
  NoisePresetType _selectedPreset = NoisePresetType.study;

  // ─── Sessizlik Sayacı (Gamification) ─────────────────────────────────────
  int _silenceSeconds = 0;
  Timer? _silenceTimer;
  int _redZoneDurationMs = 0; // Kırmızıda geçirilen süre (tolerans için)
  int _earnedStars = 0;
  int _earnedTrophies = 0;

  // ─── Sesli Uyarı & Tam Ekran ─────────────────────────────────────────────
  bool _soundAlertEnabled = true;
  bool _isFullscreen = false;
  final AudioPlayer _alertPlayer = AudioPlayer();
  DateTime? _lastAlertSoundTime;
  Uint8List? _cachedAlertWav;

  // ─── Animasyon Kontrolcüleri ─────────────────────────────────────────────
  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Başlangıçta izin kontrolü yap
    _checkPermission();
  }

  @override
  void dispose() {
    _stopListening();
    _audioRecorder.dispose();
    _alertPlayer.dispose();
    _silenceTimer?.cancel();
    _pollingTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // SESLİ UYARI (WAV SENTEZLEYİCİ - TÜM PLATFORMLARDA VE WEB'DE ÇALIŞIR)
  // ===========================================================================
  Uint8List _generateAlertWav({double freq1 = 660.0, double freq2 = 880.0, double durationSeconds = 0.38}) {
    const int sampleRate = 44100;
    final int totalSamples = (sampleRate * durationSeconds).toInt();
    final int byteRate = sampleRate * 2;
    final int dataSize = totalSamples * 2;
    final int fileSize = 36 + dataSize;

    final ByteData byteData = ByteData(44 + dataSize);
    // RIFF
    byteData.setUint8(0, 0x52);
    byteData.setUint8(1, 0x49);
    byteData.setUint8(2, 0x46);
    byteData.setUint8(3, 0x46);
    byteData.setUint32(4, fileSize, Endian.little);
    byteData.setUint8(8, 0x57);
    byteData.setUint8(9, 0x41);
    byteData.setUint8(10, 0x56);
    byteData.setUint8(11, 0x45);
    // fmt
    byteData.setUint8(12, 0x66);
    byteData.setUint8(13, 0x6D);
    byteData.setUint8(14, 0x74);
    byteData.setUint8(15, 0x20);
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little); // PCM
    byteData.setUint16(22, 1, Endian.little); // Mono
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, byteRate, Endian.little);
    byteData.setUint16(32, 2, Endian.little);
    byteData.setUint16(34, 16, Endian.little);
    // data
    byteData.setUint8(36, 0x64);
    byteData.setUint8(37, 0x61);
    byteData.setUint8(38, 0x74);
    byteData.setUint8(39, 0x61);
    byteData.setUint32(40, dataSize, Endian.little);

    int offset = 44;
    final int halfSamples = totalSamples ~/ 2;
    for (int i = 0; i < totalSamples; i++) {
      final double t = i / sampleRate;
      final double currentFreq = (i < halfSamples) ? freq1 : freq2;
      final double decay = (1.0 - (i / totalSamples)).clamp(0.0, 1.0);
      final double sampleValue = math.sin(2.0 * math.pi * currentFreq * t) * 0.7 * decay;
      final int sampleInt16 = (sampleValue * 32767).toInt().clamp(-32768, 32767);
      byteData.setInt16(offset, sampleInt16, Endian.little);
      offset += 2;
    }

    return byteData.buffer.asUint8List();
  }

  Future<void> _playAlertSound({bool force = false}) async {
    if (!_soundAlertEnabled && !force) return;

    final now = DateTime.now();
    if (!force && _lastAlertSoundTime != null && now.difference(_lastAlertSoundTime!).inMilliseconds < 2200) {
      return; // 2.2 saniyelik ses tekrarı engelleme (cooldown)
    }
    _lastAlertSoundTime = now;

    try {
      _cachedAlertWav ??= _generateAlertWav();
      await _alertPlayer.stop();
      await _alertPlayer.play(BytesSource(_cachedAlertWav!));
    } catch (e) {
      debugPrint('Alert sound error: $e');
    }
  }

  // ===========================================================================
  // MİKROFON İZİN VE DİNLEME SERVİSİ
  // ===========================================================================
  Future<bool> _checkPermission() async {
    try {
      final hasPerm = await _audioRecorder.hasPermission();
      if (mounted && !hasPerm) {
        setState(() {
          _errorMessage = 'Mikrofon izni bekleniyor. Başlat butonuna basarak tarayıcı/cihaz iznini onaylayabilirsiniz.';
        });
      }
      return hasPerm;
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Mikrofon durumu kontrol edilemedi: $e';
        });
      }
      return false;
    }
  }

  Future<void> _startListening() async {
    if (_isSimulationMode) {
      _startSimulation();
      return;
    }

    try {
      final hasPerm = await _audioRecorder.hasPermission();
      if (!hasPerm) {
        if (mounted) {
          setState(() {
            _isListening = false;
            _errorMessage = 'Mikrofon erişim izni verilmedi. Lütfen tarayıcı ayarlarından mikrofona izin verin veya Simülasyon Modunu açın.';
          });
        }
        return;
      }

      // Varsa önceki kaydı durdur ve temizle
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.stop();
      }

      // Web ve mobilde ses donanımının anlık sinyal üretmesi için ses akışını (stream) başlatıyoruz
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
      );

      final stream = await _audioRecorder.startStream(config);
      _recordStreamSubscription?.cancel();
      _recordStreamSubscription = stream.listen((_) {});

      // 1. Birincil Dinleyici: Amplitude Stream (onAmplitudeChanged)
      _amplitudeSubscription?.cancel();
      _amplitudeSubscription = _audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 60))
          .listen((amp) {
        _processAmplitude(amp.current);
      });

      // 2. Yedek Dinleyici: Polling Timer (bazı tarayıcılarda getAmplitude güvencesi)
      _pollingTimer?.cancel();
      _pollingTimer = Timer.periodic(const Duration(milliseconds: 80), (_) async {
        if (!_isListening) return;
        try {
          final amp = await _audioRecorder.getAmplitude();
          _processAmplitude(amp.current);
        } catch (_) {}
      });

      if (mounted) {
        setState(() {
          _isListening = true;
          _errorMessage = null;
        });
      }

      // Sessizlik sayacını başlat
      _startSilenceTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _errorMessage = 'Mikrofon başlatılırken bir hata oluştu: $e. Simülasyon modunu deneyebilirsiniz.';
        });
      }
    }
  }

  Future<void> _stopListening() async {
    _pollingTimer?.cancel();
    _silenceTimer?.cancel();
    _amplitudeSubscription?.cancel();
    _recordStreamSubscription?.cancel();

    try {
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.stop();
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }
  }

  void _toggleListening() {
    HapticFeedback.lightImpact();
    if (_isListening) {
      _stopListening();
    } else {
      _startListening();
    }
  }

  // ===========================================================================
  // SİMÜLASYON MODU (TEST & MİKROFONSUZ ORTAMLAR)
  // ===========================================================================
  void _startSimulation() {
    setState(() {
      _isListening = true;
      _errorMessage = null;
    });

    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (!_isListening) return;
      final rnd = math.Random().nextDouble();
      double simDb = 38.0 + (rnd * 18.0);
      if (rnd > 0.90) simDb += 28.0; // Anlık ses sıçramaları

      _updateDbValue(simDb);
    });

    _startSilenceTimer();
  }

  // ===========================================================================
  // DESİBEL HESAPLAMA VE YUMUŞATMA
  // ===========================================================================
  void _processAmplitude(double dbfs) {
    // dBFS değeri -160.0 ile 0.0 arasındadır.
    // -60 dBFS sessiz oda (~38 dB SPL), -10 dBFS yüksek ses (~85 dB SPL)
    double calculatedDb = 30.0;
    if (dbfs > -150.0 && dbfs <= 0.0) {
      calculatedDb = (dbfs + 95.0).clamp(30.0, 105.0);
    }

    _updateDbValue(calculatedDb);
  }

  void _updateDbValue(double newDb) {
    if (!mounted) return;

    setState(() {
      // Exponential moving average: ani sıçramaları yumuşatır, pürüzsüz görsel sağlar
      _smoothDb = (_smoothDb * 0.7) + (newDb * 0.3);

      if (_smoothDb > _maxDb) {
        _maxDb = _smoothDb;
      }
    });

    // Kırmızı bölge kontrolü
    if (_smoothDb >= _thresholdDb) {
      _redZoneDurationMs += 70;
      if (_redZoneDurationMs >= 750) {
        // Belirli bir süre gürültü sürdüyse sayacı sıfırla ve uyar
        _onNoiseLimitBreached();
      }
    } else {
      _redZoneDurationMs = 0;
    }
  }

  void _onNoiseLimitBreached() {
    _shakeController.forward(from: 0.0);
    HapticFeedback.heavyImpact();

    // Sesli uyarı ver
    _playAlertSound();

    // Sessizlik sayacını sıfırla
    if (_silenceSeconds > 0) {
      setState(() {
        _silenceSeconds = 0;
      });
    }
  }

  // ===========================================================================
  // SESSİZLİK SAYACI & OYUNLAŞTIRMA (GAMIFICATION)
  // ===========================================================================
  void _startSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isListening) return;

      if (_smoothDb < _thresholdDb) {
        setState(() {
          _silenceSeconds++;
        });
        _checkMilestones(_silenceSeconds);
      }
    });
  }

  void _checkMilestones(int seconds) {
    for (final milestone in SilenceRewardMilestone.defaultMilestones) {
      if (seconds == milestone.targetSeconds) {
        _onMilestoneReached(milestone);
        break;
      }
    }
  }

  void _onMilestoneReached(SilenceRewardMilestone milestone) {
    HapticFeedback.mediumImpact();
    setState(() {
      if (milestone.targetSeconds >= 300) {
        _earnedTrophies++;
      } else {
        _earnedStars++;
      }
    });

    // Kutlama bildirimi
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        backgroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: milestone.glowColor, width: 2),
        ),
        content: Row(
          children: [
            Text(milestone.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    milestone.title,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 14.5, color: const Color(0xFF1E293B)),
                  ),
                  Text(
                    'Kazanılan Ödül: ${milestone.rewardName}',
                    style: GoogleFonts.inter(fontSize: 12.5, color: milestone.glowColor, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ===========================================================================
  // HASSASİYET MODU SEÇİMİ
  // ===========================================================================
  void _selectPreset(NoiseSensitivityPreset preset) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedPreset = preset.type;
      _thresholdDb = preset.thresholdDb;
    });
  }

  void _toggleFullscreen() {
    final nextState = !_isFullscreen;
    toggleBrowserFullscreen(nextState);

    if (!kIsWeb) {
      try {
        if (nextState) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        } else {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
      } catch (_) {}
    }

    setState(() {
      _isFullscreen = nextState;
    });
  }

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.shield_rounded, color: Color(0xFF10B981), size: 24),
            ),
            const SizedBox(width: 12),
            Text(
              'Gizlilik & Güvenlik Garantisi',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '• Sınıf Termometresi mikrofon sesini ASLA kaydetmez veya depolamaz.',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569), height: 1.45),
            ),
            const SizedBox(height: 10),
            Text(
              '• Ses verisi hiçbir harici sunucuya veya buluta iletilmez.',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569), height: 1.45),
            ),
            const SizedBox(height: 10),
            Text(
              '• Yalnızca anlık desibel (şiddet) seviyesi cihaz üzerinde anlık hesaplanır ve hemen bellekten silinir.',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569), height: 1.45),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: Text('Anladım', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ARAYÜZ (BEYAZ / LIGHT TEMA)
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;

    // Ses Durumuna Göre Renk ve Karakter Belirleme
    final ratio = _smoothDb / _thresholdDb;
    final isRed = ratio >= 1.0;
    final isYellow = ratio >= 0.75 && !isRed;

    final stateColor = isRed
        ? const Color(0xFFEF4444)
        : (isYellow ? const Color(0xFFF59E0B) : const Color(0xFF10B981));

    final statusText = isRed
        ? 'GÜRÜLTÜ SINIRI AŞILDI!'
        : (isYellow ? 'DİKKAT: SES YÜKSELİYOR' : 'SINIF SAKİN VE SESSİZ');

    final statusEmoji = isRed ? '🤫' : (isYellow ? '🤔' : '😊');

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Ferah Aydınlık Arka Plan
      appBar: EduknAppBar(
        title: _isFullscreen ? 'Sınıf Termometresi (Tam Ekran)' : 'Sınıf Termometresi',
        subtitle: '${widget.schoolTypeName} • Anlık Gürültü Ölçer & Sessizlik Sayacı',
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        subtitleColor: const Color(0xFF64748B),
        backButtonColor: const Color(0xFF4F46E5),
        borderColor: const Color(0xFFE2E8F0),
        actions: [
          // Gizlilik Bilgi Butonu
          IconButton(
            tooltip: 'Gizlilik ve Güvenlik Bilgisi',
            icon: const Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 22),
            onPressed: _showPrivacyDialog,
          ),
          // Tam Ekran Butonu
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            decoration: BoxDecoration(
              color: _isFullscreen ? const Color(0xFF4F46E5) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _isFullscreen ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                width: 1.2,
              ),
            ),
            child: IconButton(
              tooltip: _isFullscreen ? 'Tam Ekrandan Çık (F11)' : 'Tarayıcı Tam Ekranı (F11)',
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
              icon: Icon(
                _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                color: _isFullscreen ? Colors.white : const Color(0xFF4F46E5),
                size: 22,
              ),
              onPressed: _toggleFullscreen,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // 1. Üst Bar: Sessizlik Kronometresi & Kazanılan Yıldızlar
              _buildGamificationBar(isMobile),
              const SizedBox(height: 18),

              // 2. Ana Gösterge: Termometre / Büyük Dairesel Desibel Göstergesi & Emoji
              _buildMainVisualGauge(stateColor, statusText, statusEmoji, isMobile),
              const SizedBox(height: 20),

              // 3. Alt Kontroller: Hassasiyet Modları, Eşik Slider'ı ve Ayarlar
              _buildControlsAndSensitivityCard(isMobile),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      // En Alta Sabitlenmiş Dinleme Butonu
      bottomNavigationBar: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 24,
          vertical: isMobile ? 12 : 14,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1.2)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF64748B).withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isListening ? const Color(0xFFEF4444) : const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _toggleListening,
              icon: Icon(_isListening ? Icons.stop_rounded : Icons.mic_rounded, size: 24),
              label: Text(
                _isListening ? 'ÖLÇÜMÜ DURDUR' : 'DİNLEMEYİ BAŞLAT',
                style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.8),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 1. OYUNLAŞTIRILMIŞ SESSİZLİK SAYACI ÇUBUĞU (BEYAZ KART)
  // ===========================================================================
  Widget _buildGamificationBar(bool isMobile) {
    final minutes = (_silenceSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_silenceSeconds % 60).toString().padLeft(2, '0');

    if (isMobile) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF64748B).withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Sayaç Rozeti
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFC7D2FE), width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_rounded, color: Color(0xFF4F46E5), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '$minutes:$seconds',
                        style: GoogleFonts.robotoMono(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: const Color(0xFF312E81),
                        ),
                      ),
                    ],
                  ),
                ),
                // Yıldız & Kupa Rozetleri
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        children: [
                          const Text('⭐', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Text(
                            '$_earnedStars',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: const Color(0xFFD97706), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEFCE8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFEF08A)),
                      ),
                      child: Row(
                        children: [
                          const Text('🏆', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Text(
                            '$_earnedTrophies',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: const Color(0xFFCA8A04), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 13, color: Color(0xFF64748B)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Sessizlik Süresi (Gürültü eşiğinde sıfırlanır)',
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64748B).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Sessizlik Kronometresi Rozeti
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFC7D2FE), width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_rounded, color: Color(0xFF4F46E5), size: 18),
                const SizedBox(width: 6),
                Text(
                  '$minutes:$seconds',
                  style: GoogleFonts.robotoMono(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: const Color(0xFF312E81),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Başlık ve Açıklama
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Kesintisiz Sessizlik Süresi',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13, color: const Color(0xFF1E293B)),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Gürültü eşiği aşılmadıkça sayaç artar',
                  style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Kazanılan Yıldızlar ve Kupalar
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Text('⭐', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 4),
                    Text(
                      '$_earnedStars',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: const Color(0xFFD97706), fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEFCE8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFEF08A)),
                ),
                child: Row(
                  children: [
                    const Text('🏆', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 4),
                    Text(
                      '$_earnedTrophies',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: const Color(0xFFCA8A04), fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. ANA GÖRSEL TERMOMETRE / DESİBEL KADRANI (BEYAZ KART)
  // ===========================================================================
  Widget _buildMainVisualGauge(Color stateColor, String statusText, String statusEmoji, bool isMobile) {
    final gaugeSize = isMobile ? 220.0 : 290.0;
    final progress = (_smoothDb / 100.0).clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        final shakeOffset = math.sin(_shakeController.value * math.pi * 4) * 8;
        return Transform.translate(
          offset: Offset(shakeOffset, 0),
          child: child,
        );
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 20, vertical: isMobile ? 20 : 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: stateColor.withValues(alpha: 0.5), width: 2),
          boxShadow: [
            BoxShadow(
              color: stateColor.withValues(alpha: 0.18),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Durum Rozeti ve Emoji (Responsive)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 18, vertical: 8),
              decoration: BoxDecoration(
                color: stateColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: stateColor.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(statusEmoji, style: TextStyle(fontSize: isMobile ? 20 : 24)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      statusText,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w900,
                        fontSize: isMobile ? 12 : 15,
                        color: stateColor,
                        letterSpacing: 0.6,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Büyük Dairesel Kadran
            Stack(
              alignment: Alignment.center,
              children: [
                // Arka Plan Halkası
                SizedBox(
                  width: gaugeSize,
                  height: gaugeSize,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: isMobile ? 14 : 20,
                    backgroundColor: const Color(0xFFF1F5F9),
                    valueColor: AlwaysStoppedAnimation<Color>(stateColor),
                  ),
                ),

                // İç Bilgi: Desibel ve Eşik Değeri
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_smoothDb.toStringAsFixed(0)} dB',
                      style: GoogleFonts.robotoMono(
                        fontWeight: FontWeight.w900,
                        fontSize: isMobile ? 48 : 68,
                        color: const Color(0xFF0F172A),
                        letterSpacing: 2,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.flag_rounded, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(
                          'Sınır: ${_thresholdDb.toInt()} dB',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 12.5 : 13.5,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Max: ${_maxDb.toStringAsFixed(0)} dB',
                      style: GoogleFonts.inter(fontSize: isMobile ? 11 : 12, color: const Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Dinamik Canlı Seviye Çubuğu (Trafik Lambası Skalası)
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    height: 10,
                    child: Stack(
                      children: [
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFF10B981), // Yeşil
                                Color(0xFFF59E0B), // Sarı
                                Color(0xFFEF4444), // Kırmızı
                              ],
                            ),
                          ),
                        ),
                        // Eşik Çizgisi
                        Align(
                          alignment: Alignment((_thresholdDb / 50.0) - 1.0, 0),
                          child: Container(
                            width: 3,
                            height: 10,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(isMobile ? '30 dB' : '30 dB (Sessiz)', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8))),
                    Text('Eşik: ${_thresholdDb.toInt()} dB', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                    Text(isMobile ? '100+ dB' : '100+ dB (Gürültülü)', style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8))),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 3. KONTROLLER & HASSASİYET SENARYOLARI (BEYAZ KART)
  // ===========================================================================
  Widget _buildControlsAndSensitivityCard(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64748B).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hata veya İzin Uyarısı
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFFEF4444), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF991B1B)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Hassasiyet Senaryoları Başlığı
          Text(
            'Etkinlik Hassasiyet Modları',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 10),

          // Preset Butonları (Tam Genişlikte Dikey Liste)
          Column(
            children: NoiseSensitivityPreset.presets.map((preset) {
              final isSelected = _selectedPreset == preset.type;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => _selectPreset(preset),
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? preset.color : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? preset.color : const Color(0xFFE2E8F0),
                        width: 1.2,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: preset.color.withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.2)
                                : preset.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            preset.icon,
                            size: 18,
                            color: isSelected ? Colors.white : preset.color,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            preset.title,
                            style: GoogleFonts.inter(
                              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                              fontSize: 13.5,
                              color: isSelected ? Colors.white : const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.25)
                                : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${preset.thresholdDb.toInt()} dB',
                            style: GoogleFonts.robotoMono(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: isSelected ? Colors.white : const Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Manuel Eşik Değeri Ayarlayıcı (Slider)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Özel Kırmızı Eşik Değeri',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12.5, color: const Color(0xFF64748B)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_thresholdDb.toInt()} dB',
                        style: GoogleFonts.robotoMono(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFFEF4444),
                    inactiveTrackColor: const Color(0xFFE2E8F0),
                    thumbColor: const Color(0xFFEF4444),
                    overlayColor: const Color(0xFFEF4444).withValues(alpha: 0.15),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                  ),
                  child: Slider(
                    value: _thresholdDb,
                    min: 35.0,
                    max: 95.0,
                    divisions: 60,
                    onChanged: (val) {
                      setState(() {
                        _thresholdDb = val;
                        _selectedPreset = NoisePresetType.custom;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 1. Simülasyon Modu Switch'i
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.science_outlined,
                      color: _isSimulationMode ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Simülasyon Modu',
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isSimulationMode,
                activeTrackColor: const Color(0xFF4F46E5),
                onChanged: (val) {
                  setState(() => _isSimulationMode = val);
                  if (_isListening) {
                    _stopListening();
                    _startListening();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 2. Sesli Uyarı ve Test Butonu (Responsive)
          isMobile
              ? Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                _soundAlertEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                                color: _soundAlertEnabled ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Sınır Aşılınca Sesli Uyarı Ver',
                                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _soundAlertEnabled,
                          activeTrackColor: const Color(0xFF10B981),
                          onChanged: (val) => setState(() => _soundAlertEnabled = val),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          foregroundColor: const Color(0xFF4F46E5),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _playAlertSound(force: true),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: Text(
                          'Sesi Test Et (Hoparlörü Dene)',
                          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            _soundAlertEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                            color: _soundAlertEnabled ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Sınır Aşılınca Sesli Uyarı Ver',
                              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            backgroundColor: const Color(0xFFF1F5F9),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _playAlertSound(force: true),
                          icon: const Icon(Icons.play_arrow_rounded, size: 16, color: Color(0xFF4F46E5)),
                          label: Text(
                            'Sesi Test Et',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF4F46E5)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          value: _soundAlertEnabled,
                          activeTrackColor: const Color(0xFF10B981),
                          onChanged: (val) => setState(() => _soundAlertEnabled = val),
                        ),
                      ],
                    ),
                  ],
                ),
        ],
      ),
    );
  }
}
