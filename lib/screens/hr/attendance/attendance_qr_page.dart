import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:async';

class AttendanceQrPage extends StatefulWidget {
  const AttendanceQrPage({super.key});

  @override
  State<AttendanceQrPage> createState() => _AttendanceQrPageState();
}

class _AttendanceQrPageState extends State<AttendanceQrPage> {
  String _qrContent = "";
  Timer? _timer;
  int _secondsLeft = 30;

  @override
  void initState() {
    super.initState();
    _generateNewQr();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 0) {
        _generateNewQr();
      } else {
        if (mounted) setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _generateNewQr() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final email = user.email ?? '';
    final domain = email.contains('@') ? email.split('@')[1] : '';
    final instId = domain.contains('.') ? domain.split('.')[0].toUpperCase() : 'UNKNOWN';

    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Format: "edukn_attendance:INSTID:TIMESTAMP"
    if (mounted) {
      setState(() {
        _qrContent = "edukn_attendance:$instId:$ts";
        _secondsLeft = 30;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final screenHeight = size.height;
    final isShortScreen = screenHeight < 700;

    return Scaffold(
      backgroundColor: const Color(0xFF1E2661), 
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: isShortScreen ? 50 : 70,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: Colors.white, size: isShortScreen ? 24 : 30),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Giriş / Çıkış Paneli',
          style: TextStyle(
            color: Colors.white, 
            fontWeight: FontWeight.bold,
            fontSize: isShortScreen ? 18 : 20,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF1E2661),
              const Color(0xFF1E2661).withOpacity(0.8),
              Colors.indigo.shade900,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                const Spacer(flex: 1),
                
                // Header Icon
                Container(
                  padding: EdgeInsets.all(isShortScreen ? 12 : 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.qr_code_scanner_rounded, 
                    color: Colors.white, 
                    size: isShortScreen ? 40 : 60
                  ),
                ),
                SizedBox(height: isShortScreen ? 12 : 24),
                Text(
                  'PERSONEL GİRİŞ / ÇIKIŞ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isShortScreen ? 20 : 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                SizedBox(height: isShortScreen ? 4 : 12),
                Text(
                  'Lütfen mobil uygulamadan kodu taratınız.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: isShortScreen ? 13 : 16,
                  ),
                ),
                
                const Spacer(flex: 2),
                
                // QR CODE
                Container(
                  padding: EdgeInsets.all(isShortScreen ? 16 : 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(isShortScreen ? 24 : 40),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyanAccent.withOpacity(0.2),
                        blurRadius: 60,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: _qrContent,
                    version: QrVersions.auto,
                    size: isShortScreen ? 180.0 : 280.0,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF1E2661)),
                    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF1E2661)),
                  ),
                ),
                
                const Spacer(flex: 2),
                
                // TIMER & STATUS
                SizedBox(
                  width: 300,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.refresh_rounded, color: Colors.cyanAccent, size: isShortScreen ? 16 : 20),
                          const SizedBox(width: 8),
                          Text(
                            'Kod $_secondsLeft saniye içinde yenilenecek',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isShortScreen ? 14 : 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: isShortScreen ? 8 : 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SizedBox(
                          height: isShortScreen ? 6 : 10,
                          child: LinearProgressIndicator(
                            value: (_secondsLeft / 30).clamp(0.0, 1.0),
                            backgroundColor: Colors.white.withOpacity(0.1),
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const Spacer(flex: 1),
                
                // Footer
                Text(
                  'eduKN Cloud Attendance System v2.0',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
