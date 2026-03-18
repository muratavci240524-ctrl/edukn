import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'dart:js' as js;
import '../../../services/attendance_service.dart';
import '../../../services/user_permission_service.dart';

class TeacherQrScanScreen extends StatefulWidget {
  const TeacherQrScanScreen({super.key});

  @override
  State<TeacherQrScanScreen> createState() => _TeacherQrScanScreenState();
}

class _TeacherQrScanScreenState extends State<TeacherQrScanScreen> {
  final AttendanceService _service = AttendanceService();
  bool _isProcessing = false;
  String? _statusMessage;
  bool _success = false;
  bool _cameraInitialized = false;
  final String _viewId = 'web-scanner-view-final-v4';

  @override
  void initState() {
    super.initState();
    // Register the web video view once using the correct library for Flutter 3+
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      final video = html.VideoElement()
        ..id = 'web-scanner-video-element'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..autoplay = true
        ..muted = true
        ..setAttribute('playsinline', 'true');
      return video;
    });
  }

  void _startWebScanner() {
    try {
      js.context.callMethod('startWebScanner', [
        'web-scanner-video-element',
        (String code) {
          if (!_isProcessing && !_success) {
            _handleScan(code);
          }
        },
      ]);
    } catch (e) {
      debugPrint("JS Scanner Error: $e");
    }
  }

  Future<void> _handleScan(String code) async {
    if (_isProcessing || _success) return;
    
    debugPrint("QR Code Scanned: $code");
    
    setState(() {
      _isProcessing = true;
      _statusMessage = "İşleniyor...";
    });

    try {
      // 1. Format Check
      debugPrint("Checking QR code format...");
      if (!code.startsWith("edukn_attendance:")) {
        throw "Geçersiz QR kodu formatı.";
      }

      final parts = code.split(":");
      if (parts.length != 3) throw "Hatalı QR kodu yapısı.";

      final qrInstId = parts[1];
      final qrTs = int.tryParse(parts[2]) ?? 0;
      final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      if ((nowTs - qrTs).abs() > 600) { // 10 minute window for sync issues
        throw "QR kodunun süresi dolmuş. Lütfen ekranı yenileyin.";
      }

      // 2. User/Permission Check
      debugPrint("Checking user data...");
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw "Oturum açık değil.";

      final userData = await UserPermissionService.loadUserData();
      final myInstId = (userData?['institutionId'] ?? "").toString().toUpperCase();

      debugPrint("QR InstId: $qrInstId, My InstId: $myInstId");

      if (qrInstId != myInstId) {
        throw "Bu QR kodu kurumunuza ait değil.\n(QR: $qrInstId, Siz: $myInstId)";
      }

      final userId = userData?['id'] ?? user.uid;
      
      // 3. Database Operation
      debugPrint("Fetching active session for user: $userId");
      final activeSession = await _service.getLastActiveSession(userId, myInstId);

      if (activeSession == null) {
        debugPrint("No active session. Performing Check-In...");
        await _service.checkIn(userId, myInstId);
        if (mounted) {
          setState(() {
            _success = true;
            _statusMessage = "GİRİŞ BAŞARILI!\nHoş geldiniz.";
          });
        }
      } else {
        debugPrint("Active session found. Performing Check-Out...");
        await _service.checkOut(userId, myInstId, docId: activeSession['id']);
        if (mounted) {
          setState(() {
            _success = true;
            _statusMessage = "ÇIKIŞ BAŞARILI!\nİyi çalışmalar.";
          });
        }
      }
    } catch (e) {
      debugPrint("Scan Handle Error: $e");
      if (mounted) {
        setState(() {
          _success = false;
          _statusMessage = "Hata oluştu:\n$e";
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'QR TARAMA SİSTEMİ v3.14 (FIX)',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.orange,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (!_success && _statusMessage == null)
            _cameraInitialized
                ? HtmlElementView(viewType: _viewId)
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.orange,
                            size: 80,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Kamera İzni Bekleniyor',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton.icon(
                          onPressed: () async {
                            setState(() => _cameraInitialized = true);
                            Future.delayed(
                              const Duration(milliseconds: 500),
                              () {
                                _startWebScanner();
                              },
                            );
                          },
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('KAMERAYI BAŞLAT'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

          if (_cameraInitialized && !_success && _statusMessage == null)
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withOpacity(0.5),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Container(
                        width: 30,
                        height: 2,
                        color: Colors.orange,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Container(
                        width: 2,
                        height: 30,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_statusMessage != null)
            Container(
              color: Colors.black.withOpacity(0.9),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _success ? Icons.check_circle : Icons.error,
                      color: _success ? Colors.green : Colors.red,
                      size: 80,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _statusMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 40),
                    if (!_isProcessing)
                      ElevatedButton(
                        onPressed: () {
                          if (_success) {
                            Navigator.pop(context);
                          } else {
                            setState(() {
                              _statusMessage = null;
                              _success = false;
                            });
                          }
                        },
                        child: Text(_success ? 'Tamam' : 'Tekrar Dene'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
