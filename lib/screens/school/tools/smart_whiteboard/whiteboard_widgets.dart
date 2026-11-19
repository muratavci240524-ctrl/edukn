import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ---------------------------------------------------------------------------
/// Matematiksel ifade çözücü (hesap makinesi ve grafik çizici için)
/// ---------------------------------------------------------------------------
class WbExpr {
  WbExpr(String src, {this.degrees = false, this.x = 0})
    : _s = src
          .replaceAll(' ', '')
          .replaceAll(',', '.')
          .toLowerCase()
          .replaceAll('×', '*')
          .replaceAll('÷', '/')
          .replaceAll('−', '-')
          .replaceAll('π', 'pi')
          .replaceAll('√', 'sqrt');

  final String _s;
  final bool degrees;
  final double x;
  int _i = 0;

  static double? tryEval(String src, {double x = 0, bool degrees = false}) {
    if (src.trim().isEmpty) return null;
    try {
      return WbExpr(src, degrees: degrees, x: x)._parse();
    } catch (_) {
      return null;
    }
  }

  double _parse() {
    _i = 0;
    final v = _expr();
    if (_i < _s.length) throw const FormatException('beklenmeyen karakter');
    return v;
  }

  bool _peek(String c) => _i < _s.length && _s[_i] == c;

  double _expr() {
    var v = _term();
    while (_i < _s.length) {
      if (_peek('+')) {
        _i++;
        v += _term();
      } else if (_peek('-')) {
        _i++;
        v -= _term();
      } else {
        break;
      }
    }
    return v;
  }

  double _term() {
    var v = _unary();
    while (_i < _s.length) {
      if (_peek('*')) {
        _i++;
        v *= _unary();
      } else if (_peek('/')) {
        _i++;
        v /= _unary();
      } else if (_peek('%')) {
        _i++;
        v %= _unary();
      } else if (RegExp(r'[0-9a-z(.]').hasMatch(_s[_i])) {
        v *= _unary(); // kapalı çarpma: 2x, 3(4+1), 2pi
      } else {
        break;
      }
    }
    return v;
  }

  double _unary() {
    if (_peek('-')) {
      _i++;
      return -_unary();
    }
    if (_peek('+')) {
      _i++;
      return _unary();
    }
    return _power();
  }

  double _power() {
    final b = _primary();
    if (_peek('^')) {
      _i++;
      final e = _unary();
      return math.pow(b, e).toDouble();
    }
    return b;
  }

  double _primary() {
    if (_i >= _s.length) throw const FormatException('eksik ifade');
    final c = _s[_i];
    if (c == '(') {
      _i++;
      final v = _expr();
      if (!_peek(')')) throw const FormatException('parantez');
      _i++;
      return v;
    }
    if (RegExp(r'[0-9.]').hasMatch(c)) {
      final start = _i;
      while (_i < _s.length && RegExp(r'[0-9.]').hasMatch(_s[_i])) {
        _i++;
      }
      return double.parse(_s.substring(start, _i));
    }
    if (RegExp(r'[a-z]').hasMatch(c)) {
      final start = _i;
      while (_i < _s.length && RegExp(r'[a-z]').hasMatch(_s[_i])) {
        _i++;
      }
      final name = _s.substring(start, _i);
      switch (name) {
        case 'pi':
          return math.pi;
        case 'e':
          return math.e;
        case 'x':
          return x;
      }
      final arg = _peek('(') ? _primaryParen() : _power();
      return _func(name, arg);
    }
    throw FormatException('geçersiz karakter $c');
  }

  double _primaryParen() {
    _i++; // (
    final v = _expr();
    if (!_peek(')')) throw const FormatException('parantez');
    _i++;
    return v;
  }

  double _func(String n, double a) {
    final r = degrees ? a * math.pi / 180 : a;
    double back(double v) => degrees ? v * 180 / math.pi : v;
    switch (n) {
      case 'sin':
        return math.sin(r);
      case 'cos':
        return math.cos(r);
      case 'tan':
        return math.tan(r);
      case 'asin':
        return back(math.asin(a));
      case 'acos':
        return back(math.acos(a));
      case 'atan':
        return back(math.atan(a));
      case 'sqrt':
        return math.sqrt(a);
      case 'abs':
        return a.abs();
      case 'ln':
        return math.log(a);
      case 'log':
        return math.log(a) / math.ln10;
      case 'exp':
        return math.exp(a);
      case 'floor':
        return a.floorToDouble();
      case 'ceil':
        return a.ceilToDouble();
      case 'round':
        return a.roundToDouble();
    }
    throw FormatException('bilinmeyen fonksiyon $n');
  }
}

