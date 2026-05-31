import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../models/assessment/external_exam_model.dart';
import '../../../../models/assessment/external_exam_message_model.dart';
import '../../../../services/external_exam_messaging_service.dart';

class ExternalExamMessagingScreen extends StatefulWidget {
  final ExternalExam exam;
  final String institutionId;

  const ExternalExamMessagingScreen({
    Key? key,
    required this.exam,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<ExternalExamMessagingScreen> createState() =>
      _ExternalExamMessagingScreenState();
}

class _ExternalExamMessagingScreenState
    extends State<ExternalExamMessagingScreen>
    with SingleTickerProviderStateMixin {
  final ExternalExamMessagingService _messagingService =
      ExternalExamMessagingService();
  late TabController _innerTabController;

  // Form state
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  MessageType _messageType = MessageType.duyuru;
  MessageChannel _channel = MessageChannel.both;
  final Set<String> _targetGrades = {};
  final Set<String> _targetSessions = {};
  bool _onlyScanned = false;
  bool _isSending = false;
  Map<String, int>? _previewCounts;

  static const _primaryColor = Color(0xFFF57C00);

  @override
  void initState() {
    super.initState();
    _innerTabController = TabController(length: 2, vsync: this);
    _innerTabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _innerTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Inner tab bar
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _innerTabController,
            indicatorColor: _primaryColor,
            labelColor: _primaryColor,
            unselectedLabelColor: Colors.grey.shade500,
            labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold),
            tabs: const [
              Tab(text: 'Mesaj Gönder'),
              Tab(text: 'Mesaj Geçmişi'),
            ],
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _innerTabController,
            children: [
              _buildSendTab(),
              _buildHistoryTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSendTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Channel selector
              Text('Gönderim Kanalı', style: _labelStyle()),
              const SizedBox(height: 12),
              Row(
                children: MessageChannel.values.map((c) {
                  final (icon, name) = c == MessageChannel.email
                      ? (Icons.email_rounded, 'E-posta')
                      : c == MessageChannel.sms
                          ? (Icons.sms_rounded, 'SMS')
                          : (Icons.message_rounded, 'Her İkisi');
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        onTap: () => setState(() {
                          _channel = c;
                          _updatePreview();
                        }),
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _channel == c
                                ? Colors.orange.shade50
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _channel == c
                                  ? _primaryColor
                                  : Colors.grey.shade200,
                              width: _channel == c ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(icon,
                                  color: _channel == c
                                      ? _primaryColor
                                      : Colors.grey.shade400,
                                  size: 22),
                              const SizedBox(height: 4),
                              Text(
                                name,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _channel == c
                                      ? _primaryColor
                                      : Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // Message type
              Text('Mesaj Türü', style: _labelStyle()),
              const SizedBox(height: 8),
              DropdownButtonFormField<MessageType>(
                value: _messageType,
                decoration: _inputDecoration('Seçin'),
                items: MessageType.values.map((t) {
                  final name = t == MessageType.duyuru
                      ? '📢 Duyuru'
                      : t == MessageType.guncelleme
                          ? '🔄 Güncelleme'
                          : t == MessageType.bilgilendirme
                              ? 'ℹ️ Bilgilendirme'
                              : '🔔 Hatırlatma';
                  return DropdownMenuItem(value: t, child: Text(name));
                }).toList(),
                onChanged: (v) => setState(() => _messageType = v!),
              ),

              const SizedBox(height: 20),

              // Title
              Text('Başlık', style: _labelStyle()),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                decoration: _inputDecoration('Mesaj başlığı'),
                onChanged: (_) => _updatePreview(),
              ),

              const SizedBox(height: 20),

              // Content
              Text('İçerik', style: _labelStyle()),
              const SizedBox(height: 8),
              TextField(
                controller: _contentController,
                decoration: _inputDecoration('Mesaj içeriği...'),
                maxLines: 5,
                onChanged: (_) => _updatePreview(),
              ),

              const SizedBox(height: 24),

              // Sadece Sınava Girenlere Checkbox
              CheckboxListTile(
                value: _onlyScanned,
                onChanged: (val) {
                  setState(() => _onlyScanned = val ?? false);
                  _updatePreview();
                },
                title: Text('Sadece Sınava Girenlere (Yoklaması Alınanlara) Mesaj Gönder',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: _primaryColor)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeColor: _primaryColor,
              ),

              const SizedBox(height: 16),

              // Target filters
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hedef Sınıflar', style: _labelStyle()),
                        const SizedBox(height: 4),
                        Text('Boş = Tümü',
                            style: GoogleFonts.inter(
                                fontSize: 11, color: Colors.grey.shade400)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: widget.exam.gradeLevels.map((g) {
                            final sel = _targetGrades.contains(g);
                            return GestureDetector(
                              onTap: () => setState(() {
                                if (sel) {
                                  _targetGrades.remove(g);
                                } else {
                                  _targetGrades.add(g);
                                }
                                _updatePreview();
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 100),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? _primaryColor
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$g.',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: sel
                                        ? Colors.white
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Seans', style: _labelStyle()),
                        const SizedBox(height: 4),
                        Text('Boş = Tümü',
                            style: GoogleFonts.inter(
                                fontSize: 11, color: Colors.grey.shade400)),
                        const SizedBox(height: 8),
                        ..._getAvailableSessions().map((s) {
                          final sel = _targetSessions.contains(s.id);
                          return GestureDetector(
                            onTap: () => setState(() {
                              if (sel) {
                                _targetSessions.remove(s.id);
                              } else {
                                _targetSessions.add(s.id);
                              }
                              _updatePreview();
                            }),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: sel
                                    ? Colors.green.shade50
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: sel
                                      ? Colors.green.shade400
                                      : Colors.transparent,
                                ),
                              ),
                              child: Text(
                                '${s.displayTime}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: sel
                                      ? Colors.green.shade700
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Preview count card
              if (_previewCounts != null)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.people_alt_rounded,
                          color: Colors.blue.shade600, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Toplam ${_previewCounts!['total']} alıcı',
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700),
                            ),
                            Text(
                              'E-posta: ${_previewCounts!['withEmail']} · SMS: ${_previewCounts!['withPhone']}',
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: Colors.blue.shade500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // Send button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : _sendMessage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                    _isSending ? 'Gönderiliyor...' : 'Mesajı Gönder',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    return StreamBuilder<List<ExternalExamMessage>>(
      stream: _messagingService.getMessageHistory(widget.exam.id ?? ''),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: _primaryColor));
        }

        final messages = snapshot.data ?? [];

        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mark_email_unread_rounded,
                    size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text(
                  'Henüz mesaj gönderilmedi.',
                  style: GoogleFonts.inter(color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _buildMessageHistoryCard(messages[i]),
        );
      },
    );
  }

  Widget _buildMessageHistoryCard(ExternalExamMessage msg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${msg.messageTypeEmoji} ${msg.messageTypeName}',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  msg.channelName,
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            msg.title,
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            msg.content,
            style: GoogleFonts.inter(
                fontSize: 12, color: Colors.grey.shade500),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.people_alt_rounded,
                  size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Text(
                '${msg.recipientCount} alıcı',
                style: GoogleFonts.inter(
                    fontSize: 12, color: Colors.grey.shade500),
              ),
              if (msg.emailCount > 0) ...[
                const SizedBox(width: 12),
                Icon(Icons.email_rounded,
                    size: 14, color: Colors.blue.shade400),
                const SizedBox(width: 4),
                Text('${msg.emailCount}',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: Colors.grey.shade500)),
              ],
              if (msg.smsCount > 0) ...[
                const SizedBox(width: 12),
                Icon(Icons.sms_rounded,
                    size: 14, color: Colors.green.shade400),
                const SizedBox(width: 4),
                Text('${msg.smsCount}',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: Colors.grey.shade500)),
              ],
              const Spacer(),
              Text(
                _formatDate(msg.sentAt),
                style: GoogleFonts.inter(
                    fontSize: 11, color: Colors.grey.shade400),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<ApplicationSession> _getAvailableSessions() {
    if (_targetGrades.isEmpty) return widget.exam.applicationSessions;
    return widget.exam.applicationSessions.where((s) {
      return s.gradeLevels.any((g) => _targetGrades.contains(g));
    }).toList();
  }

  void _updatePreview() async {
    if (widget.exam.id == null) return;
    try {
      final counts = await _messagingService.previewRecipientCount(
        examId: widget.exam.id!,
        gradeLevels: _targetGrades.toList(),
        sessionIds: _targetSessions.toList(),
        onlyScanned: _onlyScanned,
      );
      if (mounted) setState(() => _previewCounts = counts);
    } catch (e) {
      debugPrint('Preview güncelleme hatası: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_titleController.text.trim().isEmpty ||
        _contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen başlık ve içerik girin.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final result = await _messagingService.sendMessage(
        examId: widget.exam.id ?? '',
        institutionId: widget.institutionId,
        schoolId: widget.exam.schoolId,
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        messageType: _messageType,
        channel: _channel,
        gradeLevels: _targetGrades.toList(),
        sessionIds: _targetSessions.toList(),
        onlyScanned: _onlyScanned,
        sentBy: user?.email ?? '',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] as String),
            backgroundColor:
                (result['success'] as bool) ? Colors.green : Colors.red,
          ),
        );

        if (result['success'] as bool) {
          _titleController.clear();
          _contentController.clear();
          _innerTabController.animateTo(1);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gönderim hatası: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  TextStyle _labelStyle() => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.blueGrey.shade700,
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.blueGrey.shade300, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryColor, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
}
