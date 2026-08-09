import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'duty_settings_screen.dart';
import 'duty_program_detail_screen.dart';

class DutyManagementScreen extends StatefulWidget {
  final String institutionId;

  const DutyManagementScreen({Key? key, required this.institutionId})
    : super(key: key);

  @override
  State<DutyManagementScreen> createState() => _DutyManagementScreenState();
}

class _DutyManagementScreenState extends State<DutyManagementScreen> {
  static const _prefKey = 'duty_scope_mode';

  String _scopeMode = 'alt_donem';
  bool _ready = false;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _fastLoad();
  }

  /// 1. Local cache'ten scope modu an+ında oku
  /// 2. Firestore'dan scope + liste paralel çek
  Future<void> _fastLoad() async {
    // A. SharedPreferences'ten anında oku (0ms gecikme)
    final prefs = await SharedPreferences.getInstance();
    final cachedMode = prefs.getString(_prefKey) ?? 'alt_donem';
    if (mounted) setState(() => _scopeMode = cachedMode);

    // B. Firestore'dan paralel çek: scope ayarı + aktif dönem listesi
    final results = await Future.wait([
      _fetchScopeMode(),   // [0]
      _fetchList(cachedMode), // [1]
    ]);

    final serverMode = results[0] as String;
    var items = results[1] as List<Map<String, dynamic>>;

    // Eğer server'daki mod farklıysa, listeyi yeniden çek
    if (serverMode != cachedMode) {
      items = await _fetchList(serverMode);
      await prefs.setString(_prefKey, serverMode);
    }

    if (!mounted) return;
    setState(() {
      _scopeMode = serverMode;
      _items = items;
      _ready = true;
    });
  }

  Future<String> _fetchScopeMode() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('dutyGlobalSettings')
          .doc(widget.institutionId)
          .get();
      return doc.data()?['scopeMode'] as String? ?? 'alt_donem';
    } catch (_) {
      return 'alt_donem';
    }
  }

  Future<List<Map<String, dynamic>>> _fetchList(String mode) async {
    try {
      if (mode == 'alt_donem') {
        final snap = await FirebaseFirestore.instance
            .collection('workPeriods')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('isActive', isEqualTo: true)
            .get();
        final docs = snap.docs.map((d) {
          final data = Map<String, dynamic>.from(d.data());
          data['id'] = d.id;
          return data;
        }).toList();
        docs.sort((a, b) {
          final da = (a['startDate'] as Timestamp).toDate();
          final db = (b['startDate'] as Timestamp).toDate();
          return db.compareTo(da);
        });
        return docs;
      } else {
        final snap = await FirebaseFirestore.instance
            .collection('terms')
            .where('institutionId', isEqualTo: widget.institutionId)
            .get();
        final docs = snap.docs.map((d) {
          final data = Map<String, dynamic>.from(d.data());
          data['id'] = d.id;
          return data;
        }).toList();
        docs.sort((a, b) {
          final aYear = (a['startYear'] ?? 0) as int;
          final bYear = (b['startYear'] ?? 0) as int;
          if (aYear != bYear) return bYear.compareTo(aYear);
          final aOrder = (a['order'] ?? a['termOrder'] ?? 0) as int;
          final bOrder = (b['order'] ?? b['termOrder'] ?? 0) as int;
          return bOrder.compareTo(aOrder);
        });
        return docs;
      }
    } catch (_) {
      return [];
    }
  }


  Future<void> _switchScope(String mode) async {
    Navigator.pop(context);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, mode);
    await FirebaseFirestore.instance
        .collection('dutyGlobalSettings')
        .doc(widget.institutionId)
        .set({'scopeMode': mode, 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));

    if (!mounted) return;
    final items = await _fetchList(mode);
    if (!mounted) return;
    setState(() {
      _scopeMode = mode;
      _items = items;
    });
  }

  Future<void> _refresh() async {
    final items = await _fetchList(_scopeMode);
    if (!mounted) return;
    setState(() => _items = items);
  }

  void _showScopePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Nöbet Kapsam Modu',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Nöbet çizelgelerini hangi dönem yapısına göre yönetmek istiyorsunuz?',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            _ScopeOption(
              mode: 'alt_donem',
              selected: _scopeMode,
              icon: Icons.calendar_view_week,
              title: 'Alt Dönem',
              subtitle: 'Çalışma takvimindeki dönemlere göre',
              color: const Color(0xFF4F46E5),
              onTap: _switchScope,
            ),
            const SizedBox(height: 10),
            _ScopeOption(
              mode: 'donem',
              selected: _scopeMode,
              icon: Icons.school_outlined,
              title: 'Dönem',
              subtitle: '1. Dönem, 2. Dönem gibi yıllık dönemlere göre',
              color: const Color(0xFF0891B2),
              onTap: _switchScope,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nöbet Çizelgeleri',
              style: TextStyle(
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              _scopeMode == 'alt_donem' ? 'Alt Dönem Modu' : 'Dönem Modu',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 11,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF64748B)),
            tooltip: 'Yenile',
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: Color(0xFF4F46E5)),
            tooltip: 'Kapsam Modu',
            onPressed: _showScopePicker,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _buildEmpty()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return _scopeMode == 'alt_donem'
                        ? _buildWorkPeriodCard(item)
                        : _buildTermCard(item);
                  },
                ),
    );
  }

  Widget _buildWorkPeriodCard(Map<String, dynamic> data) {
    final periodId = data['id'] as String;
    final name = data['periodName'] ?? 'İsimsiz Dönem';
    final start = (data['startDate'] as Timestamp).toDate();
    final end = (data['endDate'] as Timestamp).toDate();
    final df = DateFormat('dd.MM.yyyy');
    return _buildCard(
      id: periodId,
      name: name,
      subtitle: '${df.format(start)} - ${df.format(end)}',
      icon: Icons.calendar_view_week,
      color: const Color(0xFF4F46E5),
      scopeType: 'alt_donem',
    );
  }

  Widget _buildTermCard(Map<String, dynamic> data) {
    final termId = data['id'] as String;
    final name = data['name'] ?? data['termName'] ?? 'İsimsiz Dönem';
    final isActive = data['isActive'] == true;
    final startYear = data['startYear']?.toString() ?? '';
    final endYear = data['endYear']?.toString() ?? '';
    final subtitle = (startYear.isNotEmpty && endYear.isNotEmpty)
        ? '$startYear - $endYear'
        : (data['description']?.toString() ?? '');
    return _buildCard(
      id: termId,
      name: name,
      subtitle: subtitle,
      icon: Icons.school_outlined,
      color: const Color(0xFF0891B2),
      scopeType: 'donem',
      badge: isActive ? 'Aktif' : null,
      badgeColor: const Color(0xFF16A34A),
    );
  }

  Widget _buildCard({
    required String id,
    required String name,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String scopeType,
    String? badge,
    Color? badgeColor,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      shadowColor: color.withOpacity(0.15),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DutyProgramDetailScreen(
              periodId: id,
              periodName: name,
              institutionId: widget.institutionId,
              scopeType: scopeType,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFF1E293B),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: (badgeColor ?? Colors.green).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: badgeColor ?? Colors.green,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final isAltDonem = _scopeMode == 'alt_donem';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isAltDonem ? Icons.calendar_view_week : Icons.school_outlined,
            size: 64, color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            isAltDonem ? 'Aktif çalışma dönemi bulunamadı.'
                       : 'Henüz dönem tanımlanmamış.',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            isAltDonem ? 'Çalışma Takvimi ekranından dönem oluşturunuz.'
                       : 'Dönem Yönetimi ekranından dönem oluşturunuz.',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Scope Seçenek Widget'ı ────────────────────────────────────────
class _ScopeOption extends StatelessWidget {
  final String mode;
  final String selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Function(String) onTap;

  const _ScopeOption({
    required this.mode,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == mode;
    return GestureDetector(
      onTap: () => onTap(mode),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: isSelected ? color.withOpacity(0.12) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon,
                  color: isSelected ? color : Colors.grey.shade500, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: isSelected ? color : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, color: color, size: 22),
          ],
        ),
      ),
    );
  }
}
