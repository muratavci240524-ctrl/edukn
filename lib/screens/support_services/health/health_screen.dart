import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edukn/services/user_permission_service.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/crypto_service.dart';
import '../../../services/student_movement_service.dart';

class HealthScreen extends StatefulWidget {
  final String? fixedSchoolTypeId;
  final String? fixedSchoolTypeName;
  final bool isStandalonePortal;

  const HealthScreen({
    Key? key,
    this.fixedSchoolTypeId,
    this.fixedSchoolTypeName,
    this.isStandalonePortal = false,
  }) : super(key: key);

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen>
    with SingleTickerProviderStateMixin {
  String? _institutionId;
  String? _schoolDocId;
  String? _schoolName;
  String _currentStaffName = 'Revir Görevlisi';
  bool _isLoading = true;
  late TabController _tabController;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _visitsSub;
  List<Map<String, dynamic>> _visits = [];
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _visitsSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final email = user.email ?? '';
      final userData = await UserPermissionService.loadUserData();
      _currentStaffName = (userData?['fullName'] ??
              userData?['name'] ??
              user.displayName ??
              email.split('@').first)
          .toString()
          .trim();
      if (_currentStaffName.isEmpty) _currentStaffName = 'Revir Görevlisi';

      _institutionId = (userData?['institutionId']?.toString().trim().isNotEmpty == true)
          ? userData!['institutionId'].toString().trim()
          : await UserPermissionService.resolveInstitutionId(email);

      if (_institutionId != null && _institutionId!.isNotEmpty) {
        _schoolDocId =
            await StudentMovementService().resolveSchoolDocId(_institutionId!);
        if (_schoolDocId != null && _schoolDocId!.isNotEmpty) {
          try {
            final sDoc = await FirebaseFirestore.instance
                .collection('schools')
                .doc(_schoolDocId)
                .get();
            if (sDoc.exists) {
              final sd = sDoc.data() ?? {};
              final raw =
                  (sd['schoolName'] ?? sd['name'] ?? '').toString().trim();
              if (raw.isNotEmpty) _schoolName = raw;
            }
          } catch (_) {}
        }
      }

      _subscribeVisits();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeVisits() {
    _visitsSub?.cancel();
    if (_schoolDocId == null || _schoolDocId!.isEmpty) return;

    final startOfDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final query = FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('healthVisits')
        .where(
          'visitDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where('visitDate', isLessThan: Timestamp.fromDate(endOfDay))
        .orderBy('visitDate', descending: true);

    _visitsSub = query.snapshots().listen(
      (snap) {
        if (!mounted) return;
        final parsed = <Map<String, dynamic>>[];
        for (final d in snap.docs) {
          final data = Map<String, dynamic>.from(d.data());
          if (widget.fixedSchoolTypeId != null &&
              widget.fixedSchoolTypeId!.isNotEmpty) {
            final docType = data['schoolTypeId']?.toString();
            if (docType != null &&
                docType.isNotEmpty &&
                docType != widget.fixedSchoolTypeId) {
              continue;
            }
          }
          data['id'] = d.id;
          data['complaint'] = CryptoService.decrypt(
            data['complaint']?.toString() ?? '',
            institutionId: _institutionId,
          );
          data['treatment'] = CryptoService.decrypt(
            data['treatment']?.toString() ?? '',
            institutionId: _institutionId,
          );
          data['medicationName'] = CryptoService.decrypt(
            data['medicationName']?.toString() ?? '',
            institutionId: _institutionId,
          );
          data['notes'] = CryptoService.decrypt(
            data['notes']?.toString() ?? '',
            institutionId: _institutionId,
          );
          parsed.add(data);
        }

        // Açık sevk dosyalarını her zaman en üstte göster
        parsed.sort((a, b) {
          final aOpen = (a['visitStatus']?.toString() ?? '') == 'open';
          final bOpen = (b['visitStatus']?.toString() ?? '') == 'open';
          if (aOpen != bOpen) return aOpen ? -1 : 1;
          final aTime = (a['visitDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
          final bTime = (b['visitDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
          return bTime.compareTo(aTime);
        });

        setState(() {
          _visits = parsed;
        });
      },
      onError: (e) {
        debugPrint('[HealthScreen] healthVisits stream error: $e');
      },
    );
  }

  Future<void> _completeOpenVisit(Map<String, dynamic> visit) async {
    final visitId = visit['id']?.toString() ?? '';
    final movementId =
        (visit['referralMovementId'] ?? visit['movementId'] ?? '').toString();
    final studentName = visit['studentName']?.toString() ?? 'Öğrenci';
    final existingTreatment = visit['treatment']?.toString() ?? '';
    final existingMed = visit['medicationName']?.toString() ?? '';
    final existingNotes = visit['notes']?.toString() ?? '';

    final treatmentCtrl = TextEditingController(text: existingTreatment);
    final medicationCtrl = TextEditingController(text: existingMed);
    final notesCtrl = TextEditingController(text: existingNotes);
    bool medicationGiven = visit['medicationGiven'] == true;
    String selectedOutcome = 'Dinlendi, Derse Döndü';

    const presetInterventions = [
      'Ateş ve tansiyon ölçümü yapıldı',
      'Buz uygulaması yapıldı',
      'Pansuman / yara bakımı uygulandı',
      'Revirde gözlem altında dinlendirildi',
      'Veli ile telefon görüşmesi sağlandı',
    ];

    const outcomes = [
      'Dinlendi, Derse Döndü',
      'Gözlem Tamamlandı, Derse Döndü',
      'Veli Bilgisiyle Eve Gönderildi',
      'Sağlık Kuruluşuna Sevk Edildi',
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.medical_services_rounded, color: Colors.red),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Açık Revir Dosyasına İşlem Gir',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      studentName,
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sevk Şikayeti: ${visit['complaint'] ?? '-'}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if ((visit['referredByName'] ?? '').toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Sevk Eden: ${visit['referredByName']}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Hızlı Müdahale Şablonları:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: presetInterventions.map((preset) {
                      return ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(preset, style: const TextStyle(fontSize: 11.5)),
                        onPressed: () {
                          final cur = treatmentCtrl.text.trim();
                          treatmentCtrl.text = cur.isEmpty ? preset : '$cur, $preset';
                          setDialogState(() {});
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: treatmentCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Yapılan Sağlık Müdahalesi *',
                      prefixIcon: Icon(Icons.healing_rounded),
                      hintText: 'Ne yapıldığını detaylı yazınız...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'İlaç / Medikal Ürün Verildi mi?',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    value: medicationGiven,
                    activeThumbColor: Colors.red,
                    onChanged: (val) => setDialogState(() => medicationGiven = val),
                  ),
                  if (medicationGiven) ...[
                    TextField(
                      controller: medicationCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Verilen İlaç / Ürün Adı',
                        prefixIcon: Icon(Icons.medication_rounded),
                        hintText: 'Örn: Parol 500mg, Serum fizyolojik',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: selectedOutcome,
                    decoration: const InputDecoration(
                      labelText: 'Sonuç / Yönlendirme Kararı',
                      prefixIcon: Icon(Icons.assignment_turned_in_rounded),
                      border: OutlineInputBorder(),
                    ),
                    items: outcomes
                        .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedOutcome = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ek Revir Notu (Veli ve Öğretmene İletilir)',
                      prefixIcon: Icon(Icons.note_alt_outlined),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.notifications_active_rounded,
                            size: 18, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tamamladığınızda yapılan işlem; Veliye, revire yönlendirene ve ders saatindeyse ilgili ders öğretmenine otomatik bildirilecektir.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                if (treatmentCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Lütfen yapılan müdahaleyi yazınız.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Tamamla ve Bildirim Gönder'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || _schoolDocId == null) return;

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

      if (_institutionId != null && _institutionId!.isNotEmpty && visitId.isNotEmpty) {
        await StudentMovementService().completeInfirmaryVisit(
          institutionId: _institutionId!,
          schoolDocId: _schoolDocId!,
          healthVisitId: visitId,
          movementId: movementId.isNotEmpty ? movementId : null,
          treatment: treatmentCtrl.text.trim(),
          medicationGiven: medicationGiven,
          medicationName: medicationGiven ? medicationCtrl.text.trim() : '',
          outcome: selectedOutcome,
          notes: notesCtrl.text.trim(),
        );
      } else {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(_schoolDocId)
            .collection('healthVisits')
            .doc(visitId)
            .update({
          'visitStatus': 'completed',
          'treatment': CryptoService.encrypt(
            treatmentCtrl.text.trim(),
            institutionId: _institutionId,
          ),
          'medicationGiven': medicationGiven,
          'medicationName': CryptoService.encrypt(
            medicationGiven ? medicationCtrl.text.trim() : '',
            institutionId: _institutionId,
          ),
          'notes': CryptoService.encrypt(
            notesCtrl.text.trim(),
            institutionId: _institutionId,
          ),
          'outcome': selectedOutcome,
          'handledByUid': uid,
          'handledByName': _currentStaffName,
          'completedAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✓ Revir dosyası tamamlandı; Veli, yönlendiren ve ders öğretmeni bilgilendirildi.',
            ),
            backgroundColor: Color(0xFF059669),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İşlem tamamlanırken hata oluştu: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _addVisit() async {
    final studentNameCtrl = TextEditingController();
    final complaintCtrl = TextEditingController();
    final treatmentCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool medicationGiven = false;
    String? medicationName;
    final medicationCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.local_hospital, color: Colors.red),
              SizedBox(width: 8),
              Text('Yeni Revir Ziyareti'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: studentNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Öğrenci Adı Soyadı *',
                    prefixIcon: Icon(Icons.person),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: complaintCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Şikayeti *',
                    prefixIcon: Icon(Icons.sick),
                    hintText: 'Örn: Baş ağrısı, karın ağrısı',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: treatmentCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Yapılan Müdahale',
                    prefixIcon: Icon(Icons.medical_services),
                    hintText: 'Örn: Ateş ölçümü, pansuman',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('İlaç Verildi mi?'),
                  value: medicationGiven,
                  activeThumbColor: Colors.red,
                  onChanged: (val) {
                    setDialogState(() => medicationGiven = val);
                  },
                ),
                if (medicationGiven) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: medicationCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Verilen İlaç',
                      prefixIcon: Icon(Icons.medication),
                      hintText: 'Örn: Parol 500mg',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notlar',
                    prefixIcon: Icon(Icons.note),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                medicationName = medicationCtrl.text.trim();
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    if (studentNameCtrl.text.trim().isEmpty ||
        complaintCtrl.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Öğrenci adı ve şikayet zorunludur!'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('healthVisits')
        .add({
          'studentName': studentNameCtrl.text.trim(),
          'complaint': CryptoService.encrypt(
            complaintCtrl.text.trim(),
            institutionId: _institutionId,
          ),
          'treatment': CryptoService.encrypt(
            treatmentCtrl.text.trim(),
            institutionId: _institutionId,
          ),
          'medicationGiven': medicationGiven,
          'medicationName': CryptoService.encrypt(
            medicationGiven ? (medicationName ?? '') : '',
            institutionId: _institutionId,
          ),
          'notes': CryptoService.encrypt(
            notesCtrl.text.trim(),
            institutionId: _institutionId,
          ),
          'visitStatus': 'completed',
          'visitDate': Timestamp.fromDate(DateTime.now()),
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': FirebaseAuth.instance.currentUser?.email ?? '',
          'handledByName': _currentStaffName,
          if (widget.fixedSchoolTypeId != null)
            'schoolTypeId': widget.fixedSchoolTypeId,
        });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Ziyaret kaydedildi'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _deleteVisit(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ziyaret Sil'),
        content: const Text('Bu ziyaret kaydını silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('healthVisits')
        .doc(id)
        .delete();
  }

  Future<void> _changeDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('tr', 'TR'),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
      _subscribeVisits();
    }
  }

  @override
  Widget build(BuildContext context) {
    final standalone =
        widget.isStandalonePortal || !Navigator.of(context).canPop();

    if (_isLoading) {
      return Scaffold(
        appBar: EduknAppBar(
          title: 'Sağlık İşlemleri (Revir)',
          showBackButton: !standalone,
          actions: standalone ? _buildStandaloneActions() : null,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final openCount =
        _visits.where((v) => v['visitStatus']?.toString() == 'open').length;

    return Scaffold(
      appBar: EduknAppBar(
        title: 'Sağlık İşlemleri (Revir)',
        subtitle: widget.fixedSchoolTypeName ?? _schoolName,
        showBackButton: !standalone,
        actions: standalone ? _buildStandaloneActions() : null,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.red,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.red,
          tabs: [
            Tab(
              icon: Badge(
                isLabelVisible: openCount > 0,
                label: Text('$openCount'),
                child: const Icon(Icons.local_hospital),
              ),
              text: 'Revir Ziyaretleri',
            ),
            const Tab(icon: Icon(Icons.bar_chart), text: 'İstatistikler'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addVisit,
        icon: const Icon(Icons.add),
        label: const Text('Ziyaret Ekle'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildVisitsList(openCount), _buildStatistics()],
      ),
    );
  }

  Widget _buildVisitsList(int openCount) {
    final dateStr = DateFormat('dd MMMM yyyy', 'tr_TR').format(_selectedDate);

    return Column(
      children: [
        // Date selector
        Container(
          color: Colors.red.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(
                    () => _selectedDate = _selectedDate.subtract(
                      const Duration(days: 1),
                    ),
                  );
                  _subscribeVisits();
                },
              ),
              Expanded(
                child: InkWell(
                  onTap: _changeDate,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today, size: 18, color: Colors.red),
                        const SizedBox(width: 8),
                        Text(
                          dateStr,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.red.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(
                    () => _selectedDate = _selectedDate.add(const Duration(days: 1)),
                  );
                  _subscribeVisits();
                },
              ),
            ],
          ),
        ),
        // Açık sevk dosyası canlı bilgi şeridi
        if (openCount > 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.amber.shade100,
            child: Row(
              children: [
                Icon(Icons.notification_important_rounded,
                    color: Colors.red.shade800, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Açık Revir Dosyası: $openCount öğrenci revir kağıdı ile sevk edildi ve işlem bekliyor.',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.red.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Visit count
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            children: [
              const Icon(Icons.people, color: Colors.red),
              const SizedBox(width: 8),
              Text(
                'Toplam ${_visits.length} kayıt${openCount > 0 ? ' ($openCount açık sevk dosyası)' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Visit list
        Expanded(
          child: _visits.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.health_and_safety,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Bu tarihte ziyaret kaydı yok',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                      itemCount: _visits.length,
                      itemBuilder: (context, index) {
                        final visit = _visits[index];
                        final isOpen =
                            visit['visitStatus']?.toString() == 'open';
                        final time = (visit['visitDate'] as Timestamp?)?.toDate();
                        final timeStr = time != null
                            ? DateFormat('HH:mm').format(time)
                            : '';
                        final className = visit['className']?.toString() ?? '';
                        final studentNo = visit['studentNo']?.toString() ?? '';
                        final referredByName =
                            visit['referredByName']?.toString() ?? '';
                        final priority =
                            (visit['urgency'] ?? visit['priority'] ?? '')
                                .toString();
                        final activeLessonName =
                            (visit['lessonName'] ??
                                    visit['activeLessonName'] ??
                                    '')
                                .toString();
                        final activeLessonHour =
                            visit['lessonHour'] ?? visit['activeLessonHour'];
                        final outcome = visit['outcome']?.toString() ?? '';
                        final handledByName =
                            visit['handledByName']?.toString() ?? '';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: isOpen ? 3 : 1,
                          color: isOpen ? const Color(0xFFFFFBEB) : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: isOpen
                                  ? Colors.red.shade400
                                  : Colors.grey.shade200,
                              width: isOpen ? 1.6 : 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isOpen)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade700,
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.folder_open_rounded,
                                                  size: 14, color: Colors.white),
                                              SizedBox(width: 5),
                                              Text(
                                                'AÇIK REVİR DOSYASI • İŞLEM BEKLİYOR',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (priority.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: priority == 'Acil'
                                                  ? Colors.red.shade100
                                                  : Colors.orange.shade100,
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              'Öncelik: $priority',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: priority == 'Acil'
                                                    ? Colors.red.shade900
                                                    : Colors.orange.shade900,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: isOpen
                                          ? Colors.red.shade600
                                          : Colors.red.shade100,
                                      child: Icon(
                                        isOpen
                                            ? Icons.medical_information_rounded
                                            : Icons.person,
                                        color: isOpen ? Colors.white : Colors.red,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            visit['studentName'] ?? '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                          Text(
                                            [
                                              if (className.isNotEmpty)
                                                'Sınıf: $className',
                                              if (studentNo.isNotEmpty)
                                                'No: $studentNo',
                                              if (timeStr.isNotEmpty)
                                                'Saat: $timeStr',
                                            ].join(' • '),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!isOpen && outcome.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: Colors.green.shade200,
                                          ),
                                        ),
                                        child: Text(
                                          'Tamamlandı',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.green.shade800,
                                          ),
                                        ),
                                      ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_outline,
                                        color: Colors.red.shade300,
                                      ),
                                      onPressed: () =>
                                          _deleteVisit(visit['id']),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (referredByName.isNotEmpty)
                                  _buildInfoRow(
                                    Icons.badge_outlined,
                                    'Revire Yönlendiren',
                                    activeLessonName.isNotEmpty
                                        ? '$referredByName (${activeLessonHour != null ? '$activeLessonHour. Ders - ' : ''}$activeLessonName)'
                                        : referredByName,
                                    color: Colors.indigo,
                                  ),
                                _buildInfoRow(
                                  Icons.sick,
                                  'Şikayet',
                                  (visit['complaint']?.toString().isNotEmpty == true)
                                      ? visit['complaint']
                                      : '-',
                                ),
                                if (visit['treatment'] != null &&
                                    (visit['treatment'] as String).isNotEmpty)
                                  _buildInfoRow(
                                    Icons.medical_services,
                                    'Müdahale',
                                    visit['treatment'],
                                    color: Colors.teal.shade700,
                                  ),
                                if (visit['medicationGiven'] == true)
                                  _buildInfoRow(
                                    Icons.medication,
                                    'İlaç',
                                    visit['medicationName']?.isNotEmpty == true
                                        ? visit['medicationName']
                                        : 'Verildi',
                                    color: Colors.orange.shade800,
                                  ),
                                if (outcome.isNotEmpty)
                                  _buildInfoRow(
                                    Icons.check_circle_outline,
                                    'Sonuç',
                                    handledByName.isNotEmpty
                                        ? '$outcome (İşlemi Yapan: $handledByName)'
                                        : outcome,
                                    color: Colors.green.shade700,
                                  ),
                                if (visit['notes'] != null &&
                                    (visit['notes'] as String).isNotEmpty)
                                  _buildInfoRow(
                                    Icons.note,
                                    'Not',
                                    visit['notes'],
                                  ),
                                if (isOpen) ...[
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _completeOpenVisit(visit),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red.shade700,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                          horizontal: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                      icon: const Icon(Icons.edit_note_rounded),
                                      label: const Text(
                                        'Müdahale Yaz & Dosyayı Tamamla (Veli / Öğretmen / Sevk Edene Bildir)',
                                        style: TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color ?? Colors.grey),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color ?? Colors.grey.shade700,
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildStatistics() {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolDocId)
          .collection('healthVisits')
          .orderBy('visitDate', descending: true)
          .limit(500)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        final totalVisits = docs.length;
        final medicationCount = docs
            .where((d) => (d.data() as Map<String, dynamic>)['medicationGiven'] == true)
            .length;

        // Group by complaint
        final complaintMap = <String, int>{};
        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final rawComplaint = data['complaint']?.toString() ?? '';
          final decrypted = CryptoService.decrypt(
            rawComplaint,
            institutionId: _institutionId,
          );
          final complaint = decrypted.isNotEmpty ? decrypted : 'Diğer';
          complaintMap[complaint] = (complaintMap[complaint] ?? 0) + 1;
        }
        final sortedComplaints = complaintMap.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        // Group by student
        final studentMap = <String, int>{};
        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final name = data['studentName'] as String? ?? 'Bilinmeyen';
          studentMap[name] = (studentMap[name] ?? 0) + 1;
        }
        final frequentVisitors = studentMap.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Toplam Ziyaret',
                          '$totalVisits',
                          Icons.local_hospital,
                          Colors.red,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'İlaç Verilen',
                          '$medicationCount',
                          Icons.medication,
                          Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'En Sık Şikayetler',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...sortedComplaints
                      .take(10)
                      .map(
                        (e) => ListTile(
                          dense: true,
                          leading: Icon(Icons.sick, color: Colors.red.shade300),
                          title: Text(e.key),
                          trailing: Chip(
                            label: Text('${e.value}'),
                            backgroundColor: Colors.red.shade50,
                          ),
                        ),
                      ),
                  const SizedBox(height: 24),
                  const Text(
                    'Sık Ziyaret Eden Öğrenciler',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...frequentVisitors
                      .take(10)
                      .map(
                        (e) => ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.red.shade100,
                            child: Text(
                              e.key.isNotEmpty ? e.key[0] : '?',
                              style: const TextStyle(fontSize: 12, color: Colors.red),
                            ),
                          ),
                          title: Text(e.key),
                          trailing: Chip(
                            label: Text('${e.value} ziyaret'),
                            backgroundColor: Colors.red.shade50,
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStandaloneActions() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final impersonating = UserPermissionService.isImpersonating();

    return [
      if (impersonating)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: TextButton.icon(
            onPressed: _exitImpersonation,
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFFFF7ED),
              foregroundColor: const Color(0xFFC2410C),
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 8 : 12,
                vertical: 6,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xFFFDBA74)),
              ),
            ),
            icon: const Icon(Icons.admin_panel_settings_rounded, size: 16),
            label: Text(
              isMobile ? 'Yöneticiye Dön' : 'Yönetici Hesabına Dön',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      PopupMenuButton<String>(
        tooltip: 'Hesap ve Oturum İşlemleri',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onSelected: (val) {
          if (val == 'profile') {
            Navigator.pushNamed(context, '/profile-settings');
          } else if (val == 'exit_imp') {
            _exitImpersonation();
          } else if (val == 'logout') {
            _confirmStandaloneLogout();
          }
        },
        itemBuilder: (ctx) => [
          PopupMenuItem<String>(
            enabled: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentStaffName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Sağlık (Revir) Portalı',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'profile',
            child: Row(
              children: [
                Icon(Icons.person_outline_rounded, size: 18, color: Color(0xFF334155)),
                SizedBox(width: 10),
                Text('Profil ve Şifre Ayarları', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          if (impersonating)
            const PopupMenuItem<String>(
              value: 'exit_imp',
              child: Row(
                children: [
                  Icon(Icons.undo_rounded, size: 18, color: Color(0xFFC2410C)),
                  SizedBox(width: 10),
                  Text(
                    'Yönetici Hesabına Dön',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFC2410C),
                    ),
                  ),
                ],
              ),
            ),
          const PopupMenuItem<String>(
            value: 'logout',
            child: Row(
              children: [
                Icon(Icons.logout_rounded, size: 18, color: Color(0xFFDC2626)),
                SizedBox(width: 10),
                Text(
                  'Güvenli Çıkış Yap',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          ),
        ],
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 8 : 11,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.medical_services_rounded, size: 16, color: Color(0xFFDC2626)),
              if (!isMobile) ...[
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    _currentStaffName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF991B1B),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFFDC2626)),
            ],
          ),
        ),
      ),
    ];
  }

  Future<void> _exitImpersonation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_impersonating');
    await prefs.remove('impersonated_user_id');
    await prefs.remove('impersonated_user_email');
    await prefs.remove('impersonated_user_name');
    await prefs.setString('active_portal', 'manager');
    UserPermissionService.clearCache();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/school-dashboard', (_) => false);
  }

  Future<void> _confirmStandaloneLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 10),
            Text('Çıkış Yap', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Text('Sağlık (Revir) oturumunuzu kapatmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_portal');
    await prefs.remove('is_impersonating');
    await prefs.remove('impersonated_user_id');
    await prefs.remove('impersonated_user_email');
    await prefs.remove('impersonated_user_name');
    UserPermissionService.clearCache();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/school-login', (_) => false);
  }
}
