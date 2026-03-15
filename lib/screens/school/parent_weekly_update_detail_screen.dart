import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

class ParentWeeklyUpdateDetailScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String? periodId;

  final String classId;
  final String className;

  final String lessonId;
  final String lessonName;

  final DateTime weekStart;

  const ParentWeeklyUpdateDetailScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    this.periodId,
    required this.classId,
    required this.className,
    required this.lessonId,
    required this.lessonName,
    required this.weekStart,
  });

  @override
  State<ParentWeeklyUpdateDetailScreen> createState() => _ParentWeeklyUpdateDetailScreenState();
}

class _ParentWeeklyUpdateDetailScreenState extends State<ParentWeeklyUpdateDetailScreen> {
  bool _loading = true;
  String _content = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime _startOfWeek(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  String _weekKey(DateTime weekStart) {
    final d = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  String _docKey(DateTime weekStart) {
    final period = (widget.periodId ?? '').trim().isEmpty ? '__none__' : widget.periodId!.trim();
    return '${widget.institutionId}__${widget.schoolTypeId}__${period}__${widget.classId}__${widget.lessonId}__${_weekKey(weekStart)}';
  }

  String _formatWeekRangeTr(DateTime weekStart) {
    String monthNameTr(int month) {
      const months = <String>[
        'Ocak',
        'Şubat',
        'Mart',
        'Nisan',
        'Mayıs',
        'Haziran',
        'Temmuz',
        'Ağustos',
        'Eylül',
        'Ekim',
        'Kasım',
        'Aralık',
      ];
      if (month < 1 || month > 12) return '';
      return months[month - 1];
    }

    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = start.add(const Duration(days: 6));

    if (start.month == end.month && start.year == end.year) {
      return '${start.day} - ${end.day} ${monthNameTr(end.month)} ${end.year}';
    }
    return '${start.day} ${monthNameTr(start.month)} - ${end.day} ${monthNameTr(end.month)} ${end.year}';
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final ws = _startOfWeek(widget.weekStart);
      final id = _docKey(ws);
      final doc = await FirebaseFirestore.instance.collection('parentWeeklyUpdates').doc(id).get();

      if (!mounted) return;

      if (!doc.exists) {
        setState(() {
          _content = '';
          _loading = false;
        });
        return;
      }

      final data = doc.data() ?? <String, dynamic>{};
      setState(() {
        _content = (data['content'] ?? '').toString();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _content = '';
        _loading = false;
      });
    }
  }

  Future<Uint8List> _buildPdfBytes() async {
    final weekLabel = _formatWeekRangeTr(_startOfWeek(widget.weekStart));
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Veli Bilgilendirme Mektubu', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Text('${widget.className} • ${widget.lessonName}', style: const pw.TextStyle(fontSize: 12)),
              pw.Text('Hafta: $weekLabel', style: const pw.TextStyle(fontSize: 12)),
              pw.SizedBox(height: 14),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
                child: pw.Text(_content.trim().isEmpty ? '-' : _content.trim(), style: const pw.TextStyle(fontSize: 12)),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  Future<void> _share() async {
    final text = _content.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paylaşılacak içerik bulunamadı')));
      return;
    }

    final weekLabel = _formatWeekRangeTr(_startOfWeek(widget.weekStart));
    await Share.share(
      'Veli Bilgilendirme Mektubu\n\n${widget.className} • ${widget.lessonName}\nHafta: $weekLabel\n\n$text',
      subject: 'Veli Bilgilendirme Mektubu',
    );
  }

  Future<void> _print() async {
    final bytes = await _buildPdfBytes();
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  @override
  Widget build(BuildContext context) {
    final weekLabel = _formatWeekRangeTr(_startOfWeek(widget.weekStart));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mektup Detayı', style: TextStyle(fontWeight: FontWeight.w800)),
            Text('${widget.className} • ${widget.lessonName}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Paylaş',
            onPressed: _loading ? null : _share,
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: 'Yazdır',
            onPressed: _loading ? null : _print,
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 6)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Seçili Hafta', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(weekLabel, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 6)),
                        ],
                      ),
                      child: _content.trim().isEmpty
                          ? Text(
                              'Bu haftaya ait mektup bulunamadı.',
                              style: TextStyle(color: Colors.grey.shade600),
                              textAlign: TextAlign.center,
                            )
                          : Text(
                              _content.trim(),
                              style: TextStyle(color: Colors.grey.shade900, height: 1.35),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
