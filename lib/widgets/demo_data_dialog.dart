import 'package:flutter/material.dart';

import '../services/demo_data_seeder.dart';

/// GEÇİCİ: Demo / tanıtım verisi üretme butonu (yönetici panelinde gösterilir).
/// Tanıtım bittikten sonra bu widget'ın kullanıldığı yerden kaldırılabilir.
class DemoDataButton extends StatelessWidget {
  final String institutionId;
  const DemoDataButton({super.key, required this.institutionId});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF7C3AED),
      elevation: 6,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: () => showDemoDataDialog(context, institutionId),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.science_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                'Demo Veri Üret (Geçici)',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showDemoDataDialog(BuildContext context, String institutionId) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DemoDataDialog(institutionId: institutionId),
  );
}

class _DemoDataDialog extends StatefulWidget {
  final String institutionId;
  const _DemoDataDialog({required this.institutionId});

  @override
  State<_DemoDataDialog> createState() => _DemoDataDialogState();
}

class _DemoDataDialogState extends State<_DemoDataDialog> {
  bool _running = false;
  bool _done = false;
  double _progress = 0;
  String _message = '';
  String? _error;
  DemoSeedResult? _result;
  int? _cleared;

  Future<void> _seed() async {
    setState(() {
      _running = true;
      _done = false;
      _error = null;
      _result = null;
      _cleared = null;
      _progress = 0;
      _message = 'Başlatılıyor...';
    });
    try {
      final res = await DemoDataSeeder.seed(
        institutionId: widget.institutionId,
        onProgress: (m, p) {
          if (!mounted) return;
          setState(() {
            _message = m;
            _progress = p;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _result = res;
        _done = true;
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is StateError ? e.message : e.toString();
        _running = false;
      });
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Demo verileri silinsin mi?'),
        content: const Text(
          'Yalnızca "demo" olarak işaretlenmiş kayıtlar silinir. Gerçek kayıtlara dokunulmaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _running = true;
      _done = false;
      _error = null;
      _result = null;
      _progress = 0;
      _message = 'Temizleniyor...';
    });
    try {
      final n = await DemoDataSeeder.clear(
        institutionId: widget.institutionId,
        onProgress: (m, p) {
          if (!mounted) return;
          setState(() {
            _message = m;
            _progress = p;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _cleared = n;
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.science_rounded, color: Color(0xFF7C3AED)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Demo Veri Üretici',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(child: _content()),
      ),
      actions: [
        if (!_running)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        if (!_running && !_done)
          TextButton.icon(
            onPressed: _clear,
            icon: const Icon(
              Icons.delete_sweep_rounded,
              color: Colors.red,
              size: 18,
            ),
            label: const Text(
              'Demo Verileri Temizle',
              style: TextStyle(color: Colors.red),
            ),
          ),
        if (!_running && !_done)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
            ),
            onPressed: _seed,
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(_error != null ? 'Tekrar Dene' : 'Üret'),
          ),
      ],
    );
  }

  Widget _content() {
    if (_running) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: _progress > 0 && _progress < 1 ? _progress : null,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
            color: const Color(0xFF7C3AED),
          ),
          const SizedBox(height: 14),
          Text(_message, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'Lütfen bu pencereyi kapatmayın. İşlem birkaç dakika sürebilir.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      );
    }
    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Text(_error!, style: const TextStyle(color: Color(0xFF991B1B))),
      );
    }
    if (_cleared != null) {
      return Text(
        '$_cleared demo kaydı silindi.',
        style: const TextStyle(fontWeight: FontWeight.w700),
      );
    }
    if (_done && _result != null) {
      final r = _result!;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '✅ ${r.totalDocs} kayıt üretildi.',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: r.counts.entries
                .map(
                  (e) => Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${e.key}: ${e.value}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          for (final n in r.notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $n',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Sayfayı yenileyerek (F5 / hot restart) demo verilerini tüm modüllerde görebilirsiniz.',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      );
    }
    return const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bu kuruma; sınıflar, öğretmenler, öğrenciler, veliler, dersler, ödevler, yazılı notları, '
          'yoklamalar, deneme sınavları (LGS/TYT sonuçları, kazanım ve madde verileri), etütler, '
          'duyurular ve yemek listesi gibi tüm modüller için gerçekçi DEMO verileri üretilir.',
          style: TextStyle(fontSize: 13.5, height: 1.4),
        ),
        SizedBox(height: 12),
        Text(
          '🔒 Güvenlik: Kurumda gerçek öğrenci kaydı varsa üretim reddedilir. '
          'Üretilen tüm kayıtlar "demo" etiketlidir ve tek tuşla silinebilir.',
          style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.4),
        ),
      ],
    );
  }
}
