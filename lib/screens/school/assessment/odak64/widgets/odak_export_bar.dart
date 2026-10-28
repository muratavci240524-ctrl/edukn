import 'dart:typed_data';

import 'package:edukn/services/web_share/web_file_share.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// PDF İndir / Yazdır / Paylaş düğmeleri.
/// [buildPdf] tıklanınca üretilir; böylece sadece ihtiyaç olduğunda çalışır.
class OdakExportBar extends StatefulWidget {
  final Future<Uint8List> Function() buildPdf;
  final String fileName;
  final String title;
  final String shareText;
  final bool dark;

  /// Doluysa 'Kapı Listesi' (sadece isimler) menüsü gösterilir.
  final Future<Uint8List> Function()? buildDoorList;
  final String doorFileName;

  /// Doluysa kapı listesi menüsüne 'Excel İndir' eklenir.
  final Future<void> Function()? doorExcel;

  const OdakExportBar({
    super.key,
    required this.buildPdf,
    required this.fileName,
    required this.title,
    required this.shareText,
    this.dark = false,
    this.buildDoorList,
    this.doorFileName = 'Kapi_Listesi.pdf',
    this.doorExcel,
  });

  @override
  State<OdakExportBar> createState() => _OdakExportBarState();
}

class _OdakExportBarState extends State<OdakExportBar> {
  bool _busy = false;

  Future<void> _run(Future<void> Function(Uint8List bytes) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await widget.buildPdf();
      await action(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF hazırlanamadı: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _door(String kind) async {
    final print = kind == 'print';
    if (_busy || widget.buildDoorList == null) return;
    setState(() => _busy = true);
    try {
      if (kind == 'excel') {
        await widget.doorExcel?.call();
        return;
      }
      final bytes = await widget.buildDoorList!();
      if (print) {
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name: widget.doorFileName,
        );
      } else {
        await Printing.sharePdf(bytes: bytes, filename: widget.doorFileName);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF hazırlanamadı: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() => _run(
        (b) => Printing.sharePdf(bytes: b, filename: widget.fileName),
      );

  Future<void> _print() => _run(
        (b) async {
          await Printing.layoutPdf(
            onLayout: (_) async => b,
            name: widget.fileName,
          );
        },
      );

  Future<void> _share() => _run((b) async {
        if (!mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) => _ShareSheet(
            bytes: b,
            fileName: widget.fileName,
            title: widget.title,
            text: widget.shareText,
          ),
        );
      });

  @override
  Widget build(BuildContext context) {
    final fg = widget.dark ? Colors.white : Theme.of(context).colorScheme.primary;
    final style = OutlinedButton.styleFrom(
      foregroundColor: fg,
      side: BorderSide(color: fg.withValues(alpha: 0.6)),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          style: style,
          onPressed: _busy ? null : _download,
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
          label: const Text('PDF İndir'),
        ),
        OutlinedButton.icon(
          style: style,
          onPressed: _busy ? null : _print,
          icon: const Icon(Icons.print_rounded, size: 18),
          label: const Text('Yazdır'),
        ),
        OutlinedButton.icon(
          style: style,
          onPressed: _busy ? null : _share,
          icon: const Icon(Icons.share_rounded, size: 18),
          label: const Text('Paylaş'),
        ),
        if (widget.buildDoorList != null)
          PopupMenuButton<String>(
            enabled: !_busy,
            tooltip: 'Kapı Listesi (sadece isimler)',
            onSelected: _door,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'print',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.print_rounded),
                  title: Text('Kapı Listesi Yazdır'),
                ),
              ),
              const PopupMenuItem(
                value: 'pdf',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.picture_as_pdf_rounded),
                  title: Text('Kapı Listesi PDF İndir'),
                ),
              ),
              if (widget.doorExcel != null)
                const PopupMenuItem(
                  value: 'excel',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.table_chart_rounded, color: Colors.green),
                    title: Text('Kapı Listesi Excel İndir'),
                  ),
                ),
            ],
            child: IgnorePointer(
              child: OutlinedButton.icon(
                style: style,
                onPressed: () {},
                icon: const Icon(Icons.meeting_room_rounded, size: 18),
                label: const Text('Kapı Listesi'),
              ),
            ),
          ),
        if (_busy)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          ),
      ],
    );
  }
}

class _ShareSheet extends StatelessWidget {
  final Uint8List bytes;
  final String fileName;
  final String title;
  final String text;

  const _ShareSheet({
    required this.bytes,
    required this.fileName,
    required this.title,
    required this.text,
  });

  /// PDF'i DOSYA EKLİ olarak işletim sistemi / tarayıcı paylaşım penceresiyle
  /// paylaşır. Başarılıysa true; desteklenmiyorsa false döner.
  Future<bool> _tryShareFile() async {
    if (kIsWeb) {
      return shareFileWeb(
        bytes: bytes,
        fileName: fileName,
        mimeType: 'application/pdf',
        title: title,
        text: text,
      );
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName)],
          fileNameOverrides: [fileName],
          subject: title,
          text: text,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _systemShare(BuildContext context) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (await _tryShareFile()) {
      nav.pop();
      return;
    }
    // Tarayıcı/platform dosya paylaşımını desteklemiyorsa PDF indirilir.
    await Printing.sharePdf(bytes: bytes, filename: fileName);
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Bu cihaz/tarayıcı dosya paylaşımını desteklemiyor; PDF indirildi. '
          'WhatsApp / E-posta seçenekleriyle mesajınıza ekleyebilirsiniz.',
        ),
      ),
    );
  }

  Future<void> _whatsapp(BuildContext context) async {
    final nav = Navigator.of(context);
    // Önce dosya ekli paylaşım penceresi (WhatsApp'ı seçin).
    if (await _tryShareFile()) {
      nav.pop();
      return;
    }
    await Printing.sharePdf(bytes: bytes, filename: fileName);
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent('$text\n\n(PDF dosyasını sohbete ekleyin: $fileName)')}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _mail(BuildContext context) async {
    final nav = Navigator.of(context);
    if (await _tryShareFile()) {
      nav.pop();
      return;
    }
    await Printing.sharePdf(bytes: bytes, filename: fileName);
    final uri = Uri.parse(
      'mailto:?subject=${Uri.encodeComponent(title)}'
      '&body=${Uri.encodeComponent('$text\n\nNOT: İndirilen $fileName dosyasını e-postaya ekleyin.')}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Raporu Paylaş',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(fileName, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            _Tile(
              icon: Icons.ios_share_rounded,
              color: Colors.teal,
              title: 'Paylaş menüsü',
              subtitle: 'PDF dosyası ekli olarak WhatsApp, Gmail vb. ile paylaşılır',
              onTap: () => _systemShare(context),
            ),
            _Tile(
              icon: Icons.chat_rounded,
              color: Colors.green,
              title: 'WhatsApp',
              subtitle: 'PDF ekli paylaşım açılır (WhatsApp\'ı seçin); olmazsa PDF iner',
              onTap: () => _whatsapp(context),
            ),
            _Tile(
              icon: Icons.email_rounded,
              color: Colors.blue,
              title: 'E-posta (Gmail)',
              subtitle: 'PDF ekli paylaşım açılır (Gmail\'i seçin); olmazsa PDF iner',
              onTap: () => _mail(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final MaterialColor color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: color.shade50,
        child: Icon(icon, color: color.shade700),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
