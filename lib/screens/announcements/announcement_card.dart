import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
// Okul modülü altındaki survey ekranına erişim
import '../school/survey/survey_response_screen.dart';

class AnnouncementCard extends StatefulWidget {
  final DocumentSnapshot doc;
  final bool isCreator;
  final bool isRead;
  final bool isPinned;
  final bool isSurvey;
  final VoidCallback onTogglePin;
  final VoidCallback onMarkAsRead;
  final VoidCallback onTap;
  final bool canEdit;

  const AnnouncementCard({
    Key? key,
    required this.doc,
    required this.isCreator,
    required this.isRead,
    required this.isPinned,
    this.isSurvey = false,
    required this.onTogglePin,
    required this.onMarkAsRead,
    required this.onTap,
    required this.canEdit,
  }) : super(key: key);

  @override
  State<AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<AnnouncementCard> {
  bool _isExpanded = false;

  void _handleSurveyTap() {
    // Linklerden anket ID'sini bul
    final data = widget.doc.data() as Map<String, dynamic>;
    final links = data['links'] as List<dynamic>? ?? [];

    String? surveyId;
    for (var link in links) {
      String url = '';
      if (link is Map) {
        url = (link['url'] ?? '').toString();
      } else {
        url = link.toString();
      }

      if (url.startsWith('internal://survey/')) {
        // internal://survey/{id} formatından id'yi ayıkla
        // Bazen sonuna parametreler eklenebilir, basitçe split yapalım
        final parts = url.split('internal://survey/');
        if (parts.length > 1) {
          surveyId = parts[1]
              .split('?')
              .first; // Varsa query parametrelerini at
          break;
        }
      }
    }

    if (surveyId != null && surveyId.isNotEmpty) {
      if (!widget.isRead) widget.onMarkAsRead();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SurveyResponseScreen(surveyId: surveyId!),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anket bağlantısı bulunamadı.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data() as Map<String, dynamic>;
    final title = data['title'] ?? 'Başlıksız';
    final content = data['content'] ?? '';
    final publishDate = data['publishDate'] as Timestamp?;
    final isReminder = data['isReminder'] ?? false;

    // Tarih formatı
    String dateStr = '';
    if (publishDate != null) {
      final date = publishDate.toDate();
      dateStr = DateFormat('d MMMM yyyy HH:mm', 'tr_TR').format(date);
    }

    // Icon Configuration
    IconData iconData = Icons.campaign_outlined;
    Color iconColor = Theme.of(context).primaryColor;
    Color iconBgColor = Theme.of(context).primaryColor.withOpacity(0.08);

    if (widget.isSurvey) {
      iconData = Icons.poll_outlined;
      iconColor = Colors.purple.shade600;
      iconBgColor = Colors.purple.shade50;
    } else if (isReminder) {
      iconData = Icons.notifications_active_outlined;
      iconColor = Colors.amber.shade700;
      iconBgColor = Colors.amber.shade50;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Kartın geneline tıklayınca detay sayfasına gitsin
            if (!widget.isRead) widget.onMarkAsRead();
            widget.onTap();
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sol İkon
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: iconBgColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(iconData, color: iconColor, size: 24),
                    ),
                    const SizedBox(width: 16),
                    // Orta Kısım
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1E293B),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.isPinned)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Icon(
                                    Icons.push_pin,
                                    size: 16,
                                    color: Colors.red.shade400,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 14,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                dateStr,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Menu ve Yeni Rozeti
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!widget.isRead && !widget.isCreator)
                          Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF43F5E),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'YENİ',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert,
                            color: Colors.grey.shade400,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          onSelected: (value) {
                            if (value == 'pin') {
                              widget.onTogglePin();
                            } else if (value == 'detail') {
                              widget.onTap();
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'detail',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.visibility_outlined,
                                    size: 20,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(width: 12),
                                  Text("Detayı Gör"),
                                ],
                              ),
                            ),
                            if (widget.canEdit || widget.isCreator)
                              PopupMenuItem(
                                value: 'pin',
                                child: Row(
                                  children: [
                                    Icon(
                                      widget.isPinned
                                          ? Icons.push_pin_outlined
                                          : Icons.push_pin,
                                      size: 20,
                                      color: widget.isPinned
                                          ? Colors.grey
                                          : Theme.of(context).primaryColor,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      widget.isPinned
                                          ? 'Sabitlemeyi Kaldır'
                                          : 'Sabitle',
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // İçerik ve Genişletme
                LayoutBuilder(
                  builder: (context, constraints) {
                    final textStyle = GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.6,
                      color: const Color(0xFF475569),
                    );

                    final span = TextSpan(text: content, style: textStyle);
                    final tp = TextPainter(
                      text: span,
                      maxLines: 3,
                      textDirection: ui.TextDirection.ltr,
                    );
                    tp.layout(maxWidth: constraints.maxWidth);

                    final bool isOverflowing = tp.didExceedMaxLines;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          content,
                          maxLines: _isExpanded ? null : 3,
                          overflow: _isExpanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: textStyle,
                        ),
                        if (isOverflowing || _isExpanded)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isExpanded = !_isExpanded;
                                });
                              },
                              child: Text(
                                _isExpanded ? 'Daha Az Göster' : 'Devamını Gör',
                                style: GoogleFonts.inter(
                                  color: Theme.of(context).primaryColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 16),

                // Anket Butonu
                if (widget.isSurvey)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      // Doğrudan survey ekranına gitme logic'i
                      onPressed: _handleSurveyTap,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.purple.shade700,
                        side: BorderSide(color: Colors.purple.shade200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: Colors.purple.shade50,
                      ),
                      icon: const Icon(Icons.poll_outlined, size: 18),
                      label: const Text("Ankete Git"),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
