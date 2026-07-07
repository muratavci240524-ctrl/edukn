import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/user_permission_service.dart';

/// 🔐 Veri Şifreleme Yönetim Ekranı
/// Sadece super_admin görebilir.
/// Mevcut verileri AES-256 ile şifreler.
class DataEncryptionScreen extends StatefulWidget {
  const DataEncryptionScreen({Key? key}) : super(key: key);

  @override
  _DataEncryptionScreenState createState() => _DataEncryptionScreenState();
}

class _DataEncryptionScreenState extends State<DataEncryptionScreen> {
  bool _isLoadingStats = true;
  bool _isMigrating = false;
  Map<String, dynamic>? _stats;
  String? _institutionId;
  List<String> _logs = [];
  bool _migrationDone = false;
  List<Map<String, dynamic>> _schools = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await _loadSchools();
    if (_institutionId != null) {
      await _loadStats();
    } else {
      setState(() => _isLoadingStats = false);
    }
  }

  Future<void> _loadSchools() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('schools').get();
      setState(() {
        _schools = snapshot.docs.map((doc) => {
          'id': doc.id,
          'schoolName': doc.data()['schoolName'] ?? 'İsimsiz Okul',
          'institutionId': doc.data()['institutionId'] ?? '',
        }).toList();
        
        if (_schools.isNotEmpty && _institutionId == null) {
          _institutionId = _schools.first['institutionId'] as String?;
        }
      });
    } catch (e) {
      _addLog('❌ Okul listesi yüklenemedi: $e');
    }
  }

  Future<void> _loadStats() async {
    if (_institutionId == null) return;
    setState(() => _isLoadingStats = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('getEncryptionStats');
      final result = await callable.call({'institutionId': _institutionId});
      setState(() => _stats = Map<String, dynamic>.from(result.data['stats'] ?? {}));
    } catch (e) {
      _addLog('❌ İstatistik alınamadı: $e');
    } finally {
      setState(() => _isLoadingStats = false);
    }
  }

  void _addLog(String message) {
    setState(() => _logs.insert(0, '${DateTime.now().toString().substring(11, 19)} — $message'));
  }

  Future<void> _startMigration() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.security_rounded, color: Color(0xFF4F46E5)),
            const SizedBox(width: 8),
            Text('Şifreleme Başlatılsın mı?', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        content: Text(
          'Tüm öğrenci, kullanıcı ve veli kayıtlarındaki:\n'
          '• TC Kimlik Numaraları\n'
          '• Doğum Tarihleri\n'
          '• Telefon Numaraları\n\n'
          'AES-256 ile şifrelenecek. Bu işlem geri alınamaz.\n'
          'Sistem kullanımda olabilir, mevcut oturumlar etkilenmez.',
          style: GoogleFonts.inter(fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal', style: GoogleFonts.inter(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.lock_rounded, color: Colors.white, size: 18),
            label: Text('Şifrele', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isMigrating = true;
      _logs.clear();
    });
    _addLog('🚀 Migration başlatılıyor...');

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
        'migrateEncryptData',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 540)),
      );
      _addLog('🔐 Firebase Functions çağrılıyor...');
      final result = await callable.call({'institutionId': _institutionId});

      final results = result.data['results'] as Map<dynamic, dynamic>;
      for (final entry in results.entries) {
        final col = entry.key;
        final colStats = entry.value as Map<dynamic, dynamic>;
        _addLog('✅ $col: ${colStats['encrypted']} şifrelendi, ${colStats['skipped']} zaten şifreli.');
      }
      _addLog('🎉 Migration başarıyla tamamlandı!');
      setState(() => _migrationDone = true);
      await _loadStats(); // Güncel istatistikleri al
    } catch (e) {
      _addLog('❌ Migration hatası: $e');
    } finally {
      setState(() => _isMigrating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Veri Şifreleme Yönetimi', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(
            onPressed: _loadStats,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'İstatistikleri Yenile',
          ),
        ],
      ),
      body: _isLoadingStats
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSchoolSelector(),
                  const SizedBox(height: 20),
                  _buildStatusCard(),
                  const SizedBox(height: 20),
                  _buildStatsGrid(),
                  const SizedBox(height: 20),
                  _buildMigrateButton(),
                  if (_logs.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildLogsCard(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    final allEncrypted = _stats?.values.every((v) {
      final m = v as Map<dynamic, dynamic>;
      return (m['plain'] as int? ?? 0) == 0;
    }) ?? false;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: allEncrypted
              ? [const Color(0xFF059669), const Color(0xFF10B981)]
              : [const Color(0xFF4F46E5), const Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (allEncrypted ? const Color(0xFF059669) : const Color(0xFF4F46E5)).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              allEncrypted ? Icons.verified_rounded : Icons.security_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allEncrypted ? '✅ Tüm Veriler Şifreli' : '🔓 Şifrelenmemiş Veriler Mevcut',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 17, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  allEncrypted
                      ? 'Tüm hassas veriler AES-256 ile korunuyor.'
                      : 'Aşağıdaki butonu kullanarak tüm verileri şifreleyin.',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withOpacity(0.85)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    final collections = {
      'students': ('👨‍🎓 Öğrenciler', Icons.school_rounded),
      'users': ('👤 Kullanıcılar', Icons.manage_accounts_rounded),
      'parents': ('👨‍👩‍👧 Veliler', Icons.family_restroom_rounded),
    };

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.4,
      ),
      itemCount: collections.length,
      itemBuilder: (context, index) {
        final key = collections.keys.elementAt(index);
        final (label, icon) = collections.values.elementAt(index);
        final data = _stats?[key] as Map<dynamic, dynamic>? ?? {};
        final total = data['total'] as int? ?? 0;
        final encrypted = data['encrypted'] as int? ?? 0;
        final plain = data['plain'] as int? ?? 0;
        final percent = total > 0 ? (encrypted / total * 100).round() : 0;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: const Color(0xFF4F46E5)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: const Color(0xFF1E293B)))),
                ],
              ),
              const Spacer(),
              Text('$percent%', style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w900, color: percent == 100 ? const Color(0xFF059669) : const Color(0xFF4F46E5))),
              const SizedBox(height: 2),
              Text('Şifreli: $encrypted / $total', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
              if (plain > 0)
                Text('Şifresiz: $plain', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFDC2626), fontWeight: FontWeight.w600)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMigrateButton() {
    final allDone = _stats?.values.every((v) {
      final m = v as Map<dynamic, dynamic>;
      return (m['plain'] as int? ?? 0) == 0;
    }) ?? false;

    if (allDone && !_isMigrating) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF86EFAC)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF059669)),
            const SizedBox(width: 12),
            Text('Tüm veriler zaten şifreli!', style: GoogleFonts.inter(color: const Color(0xFF059669), fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isMigrating ? null : _startMigration,
        icon: _isMigrating
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.lock_rounded, color: Colors.white),
        label: Text(
          _isMigrating ? 'Şifreleniyor... Lütfen bekleyin' : '🔐 Mevcut Tüm Verileri Şifrele',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 15),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4F46E5),
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 4,
        ),
      ),
    );
  }

  Widget _buildLogsCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal_rounded, color: Color(0xFF94A3B8), size: 16),
              const SizedBox(width: 8),
              Text('İşlem Günlüğü', style: GoogleFonts.firaCode(color: const Color(0xFF94A3B8), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          ...(_logs.take(15).map((log) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(log, style: GoogleFonts.firaCode(color: const Color(0xFF4ADE80), fontSize: 12)),
          ))),
        ],
      ),
    );
  }

  Widget _buildSchoolSelector() {
    if (_schools.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🏫 Şifrelenecek Kurumu Seçin',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _institutionId,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF1F5F9),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            items: _schools.map((school) {
              return DropdownMenuItem<String>(
                value: school['institutionId'] as String,
                child: Text(
                  '${school['schoolName']} (${school['institutionId']})',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _institutionId = val;
                });
                _loadStats();
              }
            },
          ),
        ],
      ),
    );
  }
}
