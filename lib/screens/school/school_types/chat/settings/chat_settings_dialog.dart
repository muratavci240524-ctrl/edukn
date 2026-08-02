import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ChatSettingsData {
  TimeOfDay startWorkingTime;
  TimeOfDay endWorkingTime;
  bool allowWeekendMessaging;
  bool parentCanCallTeacher;
  bool parentCanCallManager;
  bool studentCanCallTeacher;
  bool allowVoiceCalls;
  bool allowVideoCalls;

  ChatSettingsData({
    this.startWorkingTime = const TimeOfDay(hour: 8, minute: 30),
    this.endWorkingTime = const TimeOfDay(hour: 18, minute: 0),
    this.allowWeekendMessaging = false,
    this.parentCanCallTeacher = true,
    this.parentCanCallManager = true,
    this.studentCanCallTeacher = false,
    this.allowVoiceCalls = true,
    this.allowVideoCalls = true,
  });
}

// Global active settings singleton for seamless access across chat
final ChatSettingsData globalChatSettings = ChatSettingsData();

class ChatSettingsDialog extends StatefulWidget {
  const ChatSettingsDialog({Key? key}) : super(key: key);

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const ChatSettingsDialog(),
    );
  }

  @override
  State<ChatSettingsDialog> createState() => _ChatSettingsDialogState();
}

class _ChatSettingsDialogState extends State<ChatSettingsDialog> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late bool _allowWeekend;
  late bool _parentCallTeacher;
  late bool _parentCallManager;
  late bool _studentCallTeacher;
  late bool _allowVoice;
  late bool _allowVideo;

  @override
  void initState() {
    super.initState();
    _startTime = globalChatSettings.startWorkingTime;
    _endTime = globalChatSettings.endWorkingTime;
    _allowWeekend = globalChatSettings.allowWeekendMessaging;
    _parentCallTeacher = globalChatSettings.parentCanCallTeacher;
    _parentCallManager = globalChatSettings.parentCanCallManager;
    _studentCallTeacher = globalChatSettings.studentCanCallTeacher;
    _allowVoice = globalChatSettings.allowVoiceCalls;
    _allowVideo = globalChatSettings.allowVideoCalls;
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _startTime : _endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  void _saveSettings() {
    setState(() {
      globalChatSettings.startWorkingTime = _startTime;
      globalChatSettings.endWorkingTime = _endTime;
      globalChatSettings.allowWeekendMessaging = _allowWeekend;
      globalChatSettings.parentCanCallTeacher = _parentCallTeacher;
      globalChatSettings.parentCanCallManager = _parentCallManager;
      globalChatSettings.studentCanCallTeacher = _studentCallTeacher;
      globalChatSettings.allowVoiceCalls = _allowVoice;
      globalChatSettings.allowVideoCalls = _allowVideo;
    });

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚙️ Mesajlaşma ve Arama ayarları güncellendi.'),
        backgroundColor: Colors.indigo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 750),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.settings_suggest_rounded, color: Colors.indigo, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '⚙️ Mesajlaşma & Arama Ayarları',
                          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Mesai saatlerini ve arama yetkilerini dinamik yönetin',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.blueGrey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Section 1: Mesai Saatleri Ayarları
              Text(
                '⏰ Veli - Öğretmen Mesai Saati Sınırlaması',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickTime(true),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.indigo.shade200),
                        ),
                        child: Column(
                          children: [
                            const Text('Başlangıç Saati', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                            const SizedBox(height: 4),
                            Text(
                              _formatTimeOfDay(_startTime),
                              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickTime(false),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.indigo.shade200),
                        ),
                        child: Column(
                          children: [
                            const Text('Bitiş Saati', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                            const SizedBox(height: 4),
                            Text(
                              _formatTimeOfDay(_endTime),
                              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hafta Sonu İletişimine İzin Ver'),
                subtitle: const Text('Cumartesi ve Pazar günleri mesajlaşmayı açık tutar'),
                value: _allowWeekend,
                onChanged: (val) => setState(() => _allowWeekend = val),
              ),
              const Divider(height: 24),

              // Section 2: Arama İzin Kuralları
              Text(
                '📞 Arama Yetki & İzin Kuralları',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sesli Aramaya İzin Ver'),
                subtitle: const Text('Sistem genelinde sesli aramayı aktif eder'),
                value: _allowVoice,
                onChanged: (val) => setState(() => _allowVoice = val),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Görüntülü Aramaya İzin Ver'),
                subtitle: const Text('Sistem genelinde görüntülü aramayı aktif eder'),
                value: _allowVideo,
                onChanged: (val) => setState(() => _allowVideo = val),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Veli -> Öğretmeni Arayabilir'),
                subtitle: const Text('Velilerin öğretmenlere arama başlatmasına izin verir'),
                value: _parentCallTeacher,
                onChanged: (val) => setState(() => _parentCallTeacher = val),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Veli -> Yöneticileri Arayabilir'),
                subtitle: const Text('Velilerin okul müdür ve yrd. aramasını sağlar'),
                value: _parentCallManager,
                onChanged: (val) => setState(() => _parentCallManager = val),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Öğrenci -> Öğretmeni Arayabilir'),
                subtitle: const Text('Varsayılan kapalıdır. İstenirse açılabilir.'),
                value: _studentCallTeacher,
                onChanged: (val) => setState(() => _studentCallTeacher = val),
              ),
              const SizedBox(height: 20),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('İptal', style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: Text(
                      'Ayarları Kaydet',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
