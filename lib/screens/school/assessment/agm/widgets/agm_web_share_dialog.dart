import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:printing/printing.dart';

class AgmWebShareDialog extends StatefulWidget {
  final Uint8List pdfBytes;
  final String fileName;
  final String targetUserId;
  final String title;
  final String messageBody;

  const AgmWebShareDialog({
    Key? key,
    required this.pdfBytes,
    required this.fileName,
    required this.targetUserId,
    required this.title,
    required this.messageBody,
  }) : super(key: key);

  @override
  State<AgmWebShareDialog> createState() => _AgmWebShareDialogState();
}

class _AgmWebShareDialogState extends State<AgmWebShareDialog> {
  bool _isLoadingContact = true;
  String? _phone;
  String? _email;
  String? _contactError;

  @override
  void initState() {
    super.initState();
    _fetchContactInfo();
  }

  Future<void> _fetchContactInfo() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.targetUserId)
          .get();

      if (!doc.exists || doc.data() == null) {
        setState(() {
          _contactError = 'İletişim bilgisi bulunamadı.';
          _isLoadingContact = false;
        });
        return;
      }

      final data = doc.data()!;
      String? foundPhone;
      for (final key in [
        'mobilePhone',
        'phone',
        'phoneNumber',
        'cepTelefonu',
        'telefon',
        'veliTelefon',
        'veliTelefonu',
        'anneTelefon',
        'babaTelefon',
      ]) {
        if (data[key] != null && data[key].toString().trim().isNotEmpty) {
          foundPhone = data[key].toString().trim();
          break;
        }
      }

      String? foundEmail;
      for (final key in [
        'corporateEmail',
        'personalEmail',
        'email',
        'kurumsalEmail',
        'kisiselEmail',
        'eposta',
        'veliEmail',
        'studentEmail',
      ]) {
        if (data[key] != null && data[key].toString().trim().isNotEmpty) {
          foundEmail = data[key].toString().trim();
          break;
        }
      }

      setState(() {
        _phone = foundPhone;
        _email = foundEmail;
        _isLoadingContact = false;
        if (_phone == null && _email == null) {
          _contactError = 'Kayıtlı Telefon veya E-Posta bulunamadı.';
        }
      });
    } catch (e) {
      setState(() {
        _contactError = 'Bilgiler alınırken hata oluştu.';
        _isLoadingContact = false;
      });
    }
  }

  Future<void> _shareViaWhatsApp() async {
    if (_phone == null) return;

    var formattedPhone = _phone!.replaceAll(RegExp(r'\D'), '');
    if (!formattedPhone.startsWith('90')) {
      formattedPhone = '90$formattedPhone';
    }

    final text = Uri.encodeComponent(
      '${widget.messageBody}\n\n*Dosya Cihazıma İndirildi, Lütfen Eke Ekleyin.*',
    );
    final launchUri = Uri.parse('https://wa.me/$formattedPhone?text=$text');

    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri, mode: LaunchMode.externalApplication);
    }

    // PDF'i indir (WhatsApp web üzerinden dosya atılamadığı için kullanıcının manuel yüklemesi gerekir)
    await _downloadPdf();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _shareViaEmail() async {
    if (_email == null) return;

    final subject = Uri.encodeComponent(widget.title);
    final body = Uri.encodeComponent(
      '${widget.messageBody}\n\nNOT: Lütfen indirilen PDF dosyasını bu maile eklemeyi unutmayın.',
    );
    final launchUri = Uri.parse('mailto:$_email?subject=$subject&body=$body');

    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri, mode: LaunchMode.externalApplication);
    }

    await _downloadPdf();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _downloadPdf() async {
    await Printing.sharePdf(bytes: widget.pdfBytes, filename: widget.fileName);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 10,
      backgroundColor: Colors.transparent,
      child: Container(
        width: 450,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.deepOrange.shade400,
                    Colors.deepOrange.shade600,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.share,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                    splashRadius: 24,
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24.0),
              child: _isLoadingContact
                  ? const SizedBox(
                      height: 150,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Colors.deepOrange,
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        if (_contactError != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: Colors.red.shade400,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _contactError!,
                                    style: TextStyle(
                                      color: Colors.red.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.blue.shade700,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Whatsapp veya E-Posta Web üzerinden otomatik PDF eklemeyi desteklemediğinden, PDF cihazınıza inecektir. Lütfen açılan ekranda dosyayı manuel olarak mesaja ekleyiniz.',
                                    style: TextStyle(
                                      color: Colors.blue.shade900,
                                      fontSize: 13,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          if (_phone != null)
                            _ActionCard(
                              icon: Icons.chat,
                              title: 'WhatsApp ile Gönder',
                              subtitle: _phone!,
                              color: Colors.green,
                              onTap: _shareViaWhatsApp,
                            ),
                          if (_phone != null && _email != null)
                            const SizedBox(height: 12),
                          if (_email != null)
                            _ActionCard(
                              icon: Icons.email,
                              title: 'E-Posta ile Gönder',
                              subtitle: _email!,
                              color: Colors.blue,
                              onTap: _shareViaEmail,
                            ),
                        ],

                        const SizedBox(height: 24),
                        const Divider(),
                        TextButton.icon(
                          onPressed: () {
                            _downloadPdf();
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.file_download),
                          label: const Text('Cihazıma Sadece PDF Olarak İndir'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey.shade800,
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final MaterialColor color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.shade500,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: color.shade900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: color.shade700),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color.shade400),
          ],
        ),
      ),
    );
  }
}