String wbFormatNumber(double v) {
  if (v.isNaN) return 'Hata';
  if (v.isInfinite) return v > 0 ? '∞' : '-∞';
  if (v.abs() < 1e15 && v == v.roundToDouble()) return v.toInt().toString();
  var s = v.toStringAsFixed(8);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}

/// ---------------------------------------------------------------------------
/// Sürüklenebilir yüzen panel (zamanlayıcı, hesap makinesi vb. için çerçeve)
/// ---------------------------------------------------------------------------
class WbFloatingPanel extends StatefulWidget {
  const WbFloatingPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    required this.onClose,
    this.width = 320,
    this.initial = const Offset(120, 90),
  });

  final String title;
  final IconData icon;
  final Widget child;
  final VoidCallback onClose;
  final double width;
  final Offset initial;

  @override
  State<WbFloatingPanel> createState() => _WbFloatingPanelState();
}

class _WbFloatingPanelState extends State<WbFloatingPanel> {
  late Offset _pos = widget.initial;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = math.min(widget.width, size.width - 16);
    final left = _pos.dx.clamp(0.0, math.max(0.0, size.width - w)).toDouble();
    final top = _pos.dy.clamp(0.0, math.max(0.0, size.height - 60)).toDouble();
    return Positioned(
      left: left,
      top: top,
      width: w,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {},
        child: Material(
          color: Colors.white,
          elevation: 14,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) =>
                    setState(() => _pos = Offset(left, top) + d.delta),
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  color: const Color(0xFF1E293B),
                  child: Row(
                    children: [
                      Icon(widget.icon, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.drag_indicator_rounded,
                        color: Colors.white38,
                        size: 18,
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                ),
              ),
              widget.child,
            ],
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Geri sayım zamanlayıcısı
/// ---------------------------------------------------------------------------
class WbCountdown extends StatefulWidget {
  const WbCountdown({super.key});
  @override
  State<WbCountdown> createState() => _WbCountdownState();
}

class _WbCountdownState extends State<WbCountdown> {
  int _total = 300;
  int _remaining = 300;
  bool _running = false;
  bool _done = false;
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _setTotal(int secs) {
    setState(() {
      _total = secs.clamp(5, 3 * 3600);
      _remaining = _total;
      _done = false;
    });
  }

  void _toggle() {
    if (_running) {
      _t?.cancel();
      setState(() => _running = false);
      return;
    }
    if (_remaining <= 0) _remaining = _total;
    _done = false;
    setState(() => _running = true);
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _remaining--;
        if (_remaining <= 0) {
          _remaining = 0;
          _running = false;
          _done = true;
          t.cancel();
          SystemSound.play(SystemSoundType.alert);
        }
      });
    });
  }

  void _reset() {
    _t?.cancel();
    setState(() {
      _running = false;
      _done = false;
      _remaining = _total;
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = (_remaining ~/ 60).toString().padLeft(2, '0');
    final s = (_remaining % 60).toString().padLeft(2, '0');
    final progress = _total == 0 ? 0.0 : _remaining / _total;
    final color = _done
        ? Colors.red
        : (progress < 0.2 ? Colors.deepOrange : const Color(0xFF2563EB));
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 170,
            height: 170,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 10,
                    color: color,
                    backgroundColor: Colors.grey.shade200,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$m:$s',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (_done)
                      const Text(
                        'Süre doldu!',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final min in [1, 3, 5, 10, 15, 20, 30, 45])
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text('$min dk'),
                  onPressed: _running ? null : () => _setTotal(min * 60),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '-1 dk',
                onPressed: _running ? null : () => _setTotal(_total - 60),
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
              const Text('Süre ayarla', style: TextStyle(fontSize: 12)),
              IconButton(
                tooltip: '+1 dk',
                onPressed: _running ? null : () => _setTotal(_total + 60),
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _toggle,
                  icon: Icon(
                    _running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(_running ? 'Duraklat' : 'Başlat'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Sıfırla'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Kronometre
/// ---------------------------------------------------------------------------
class WbStopwatch extends StatefulWidget {
  const WbStopwatch({super.key});
  @override
  State<WbStopwatch> createState() => _WbStopwatchState();
}

class _WbStopwatchState extends State<WbStopwatch> {
  final Stopwatch _sw = Stopwatch();
  Timer? _t;
  final List<Duration> _laps = [];

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final c = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$m:$s.$c';
  }

  void _toggle() {
    if (_sw.isRunning) {
      _sw.stop();
      _t?.cancel();
    } else {
      _sw.start();
      _t = Timer.periodic(const Duration(milliseconds: 40), (_) {
        if (mounted) setState(() {});
      });
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _fmt(_sw.elapsed),
            style: const TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _toggle,
                  icon: Icon(
                    _sw.isRunning
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  label: Text(_sw.isRunning ? 'Durdur' : 'Başlat'),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.outlined(
                tooltip: 'Tur',
                onPressed: _sw.isRunning
                    ? () => setState(() => _laps.insert(0, _sw.elapsed))
                    : null,
                icon: const Icon(Icons.flag_rounded),
              ),
              IconButton.outlined(
                tooltip: 'Sıfırla',
                onPressed: () {
                  _sw.reset();
                  _laps.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.restart_alt_rounded),
              ),
            ],
          ),
          if (_laps.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 130),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _laps.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Tur ${_laps.length - i}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      Text(
                        _fmt(_laps[i]),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Zar
/// ---------------------------------------------------------------------------
class WbDice extends StatefulWidget {
  const WbDice({super.key});
  @override
  State<WbDice> createState() => _WbDiceState();
}

class _WbDiceState extends State<WbDice> {
  int _count = 2;
  List<int> _vals = [3, 5, 1];
  Timer? _t;
  final _rng = math.Random();

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _roll() {
    int n = 0;
    _t?.cancel();
    _t = Timer.periodic(const Duration(milliseconds: 70), (t) {
      if (!mounted) return;
      setState(() => _vals = List.generate(3, (_) => 1 + _rng.nextInt(6)));
      if (++n >= 10) t.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = _vals.take(_count).fold<int>(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1 zar')),
              ButtonSegment(value: 2, label: Text('2 zar')),
              ButtonSegment(value: 3, label: Text('3 zar')),
            ],
            selected: {_count},
            onSelectionChanged: (s) => setState(() => _count = s.first),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            children: [
              for (int i = 0; i < _count; i++)
                SizedBox(
                  width: 70,
                  height: 70,
                  child: CustomPaint(painter: _DicePainter(_vals[i])),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Toplam: $total',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _roll,
              icon: const Icon(Icons.casino_rounded),
              label: const Text('Zar At'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DicePainter extends CustomPainter {
  _DicePainter(this.v);
  final int v;
  @override
  void paint(Canvas canvas, Size s) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & s,
      Radius.circular(s.width * 0.2),
    );
    canvas.drawRRect(r, Paint()..color = Colors.white);
    canvas.drawRRect(
      r,
      Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final pip = Paint()..color = const Color(0xFF1E293B);
    final a = s.width * 0.25, b = s.width * 0.5, c = s.width * 0.75;
    final pr = s.width * 0.075;
    final map = <int, List<Offset>>{
      1: [Offset(b, b)],
      2: [Offset(a, a), Offset(c, c)],
      3: [Offset(a, a), Offset(b, b), Offset(c, c)],
      4: [Offset(a, a), Offset(c, a), Offset(a, c), Offset(c, c)],
      5: [Offset(a, a), Offset(c, a), Offset(b, b), Offset(a, c), Offset(c, c)],
      6: [
        Offset(a, a),
        Offset(c, a),
        Offset(a, b),
        Offset(c, b),
        Offset(a, c),
        Offset(c, c),
      ],
    };
    for (final o in map[v] ?? const <Offset>[]) {
      canvas.drawCircle(o, pr + 1.5, pip);
    }
  }

  @override
  bool shouldRepaint(covariant _DicePainter old) => old.v != v;
}

/// ---------------------------------------------------------------------------
/// Yazı - Tura
/// ---------------------------------------------------------------------------
class WbCoin extends StatefulWidget {
  const WbCoin({super.key});
  @override
  State<WbCoin> createState() => _WbCoinState();
}

class _WbCoinState extends State<WbCoin> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _heads = true;
  final _rng = math.Random();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _flip() {
    final next = _rng.nextBool();
    setState(() => _heads = next);
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final t = Curves.easeOut.transform(_c.value);
              final turns = t * math.pi * 7 + (_heads ? 0 : math.pi);
              final showFront = math.cos(turns) >= 0;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.002)
                  ..rotateX(turns)
                  ..translate(0.0, -math.sin(t * math.pi) * 30, 0.0),
                child: Container(
                  width: 110,
                  height: 110,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Color(0xFFFFE082), Color(0xFFFFB300)],
                    ),
                    border: Border.all(
                      color: const Color(0xFFB77900),
                      width: 4,
                    ),
                  ),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..rotateX(showFront ? 0 : math.pi),
                    child: Text(
                      showFront ? 'YAZI' : 'TURA',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF6D4C00),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _flip,
              icon: const Icon(Icons.monetization_on_rounded),
              label: const Text('Parayı At'),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Rastgele sayı
/// ---------------------------------------------------------------------------
class WbRandomNumber extends StatefulWidget {
  const WbRandomNumber({super.key});
  @override
  State<WbRandomNumber> createState() => _WbRandomNumberState();
}

class _WbRandomNumberState extends State<WbRandomNumber> {
  final _min = TextEditingController(text: '1');
  final _max = TextEditingController(text: '30');
  int? _value;
  final _rng = math.Random();
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _gen() {
    final a = int.tryParse(_min.text.trim()) ?? 1;
    final b = int.tryParse(_max.text.trim()) ?? 30;
    final lo = math.min(a, b), hi = math.max(a, b);
    int n = 0;
    _t?.cancel();
    _t = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (!mounted) return;
      setState(() => _value = lo + _rng.nextInt(hi - lo + 1));
      if (++n >= 12) t.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _min,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'En küçük',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _max,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'En büyük',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _value?.toString() ?? '?',
            style: const TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.w900,
              color: Color(0xFF7C3AED),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _gen,
              icon: const Icon(Icons.shuffle_rounded),
              label: const Text('Sayı Seç'),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Saat
/// ---------------------------------------------------------------------------
class WbClock extends StatefulWidget {
  const WbClock({super.key});
  @override
  State<WbClock> createState() => _WbClockState();
}

class _WbClockState extends State<WbClock> {
  Timer? _t;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    const days = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];
    const months = [
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
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 170,
            height: 170,
            child: CustomPaint(painter: _ClockPainter(_now)),
          ),
          const SizedBox(height: 8),
          Text(
            '${two(_now.hour)}:${two(_now.minute)}:${two(_now.second)}',
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            '${_now.day} ${months[_now.month - 1]} ${_now.year}, ${days[_now.weekday - 1]}',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClockPainter extends CustomPainter {
  _ClockPainter(this.t);
  final DateTime t;
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2 - 4;
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    for (int i = 0; i < 60; i++) {
      final a = i * math.pi / 30;
      final len = i % 5 == 0 ? 10.0 : 4.0;
      canvas.drawLine(
        c + Offset(math.sin(a), -math.cos(a)) * (r - 6),
        c + Offset(math.sin(a), -math.cos(a)) * (r - 6 - len),
        Paint()
          ..color = const Color(0xFF1E293B)
          ..strokeWidth = i % 5 == 0 ? 2.4 : 1,
      );
    }
    for (int h = 1; h <= 12; h++) {
      final a = h * math.pi / 6;
      final tp = TextPainter(
        text: TextSpan(
          text: '$h',
          style: const TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final pos = c + Offset(math.sin(a), -math.cos(a)) * (r - 26);
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
    void hand(double angle, double len, double w, Color col) {
      canvas.drawLine(
        c,
        c + Offset(math.sin(angle), -math.cos(angle)) * len,
        Paint()
          ..color = col
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round,
      );
    }

    hand(
      (t.hour % 12 + t.minute / 60) * math.pi / 6,
      r * 0.5,
      5,
      const Color(0xFF1E293B),
    );
    hand(
      (t.minute + t.second / 60) * math.pi / 30,
      r * 0.74,
      3.5,
      const Color(0xFF1E293B),
    );
    hand(t.second * math.pi / 30, r * 0.84, 1.8, Colors.red);
    canvas.drawCircle(c, 5, Paint()..color = Colors.red);
  }

  @override
  bool shouldRepaint(covariant _ClockPainter old) => old.t.second != t.second;
}

/// ---------------------------------------------------------------------------
/// Bilimsel hesap makinesi
/// ---------------------------------------------------------------------------
class WbCalculator extends StatefulWidget {
  const WbCalculator({super.key});
  @override
  State<WbCalculator> createState() => _WbCalculatorState();
}

class _WbCalculatorState extends State<WbCalculator> {
  String _expr = '';
  bool _deg = true;
  String? _result;

  static const _rows = [
    ['C', '⌫', '(', ')', '÷'],
    ['sin', 'cos', 'tan', '√', '×'],
    ['7', '8', '9', '^', '−'],
    ['4', '5', '6', 'π', '+'],
    ['1', '2', '3', 'x²', '='],
    ['0', '.', 'ln', 'log', 'Ans'],
  ];

  void _press(String k) {
    setState(() {
      switch (k) {
        case 'C':
          _expr = '';
          _result = null;
          return;
        case '⌫':
          if (_expr.isNotEmpty) _expr = _expr.substring(0, _expr.length - 1);
          break;
        case '=':
          final v = WbExpr.tryEval(_expr, degrees: _deg);
          if (v != null) {
            _result = wbFormatNumber(v);
          } else {
            _result = 'Hata';
          }
          return;
        case 'Ans':
          if (_result != null && _result != 'Hata') _expr += _result!;
          break;
        case 'sin':
        case 'cos':
        case 'tan':
        case 'ln':
        case 'log':
          _expr += '$k(';
          break;
        case '√':
          _expr += '√(';
          break;
        case 'x²':
          _expr += '^2';
          break;
        default:
          _expr += k;
      }
      final live = WbExpr.tryEval(_expr, degrees: _deg);
      _result = live == null ? null : wbFormatNumber(live);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _expr.isEmpty ? '0' : _expr,
                  style: const TextStyle(color: Colors.white70, fontSize: 17),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _result ?? ' ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _deg = !_deg),
              child: Text(_deg ? 'Derece (DEG)' : 'Radyan (RAD)'),
            ),
          ),
          for (final row in _rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  for (final k in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5),
                        child: SizedBox(
                          height: 40,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              backgroundColor: k == '='
                                  ? const Color(0xFF2563EB)
                                  : (RegExp(r'^[0-9.]$').hasMatch(k)
                                        ? Colors.grey.shade200
                                        : const Color(0xFFE0E7FF)),
                              foregroundColor: k == '='
                                  ? Colors.white
                                  : const Color(0xFF1E293B),
                            ),
                            onPressed: () => _press(k),
                            child: Text(
                              k,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Fonksiyon grafik çizici
/// ---------------------------------------------------------------------------
class WbGrapher extends StatefulWidget {
  const WbGrapher({super.key});
  @override
  State<WbGrapher> createState() => _WbGrapherState();
}

class _WbGrapherState extends State<WbGrapher> {
  final List<TextEditingController> _ctrls = [
    TextEditingController(text: 'x^2'),
    TextEditingController(text: 'sin(x)'),
    TextEditingController(),
  ];
  static const _colors = [
    Color(0xFF2563EB),
    Color(0xFFE11D48),
    Color(0xFF059669),
  ];
  double _cx = 0, _cy = 0, _ppu = 28;
  double _baseScale = 1;

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: TextField(
                controller: _ctrls[i],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.show_chart_rounded, color: _colors[i]),
                  prefixText: 'y = ',
                  hintText: 'ör. x^2 - 3x + 1',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 250,
              child: GestureDetector(
                onScaleStart: (_) => _baseScale = _ppu,
                onScaleUpdate: (d) {
                  setState(() {
                    _ppu = (_baseScale * d.scale).clamp(4.0, 400.0);
                    _cx -= d.focalPointDelta.dx / _ppu;
                    _cy += d.focalPointDelta.dy / _ppu;
                  });
                },
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _GraphPainter(
                    exprs: _ctrls.map((c) => c.text).toList(),
                    colors: _colors,
                    cx: _cx,
                    cy: _cy,
                    ppu: _ppu,
                  ),
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () =>
                    setState(() => _ppu = (_ppu * 1.3).clamp(4.0, 400.0)),
                icon: const Icon(Icons.zoom_in_rounded),
              ),
              IconButton(
                onPressed: () =>
                    setState(() => _ppu = (_ppu / 1.3).clamp(4.0, 400.0)),
                icon: const Icon(Icons.zoom_out_rounded),
              ),
              IconButton(
                onPressed: () => setState(() {
                  _cx = 0;
                  _cy = 0;
                  _ppu = 28;
                }),
                icon: const Icon(Icons.center_focus_strong_rounded),
              ),
              const Text(
                'Sürükle: kaydır • Sıkıştır: yakınlaştır',
                style: TextStyle(fontSize: 10.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.exprs,
    required this.colors,
    required this.cx,
    required this.cy,
    required this.ppu,
  });
  final List<String> exprs;
  final List<Color> colors;
  final double cx, cy, ppu;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    Offset toScreen(double x, double y) => Offset(
      size.width / 2 + (x - cx) * ppu,
      size.height / 2 - (y - cy) * ppu,
    );
    final xMin = cx - size.width / 2 / ppu, xMax = cx + size.width / 2 / ppu;
    final yMin = cy - size.height / 2 / ppu, yMax = cy + size.height / 2 / ppu;

    double step = 1;
    while (step * ppu < 26) {
      step *= 2;
    }
    final grid = Paint()
      ..color = const Color(0x22000000)
      ..strokeWidth = 1;
    for (double x = (xMin / step).floor() * step; x <= xMax; x += step) {
      canvas.drawLine(toScreen(x, yMin), toScreen(x, yMax), grid);
    }
    for (double y = (yMin / step).floor() * step; y <= yMax; y += step) {
      canvas.drawLine(toScreen(xMin, y), toScreen(xMax, y), grid);
    }
    final axis = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 1.8;
    canvas.drawLine(toScreen(xMin, 0), toScreen(xMax, 0), axis);
    canvas.drawLine(toScreen(0, yMin), toScreen(0, yMax), axis);
    int cnt = 0;
    for (
      double x = (xMin / step).floor() * step;
      x <= xMax && cnt < 40;
      x += step, cnt++
    ) {
      if (x.abs() < 1e-9) continue;
      final tp = wbLabel(wbFormatNumber(double.parse(x.toStringAsFixed(4))));
      final p = toScreen(x, 0);
      tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy + 3));
    }
    cnt = 0;
    for (
      double y = (yMin / step).floor() * step;
      y <= yMax && cnt < 40;
      y += step, cnt++
    ) {
      if (y.abs() < 1e-9) continue;
      final tp = wbLabel(wbFormatNumber(double.parse(y.toStringAsFixed(4))));
      final p = toScreen(0, y);
      tp.paint(canvas, Offset(p.dx + 4, p.dy - tp.height / 2));
    }

    for (int k = 0; k < exprs.length; k++) {
      if (exprs[k].trim().isEmpty) continue;
      final paint = Paint()
        ..color = colors[k]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round;
      final path = Path();
      bool pen = false;
      double? prevY;
      final n = size.width.toInt() * 2;
      for (int i = 0; i <= n; i++) {
        final x = xMin + (xMax - xMin) * i / n;
        final y = WbExpr.tryEval(exprs[k], x: x, degrees: false);
        if (y == null || y.isNaN || y.isInfinite || y.abs() > 1e6) {
          pen = false;
          prevY = null;
          continue;
        }
        final p = toScreen(x, y);
        // süreksizlik (örn. tan, 1/x) için yüksek sıçramada çizgiyi kes
        if (prevY != null && (y - prevY).abs() > (yMax - yMin) * 1.5)
          pen = false;
        if (!pen) {
          path.moveTo(p.dx, p.dy);
          pen = true;
        } else {
          path.lineTo(p.dx, p.dy);
        }
        prevY = y;
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => true;
}

TextPainter wbLabel(String s) => TextPainter(
  text: TextSpan(
    text: s,
    style: const TextStyle(color: Color(0xFF475569), fontSize: 10),
  ),
  textDirection: TextDirection.ltr,
)..layout();

/// ---------------------------------------------------------------------------
/// Tahta gereçleri: cetvel, iletki, gönye (sürüklenebilir + döndürülebilir)
/// ---------------------------------------------------------------------------
enum WbInstrumentKind { ruler, protractor, setSquare, setSquare45 }

class WbInstrumentView extends StatefulWidget {
  const WbInstrumentView({
    super.key,
    required this.kind,
    required this.pos,
    required this.angle,
    required this.stackKey,
    required this.onChanged,
    required this.onClose,
  });

  final WbInstrumentKind kind;
  final Offset pos;
  final double angle;
  final GlobalKey stackKey;
  final void Function(Offset pos, double angle) onChanged;
  final VoidCallback onClose;

  static Size bodySize(WbInstrumentKind k) {
    switch (k) {
      case WbInstrumentKind.ruler:
        return const Size(640, 68);
      case WbInstrumentKind.protractor:
        return const Size(380, 196);
      case WbInstrumentKind.setSquare:
        return const Size(320, 320);
      case WbInstrumentKind.setSquare45:
        return const Size(320, 320);
    }
  }

  @override
  State<WbInstrumentView> createState() => _WbInstrumentViewState();
}

class _WbInstrumentViewState extends State<WbInstrumentView> {
  Offset? _lastG;

  @override
  Widget build(BuildContext context) {
    final body = WbInstrumentView.bodySize(widget.kind);
    final w = body.width + 52;
    final h = body.height;
    return Positioned(
      left: widget.pos.dx - w / 2,
      top: widget.pos.dy - h / 2,
      width: w,
      height: h,
      child: Transform.rotate(
        angle: widget.angle,
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                width: body.width,
                height: body.height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => _lastG = d.globalPosition,
                  onPanUpdate: (d) {
                    final last = _lastG ?? d.globalPosition;
                    final delta = d.globalPosition - last;
                    _lastG = d.globalPosition;
                    widget.onChanged(widget.pos + delta, widget.angle);
                  },
                  child: CustomPaint(painter: _InstrumentPainter(widget.kind)),
                ),
              ),
              Positioned(
                left: body.width + 6,
                top: h / 2 - 20,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) {
                    final box =
                        widget.stackKey.currentContext?.findRenderObject()
                            as RenderBox?;
                    if (box == null) return;
                    final local = box.globalToLocal(d.globalPosition);
                    widget.onChanged(
                      widget.pos,
                      math.atan2(
                        local.dy - widget.pos.dy,
                        local.dx - widget.pos.dx,
                      ),
                    );
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2563EB),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black38, blurRadius: 6),
                      ],
                    ),
                    child: const Icon(
                      Icons.rotate_right_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: body.width + 14,
                top: h / 2 - 54,
                child: GestureDetector(
                  onTap: widget.onClose,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE11D48),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstrumentPainter extends CustomPainter {
  _InstrumentPainter(this.kind);
  final WbInstrumentKind kind;

  @override
  void paint(Canvas canvas, Size s) {
    final fill = Paint()..color = const Color(0xA6FFE082);
    final edge = Paint()
      ..color = const Color(0xFF8D6E00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final tick = Paint()
      ..color = const Color(0xFF3E2C00)
      ..strokeWidth = 1.2;

    void label(String t, Offset c, {double size = 10}) {
      final tp = TextPainter(
        text: TextSpan(
          text: t,
          style: TextStyle(
            color: const Color(0xFF3E2C00),
            fontSize: size,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }

    switch (kind) {
      case WbInstrumentKind.ruler:
        final r = RRect.fromRectAndRadius(
          Offset.zero & s,
          const Radius.circular(8),
        );
        canvas.drawRRect(r, fill);
        canvas.drawRRect(r, edge);
        const pxPerCm = 20.0;
        for (int mm = 0; mm <= 300; mm++) {
          final x = 10 + mm * pxPerCm / 10;
          if (x > s.width - 6) break;
          final isCm = mm % 10 == 0;
          final isHalf = mm % 5 == 0;
          final len = isCm ? 20.0 : (isHalf ? 14.0 : 8.0);
          canvas.drawLine(Offset(x, 0), Offset(x, len), tick);
          canvas.drawLine(
            Offset(x, s.height),
            Offset(x, s.height - (isCm ? 14.0 : (isHalf ? 10.0 : 6.0))),
            tick,
          );
          if (isCm && mm > 0) label('${mm ~/ 10}', Offset(x, 32));
        }
        label('cm', Offset(s.width - 24, s.height - 14), size: 11);
        break;
      case WbInstrumentKind.protractor:
        final c = Offset(s.width / 2, s.height - 6);
        final R = s.width / 2 - 4;
        final path = Path()
          ..moveTo(c.dx - R, c.dy)
          ..arcTo(
            Rect.fromCircle(center: c, radius: R),
            math.pi,
            math.pi,
            false,
          )
          ..close();
        canvas.drawPath(path, fill);
        canvas.drawPath(path, edge);
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: R * 0.52),
          math.pi,
          math.pi,
          false,
          edge,
        );
        for (int d = 0; d <= 180; d++) {
          final a = math.pi + d * math.pi / 180;
          final dir = Offset(math.cos(a), math.sin(a));
          final len = d % 10 == 0 ? 18.0 : (d % 5 == 0 ? 12.0 : 7.0);
          canvas.drawLine(c + dir * R, c + dir * (R - len), tick);
          if (d % 10 == 0) {
            label('$d', c + dir * (R - 30), size: 9);
            label('${180 - d}', c + dir * (R * 0.52 + 14), size: 8);
          }
        }
        canvas.drawLine(c - const Offset(14, 0), c + const Offset(14, 0), edge);
        canvas.drawLine(c - const Offset(0, 14), c + const Offset(0, 0), edge);
        break;
      case WbInstrumentKind.setSquare:
      case WbInstrumentKind.setSquare45:
        final isEq = kind == WbInstrumentKind.setSquare45;
        // dik üçgen: sol-alt dik açı. 30-60-90 için yatay kenar uzun
        final pw = s.width, ph = isEq ? s.height : s.height * 0.58;
        final tri = Path()
          ..moveTo(0, s.height)
          ..lineTo(pw, s.height)
          ..lineTo(0, s.height - ph)
          ..close();
        canvas.drawPath(tri, fill);
        canvas.drawPath(tri, edge);
        final inner = Path()
          ..moveTo(pw * 0.2, s.height - 12)
          ..lineTo(pw * (isEq ? 0.62 : 0.66), s.height - 12)
          ..lineTo(pw * 0.2, s.height - ph * (isEq ? 0.62 : 0.55))
          ..close();
        canvas.drawPath(inner, Paint()..color = const Color(0x22FFFFFF));
        canvas.drawPath(inner, edge);
        for (int mm = 0; mm <= 300; mm += 5) {
          final x = mm * 2.0;
          if (x > pw - 4) break;
          final isCm = mm % 10 == 0;
          canvas.drawLine(
            Offset(x, s.height),
            Offset(x, s.height - (isCm ? 14 : 7)),
            tick,
          );
          if (isCm && mm > 0 && mm % 20 == 0)
            label('${mm ~/ 10}', Offset(x, s.height - 24), size: 9);
        }
        for (int mm = 0; mm <= 300; mm += 5) {
          final y = s.height - mm * 2.0;
          if (y < s.height - ph + 4) break;
          final isCm = mm % 10 == 0;
          canvas.drawLine(Offset(0, y), Offset(isCm ? 14 : 7, y), tick);
          if (isCm && mm > 0 && mm % 20 == 0)
            label('${mm ~/ 10}', Offset(24, y), size: 9);
        }
        label(
          isEq ? '45°' : '30°-60°',
          Offset(pw * 0.62, s.height - 30),
          size: 11,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _InstrumentPainter old) => old.kind != kind;
}
