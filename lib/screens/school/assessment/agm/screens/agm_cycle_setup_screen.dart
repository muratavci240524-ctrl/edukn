import 'dart:convert';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/agm_time_slot_model.dart';
import '../repository/agm_repository.dart';
import '../services/agm_service.dart';
import '../../../classroom_management_screen.dart';

/// AGM Cycle Kurulum Ekranı – 3 adımlı wizard
/// 1. Ayarlar  (sınav, tarih, soft kısıtlar)
/// 2. Saat Dilimleri  (gün/saat + ders seçimi + öğretmen atama)
/// 3. Özet & Oluştur
import '../models/agm_cycle_model.dart';
import '../models/agm_group_model.dart';

class AgmCycleSetupScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String? schoolTypeName;
  final AgmCycle? initialCycle;

  const AgmCycleSetupScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    this.schoolTypeName,
    this.initialCycle,
  }) : super(key: key);

  @override
  State<AgmCycleSetupScreen> createState() => _AgmCycleSetupScreenState();
}

class _AgmCycleSetupScreenState extends State<AgmCycleSetupScreen>
    with SingleTickerProviderStateMixin {
  final _service = AgmService();
  final _repo = AgmRepository();
  final _db = FirebaseFirestore.instance;
  late TabController _tabController;

  // ── Cycle Başlığı ───────────────────────────────────────
  final _titleController = TextEditingController();
  final _examSearchController = TextEditingController();

  // ── Sınavlar ───────────────────────────────────────────
  List<String> _selectedExamIds = [];
  List<String> _selectedExamNames = [];
  List<Map<String, dynamic>> _exams = [];
  Map<String, String> _examDersler = {};

  // ── Tarih ──────────────────────────────────────────────
  DateTime _baslangic = DateTime.now();
  DateTime _bitis = DateTime.now().add(const Duration(days: 6));

  // ── Soft kısıtlar ──────────────────────────────────────
  int? _maxSaat;
  int? _minDers;

  // ── Saat dilimleri ─────────────────────────────────────
  List<AgmTimeSlot> _existingSlots = [];
  bool _loadingSlots = true;
  bool _saving = false;

  // ── Öğretmenler ────────────────────────────────────────
  List<Map<String, dynamic>> _teachers = [];

  // ── UI / UX State ──────────────────────────────────────
  List<AgmSlotTeacherEntry>? _copiedEntries;
  String? _expandedSlotId; // Tek bir slot açık olabilir

  final List<String> _gunler = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  List<AgmTimeSlot> _allLibrarySlots = [];

  // ── Derslikler ──────────────────────────────────────────
  List<Map<String, dynamic>> _classrooms = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    if (widget.initialCycle != null) {
      final c = widget.initialCycle!;
      _titleController.text = c.title ?? '';
      _selectedExamIds = c.referansDenemeSinavIds.isNotEmpty
          ? c.referansDenemeSinavIds
          : [c.referansDenemeSinavId];
      _selectedExamNames = c.referansDenemeSinavAdlari.isNotEmpty
          ? c.referansDenemeSinavAdlari
          : [c.referansDenemeSinavAdi];
      _baslangic = c.baslangicTarihi;
      _maxSaat = c.haftalikMaksimumSaat;
      _minDers = c.minimumDersSayisi;
    }

    _loadData();
    if (_selectedExamIds.isNotEmpty) {
      _updateExamDersler();
    }
  }

  Future<void> _loadData() async {
    // Tüm Saat dilimleri (Kütüphane için)
    final librarySlots = await _repo.getTimeSlots(
      widget.institutionId,
      includeInactive: true,
    );

    // Sınavlar - trial_exams collection
    QuerySnapshot? examSnap;
    try {
      examSnap = await _db
          .collection('trial_exams')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          // orderBy('date'...) bazen index hatası verebilir, şimdilik basit tutalım
          .get();
    } catch (e) {
      debugPrint('Sınavları çekerken hata: $e');
    }

    // Saat dilimleri (mevcut cycle için boş başlar)
    // Öğretmenler – users collection, type:'staff', title:'ogretmen'
    final teacherSnap = await _db
        .collection('users')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('type', isEqualTo: 'staff')
        .get();

    // Derslikler - classrooms collection
    final classroomSnap = await _db
        .collection('classrooms')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('isActive', isEqualTo: true)
        .get();

    if (mounted) {
      // schoolTypeName ile workLocations/workLocation filtresi (client-side)
      final allStaff = teacherSnap.docs.map((d) {
        final data = d.data();
        return {'id': d.id, ...data};
      }).toList();

      final teachers = allStaff.where((s) {
        // Sadece öğretmenler (title veya role alanı)
        final title = (s['title'] ?? s['role'] ?? '').toString().toLowerCase();
        final isOgretmen =
            title == 'ogretmen' || title == 'teacher' || title.isEmpty;

        // schoolTypeName ile workLocations filtresi
        bool matchesSchoolType = true;
        final stn = widget.schoolTypeName;
        if (stn != null && stn.isNotEmpty) {
          final locations = s['workLocations'];
          if (locations != null && locations is List && locations.isNotEmpty) {
            matchesSchoolType = List<String>.from(locations).contains(stn);
          } else if (s['workLocation'] != null &&
              s['workLocation'].toString().isNotEmpty) {
            matchesSchoolType = s['workLocation'].toString() == stn;
          }
          // workLocations boşsa göster (henüz atanmamış olabilir)
        }

        return isOgretmen && matchesSchoolType;
      }).toList();

      setState(() {
        _exams = examSnap != null 
            ? examSnap.docs.map((d) => {'id': d.id, ...d.data() as Map<String, dynamic>}).toList()
            : [];
        // Tarihe göre manuel sırala (eğer alan varsa)
        _exams.sort((a, b) {
          final da = a['date'];
          final db = b['date'];
          if (da is Timestamp && db is Timestamp) return db.compareTo(da);
          return 0;
        });

        _classrooms = classroomSnap.docs
            .map(
              (d) => {
                'id': d.id,
                'name': d.data()['classroomName'] ?? '',
                'capacity': d.data()['capacity'] ?? 0,
              },
            )
            .toList()
          ..sort((a, b) => _compareNatural(a['name'] as String, b['name'] as String));

        _existingSlots = [];
        _allLibrarySlots = librarySlots;
        _loadingSlots = false;
        _teachers =
            teachers
                .map(
                  (s) => {
                    'id': s['id'] as String,
                    'name':
                        (s['fullName'] ??
                        '${s['name'] ?? ''} ${s['surname'] ?? ''}'.trim()),
                    'branch': s['branch'] ?? '',
                  },
                )
                .where((t) => (t['name'] as String).isNotEmpty)
                .toList()
              ..sort(
                (a, b) => (a['name'] as String).compareTo(b['name'] as String),
              );
      });

      // Eger duzenleme modundaysak onceki gruplari yukle
      if (widget.initialCycle != null) {
        _loadExistingSlotsFromCycle(widget.initialCycle!.id);
      }
    }
  }

  Future<void> _loadExistingSlotsFromCycle(String cycleId) async {
    try {
      final groups = await _repo.getGroupsByCycle(cycleId);
      final Map<String, AgmTimeSlot> slotMap = {};

      for (final g in groups) {
        if (!slotMap.containsKey(g.saatDilimiId)) {
          slotMap[g.saatDilimiId] = AgmTimeSlot(
            id: g.saatDilimiId,
            institutionId: widget.institutionId,
            ad: g.saatDilimiAdi,
            gun: g.gun,
            baslangicSaat: g.baslangicSaat,
            bitisSaat: g.bitisSaat,
            ogretmenGirisler: [],
          );
        }

        slotMap[g.saatDilimiId]!.ogretmenGirisler.add(
          AgmSlotTeacherEntry(
            dersId: g.dersId,
            dersAdi: g.dersAdi,
            ogretmenId: g.ogretmenId,
            ogretmenAdi: g.ogretmenAdi,
            derslikId: g.derslikId,
            derslikAdi: g.derslikAdi,
            kapasite: g.kapasite,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _existingSlots = slotMap.values.toList();
        });
      }
    } catch (e) {
      debugPrint('Mevcut cycle gruplarini cekerken hata: $e');
    }
  }

  /// Sınav(lar) seçilince answerKeys'ten ders listesini çek
  Future<void> _updateExamDersler() async {
    Map<String, String> allDersler = {};

    for (var examId in _selectedExamIds) {
      final doc = await _db.collection('trial_exams').doc(examId).get();
      final data = doc.data() ?? {};

      // Önce answerKeys'ten dersler
      final answerKeys = data['answerKeys'] as Map<String, dynamic>? ?? {};
      if (answerKeys.isNotEmpty) {
        final firstBooklet = answerKeys.values.first;
        if (firstBooklet is Map<String, dynamic>) {
          for (final k in firstBooklet.keys) {
            allDersler[k] = k;
          }
        }
      }

      // answerKeys boşsa resultsJson'dan dene
      if (data['resultsJson'] != null) {
        try {
          final raw = data['resultsJson'] as String;
          final list = jsonDecode(raw) as List<dynamic>;
          if (list.isNotEmpty) {
            final first = list.first as Map<String, dynamic>;
            final subjects = first['subjects'] as Map<String, dynamic>? ?? {};
            for (final k in subjects.keys) {
              allDersler[k] = k;
            }
          }
        } catch (_) {}
      }
    }

    setState(() {
      _examDersler = allDersler;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _examSearchController.dispose();
    super.dispose();
  }

  void _showExamSelectionDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Icon(Icons.quiz_outlined, color: Colors.deepOrange),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Deneme Sınavı Seçimi',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _examSearchController,
                  decoration: _inputDecoration('Sınav Ara...').copyWith(
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  onChanged: (val) {
                    setSt(() {}); // Dialog state'ini yenile
                  },
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final query = _examSearchController.text.toLowerCase();
                    final filteredExams = _exams.where((e) {
                      final name = (e['name'] ?? '').toString().toLowerCase();
                      final type = (e['type'] ?? '').toString().toLowerCase();
                      return name.contains(query) || type.contains(query);
                    }).toList();

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: filteredExams.length,
                      itemBuilder: (context, index) {
                        final e = filteredExams[index];
                        final id = e['id'] as String;
                        final name = e['name'] as String? ?? '';
                        final type = e['type'] as String? ?? '';
                        final dateRaw = e['date'];
                        String dateStr = '';
                        if (dateRaw is Timestamp) {
                          dateStr = DateFormat('dd.MM.yyyy').format(dateRaw.toDate());
                        }

                        final isSelected = _selectedExamIds.contains(id);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.deepOrange.shade50
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.deepOrange.shade200
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: CheckboxListTile(
                            title: Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '$type • $dateStr',
                              style: const TextStyle(fontSize: 12),
                            ),
                            value: isSelected,
                            activeColor: Colors.deepOrange,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedExamIds.add(id);
                                  _selectedExamNames.add(name);
                                } else {
                                  _selectedExamIds.remove(id);
                                  _selectedExamNames.remove(name);
                                }
                              });
                              setSt(() {});
                              _updateExamDersler();
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Seçimi Tamamla'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  ANA SCAFFOLD
  // ════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Yeni AGM Cycle'),
        backgroundColor: Colors.deepOrange,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Derslik Tanımlama',
            icon: const Icon(Icons.meeting_room_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ClassroomManagementScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: 'AGM',
                  ),
                ),
              );
              // Geri dönünce derslik verisini tazele
              _loadData();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: '1. Ayarlar'),
            Tab(text: '2. Saat Dilimleri'),
            Tab(text: '3. Özet'),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSettingsTab(),
              _buildSlotsTab(),
              _buildSummaryTab(),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  TAB 1: AYARLAR
  // ════════════════════════════════════════════════════════

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Cycle Bilgileri', Icons.edit_note),
          const SizedBox(height: 12),
          TextFormField(
            controller: _titleController,
            decoration: _inputDecoration(
              'Başlık (örn: Şubat 1. Hafta Etütleri)',
            ),
          ),
          const SizedBox(height: 24),
          _sectionHeader('Referans Deneme Sınav(ları)', Icons.quiz_outlined),
          const SizedBox(height: 12),
          InkWell(
            onTap: _showExamSelectionDialog,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedExamIds.isEmpty
                          ? 'Sınav seçmek için dokunun'
                          : _selectedExamNames.join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _selectedExamIds.isEmpty
                            ? Colors.grey
                            : Colors.black87,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Icon(Icons.search, color: Colors.deepOrange),
                ],
              ),
            ),
          ),
          if (_selectedExamIds.isNotEmpty && _examDersler.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.deepOrange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.deepOrange.shade100),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _examDersler.values
                    .map(
                      (d) => Chip(
                        label: Text(d, style: const TextStyle(fontSize: 11)),
                        backgroundColor: Colors.white,
                        side: BorderSide(color: Colors.deepOrange.shade200),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ),
            Text(
              '${_examDersler.length} ders tespit edildi',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
          const SizedBox(height: 24),
          _sectionHeader('Tarih Aralığı', Icons.date_range),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDateButton(
                  label: 'Başlangıç',
                  date: _baslangic,
                  onTap: () => _pickDate(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDateButton(
                  label: 'Bitiş',
                  date: _bitis,
                  onTap: () => _pickDate(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _sectionHeader(
            'Soft Kısıtlar (Opsiyonel)',
            Icons.tune,
            subtitle: 'Aşılabilir, uyarı üretir',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: _maxSaat?.toString(),
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration('Haftalık maks. saat'),
                  onChanged: (v) => _maxSaat = int.tryParse(v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: _minDers?.toString(),
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration('Min. ders sayısı'),
                  onChanged: (v) => _minDers = int.tryParse(v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _tabController.animateTo(1),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Sonraki: Saat Dilimleri →'),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  TAB 2: SAAT DİLİMLERİ
  // ════════════════════════════════════════════════════════

  Widget _buildSlotsTab() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    if (_loadingSlots) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        _buildSlotLibrary(),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSlotsHeader(isMobile),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildHeaderActionBtn(
                            onPressed: _showAddSlotSheet,
                            icon: Icons.add_circle_outline,
                            label: 'Ekle',
                            color: Colors.deepOrange,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildHeaderActionBtn(
                            onPressed: _autoDistributeClassrooms,
                            icon: Icons.auto_awesome,
                            label: 'Oto Dağıt',
                            color: Colors.teal,
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: _buildSlotsHeader(isMobile)),
                    _buildHeaderActionBtn(
                      onPressed: _showAddSlotSheet,
                      icon: Icons.add_circle_outline,
                      label: 'Ekle',
                      color: Colors.deepOrange,
                    ),
                    const SizedBox(width: 8),
                    _buildHeaderActionBtn(
                      onPressed: _autoDistributeClassrooms,
                      icon: Icons.auto_awesome,
                      label: 'Derslikleri Otomatik Dağıt',
                      color: Colors.teal,
                    ),
                  ],
                ),
        ),
        Expanded(
          child: _existingSlots.isEmpty
              ? _buildNoSlotsState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _existingSlots.length,
                  itemBuilder: (context, i) =>
                      _buildSlotCard(_existingSlots[i], i),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _tabController.animateTo(0),
                  child: const Text('← Geri'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _tabController.animateTo(2),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Özet →'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoSlotsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'Henüz saat dilimi yok',
            style: TextStyle(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _showAddSlotSheet,
            child: const Text('İlk dilimi ekle'),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotCard(AgmTimeSlot slot, int index) {
    final isExpanded = _expandedSlotId == slot.id;
    final hasCopied = _copiedEntries != null && _copiedEntries!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey(slot.id), // State koruması için
        initiallyExpanded: isExpanded,
        onExpansionChanged: (val) {
          setState(() {
            if (val) {
              _expandedSlotId = slot.id;
            } else if (_expandedSlotId == slot.id) {
              _expandedSlotId = null;
            }
          });
        },
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.deepOrange.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.access_time,
            color: Colors.deepOrange,
            size: 20,
          ),
        ),
        title: Text(
          slot.ad,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          slot.ogretmenGirisler.isEmpty
              ? 'Henüz ders/öğretmen eklenmedi'
              : '${slot.ogretmenGirisler.length} ders-öğretmen girişi',
          style: TextStyle(
            color: slot.ogretmenGirisler.isEmpty
                ? Colors.red.shade400
                : Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.grey),
              onSelected: (value) {
                switch (value) {
                  case 'add':
                    _showAddTeacherEntrySheet(slot, index);
                    break;
                  case 'copy':
                    _copySlot(slot);
                    break;
                  case 'paste':
                    _pasteSlot(slot, index);
                    break;
                  case 'archive':
                    _deleteSlot(slot);
                    break;
                  case 'remove':
                    setState(
                      () => _existingSlots.removeWhere((s) => s.id == slot.id),
                    );
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'add',
                  child: ListTile(
                    leading: Icon(
                      Icons.add_circle_outline,
                      color: Colors.deepOrange,
                    ),
                    title: Text('Ders/Öğretmen Ekle'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: ListTile(
                    leading: Icon(Icons.copy, color: Colors.blue),
                    title: Text('Kopyala'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                if (hasCopied)
                  const PopupMenuItem(
                    value: 'paste',
                    child: ListTile(
                      leading: Icon(Icons.paste, color: Colors.green),
                      title: Text('Yapıştır'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'archive',
                  child: ListTile(
                    leading: Icon(Icons.archive_outlined, color: Colors.grey),
                    title: Text('Arşive Gönder'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: ListTile(
                    leading: Icon(
                      Icons.remove_circle_outline,
                      color: Colors.redAccent,
                    ),
                    title: Text('Sihirbazdan Çıkar'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              ],
            ),
            const Icon(Icons.expand_more, size: 20),
          ],
        ),
        children: [
          if (slot.ogretmenGirisler.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Henüz ders/öğretmen atanmamış.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: (() {
                  final sortedEntries = List<AgmSlotTeacherEntry>.from(slot.ogretmenGirisler);
                  sortedEntries.sort((a, b) => a.dersAdi.compareTo(b.dersAdi));
                  return sortedEntries;
                })().map((entry) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.dersAdi,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '${entry.ogretmenAdi} • Kapasite: ${entry.kapasite}${entry.derslikAdi != null ? ' • ${entry.derslikAdi}' : ''}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.edit,
                                size: 16,
                                color: Colors.blue.shade400,
                              ),
                              onPressed: () =>
                                  _editTeacherEntry(slot, index, entry),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.red.shade300,
                              ),
                              onPressed: () =>
                                  _removeTeacherEntry(slot, index, entry),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  void _copySlot(AgmTimeSlot slot) {
    if (slot.ogretmenGirisler.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kopyalanacak veri yok')));
      return;
    }
    setState(() => _copiedEntries = List.from(slot.ogretmenGirisler));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${slot.ogretmenGirisler.length} giriş kopyalandı'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Future<void> _pasteSlot(AgmTimeSlot slot, int index) async {
    if (_copiedEntries == null || _copiedEntries!.isEmpty) return;

    // Mevcut olanlarla birleştir (varsa aynı ders-öğretmen ikililerini ekleme? opsiyonel)
    // Şimdilik üzerine ekleyelim
    final updatedEntries = [...slot.ogretmenGirisler, ..._copiedEntries!];

    final updatedSlot = AgmTimeSlot(
      id: slot.id,
      institutionId: slot.institutionId,
      ad: slot.ad,
      gun: slot.gun,
      baslangicSaat: slot.baslangicSaat,
      bitisSaat: slot.bitisSaat,
      ogretmenGirisler: updatedEntries,
    );

    // DB güncelle
    await _repo.updateTimeSlotTeachers(slot.id, updatedEntries);

    setState(() {
      _existingSlots[index] = updatedSlot;
      _expandedSlotId = slot.id; // Yapıştırınca açalım
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Atamalar başarıyla yapıştırıldı'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  TAB 3: ÖZET & OLUŞTUR
  // ════════════════════════════════════════════════════════

  Widget _buildSummaryTab() {
    final formatter = DateFormat('dd.MM.yyyy');
    final totalEntries = _existingSlots.fold(
      0,
      (s, sl) => s + sl.ogretmenGirisler.length,
    );
    final hazir =
        _selectedExamIds.isNotEmpty &&
        _existingSlots.isNotEmpty &&
        totalEntries > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_titleController.text.isNotEmpty)
            _buildSummaryItem(
              icon: Icons.edit_note,
              label: 'Cycle Başlığı',
              value: _titleController.text,
              ok: true,
            ),
          _buildSummaryItem(
            icon: Icons.quiz_outlined,
            label: 'Referans Sınav(lar)',
            value: _selectedExamNames.isEmpty
                ? '—'
                : _selectedExamNames.join(', '),
            ok: _selectedExamIds.isNotEmpty,
          ),
          _buildSummaryItem(
            icon: Icons.date_range,
            label: 'Tarih Aralığı',
            value:
                '${formatter.format(_baslangic)} – ${formatter.format(_bitis)}',
            ok: true,
          ),
          _buildSummaryItem(
            icon: Icons.schedule,
            label: 'Saat Dilimleri',
            value: '${_existingSlots.length} dilim',
            ok: _existingSlots.isNotEmpty,
          ),
          _buildSummaryItem(
            icon: Icons.group,
            label: 'Toplam Grup',
            value: '$totalEntries grup oluşturulacak',
            ok: totalEntries > 0,
          ),
          if (_maxSaat != null)
            _buildSummaryItem(
              icon: Icons.timer,
              label: 'Haftalık Maks.',
              value: '$_maxSaat saat',
              ok: true,
            ),
          const SizedBox(height: 24),
          _buildClassroomAnalysisPanel(),
          const SizedBox(height: 32),
          if (!hazir) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange.shade700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cycle oluşturmak için:\n'
                      '• Sınav seçin\n'
                      '• En az 1 saat dilimi ekleyin\n'
                      '• Her dilime en az 1 ders+öğretmen atayın',
                      style: TextStyle(color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: hazir && !_saving ? _saveCycle : null,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.rocket_launch_outlined),
              label: Text(
                _saving
                    ? (widget.initialCycle != null
                          ? 'Güncelleniyor...'
                          : 'Oluşturuluyor...')
                    : (widget.initialCycle != null
                          ? 'Cycle Güncelle'
                          : 'Cycle Oluştur'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required String value,
    required bool ok,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.deepOrange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Icon(
            ok ? Icons.check_circle : Icons.radio_button_unchecked,
            color: ok ? Colors.green : Colors.grey,
            size: 20,
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  BOTTOM SHEET: YENİ SLOT EKLE (gün + saat)
  // ════════════════════════════════════════════════════════

  void _showAddSlotSheet() {
    String selectedGun = _gunler.first;
    TimeOfDay baslangic = const TimeOfDay(hour: 09, minute: 00);
    TimeOfDay bitis = const TimeOfDay(hour: 09, minute: 40);
    final titleController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Yeni Saat Dilimi Tanımla',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: titleController,
                  decoration: _inputDecoration(
                    'Özel Başlık (Opsiyonel)',
                  ).copyWith(hintText: 'örn: TYT-A Grubu veya Sabah Etütleri'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedGun,
                  decoration: _inputDecoration('Gün'),
                  items: _gunler
                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: (v) => setSt(() => selectedGun = v!),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildTimePicker(
                        ctx: context,
                        label: 'Başlangıç',
                        time: baslangic,
                        onPicked: (t) => setSt(() => baslangic = t),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTimePicker(
                        ctx: context,
                        label: 'Bitiş',
                        time: bitis,
                        onPicked: (t) => setSt(() => bitis = t),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final name = titleController.text.trim().isNotEmpty
                          ? titleController.text.trim()
                          : '$selectedGun ${baslangic.format(context)}-${bitis.format(context)}';

                      final slot = AgmTimeSlot(
                        id: '',
                        institutionId: widget.institutionId,
                        ad: name,
                        gun: selectedGun,
                        baslangicSaat: baslangic.format(context),
                        bitisSaat: bitis.format(context),
                      );

                      final id = await _repo.createTimeSlot(slot);
                      final newSlot = AgmTimeSlot(
                        id: id,
                        institutionId: widget.institutionId,
                        ad: name,
                        gun: selectedGun,
                        baslangicSaat: baslangic.format(context),
                        bitisSaat: bitis.format(context),
                      );

                      setState(() {
                        _existingSlots.add(newSlot);
                        _allLibrarySlots.insert(0, newSlot);
                      });
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Oluştur ve Ekle'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  BOTTOM SHEET: DERS + ÖĞRETMEN EKLE (Multi-select)
  // ════════════════════════════════════════════════════════

  void _showAddTeacherEntrySheet(AgmTimeSlot slot, int slotIndex) {
    if (_examDersler.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Önce Tab 1\'den bir sınav seçin. Ders listesi sınavdan otomatik gelir.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final Set<String> secilenDersIds = {};
    final Map<String, Set<String>> dersOgretmenMap = {};
    // {dersId_ogretmenId: {kapasite: int, derslikId: string, derslikAdi: string}}
    final Map<String, Map<String, dynamic>> extraInfo = {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (_, setSt) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${slot.ad} – Planlama',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ders seçin, öğretmen atayın ve her öğretmen için derslik belirleyin.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                const Text(
                  '1. Dersler',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                const SizedBox(height: 8),
                ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                    },
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: () {
                        final List<String> order = [
                          'türkçe',
                          'sosyal bilgiler',
                          'din kültürü',
                          'ingilizce',
                          'matematik',
                          'fen bilimleri',
                        ];
                        final sortedEntries = _examDersler.entries.toList()
                          ..sort((a, b) {
                            final nA = a.value.toLowerCase();
                            final nB = b.value.toLowerCase();
                            int idxA = order.indexWhere((o) => nA.contains(o));
                            int idxB = order.indexWhere((o) => nB.contains(o));
                            if (idxA == -1) idxA = 99;
                            if (idxB == -1) idxB = 99;
                            return idxA.compareTo(idxB);
                          });

                        return sortedEntries.map((e) {
                          final selected = secilenDersIds.contains(e.key);
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(
                                e.value,
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: selected,
                              selectedColor: Colors.deepOrange,
                              checkmarkColor: Colors.white,
                              labelStyle: TextStyle(
                                color: selected ? Colors.white : Colors.black87,
                              ),
                              onSelected: (on) {
                                setSt(() {
                                  if (on) {
                                    secilenDersIds.add(e.key);
                                    dersOgretmenMap.putIfAbsent(
                                      e.key,
                                      () => {},
                                    );
                                  } else {
                                    secilenDersIds.remove(e.key);
                                    dersOgretmenMap.remove(e.key);
                                  }
                                });
                              },
                            ),
                          );
                        }).toList();
                      }(),
                    ),
                  ),
                ),
                if (secilenDersIds.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    '2. Öğretmen & Derslik Atamaları',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ...secilenDersIds.map((dersId) {
                    final dersAdi = _examDersler[dersId] ?? dersId;
                    final selectedTeachers = dersOgretmenMap[dersId] ?? {};

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dersAdi,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context).copyWith(
                              dragDevices: {
                                PointerDeviceKind.touch,
                                PointerDeviceKind.mouse,
                              },
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: _teachers
                                    .where((t) {
                                      final b = (t['branch'] ?? '')
                                          .toString()
                                          .toLowerCase();
                                      final d = dersAdi.toLowerCase();
                                      return b == d ||
                                          d.contains(b) ||
                                          b.contains(d);
                                    })
                                    .map((t) {
                                      final tId = t['id'];
                                      final isSelected = selectedTeachers
                                          .contains(tId);
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 6,
                                        ),
                                        child: ChoiceChip(
                                          label: Text(
                                            t['name'],
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                          selected: isSelected,
                                          selectedColor:
                                              Colors.deepOrange.shade100,
                                          onSelected: (on) {
                                            setSt(() {
                                              if (on) {
                                                selectedTeachers.add(tId);
                                                extraInfo['${dersId}_$tId'] = {
                                                  'kapasite': 20,
                                                  'derslikId': null,
                                                  'derslikAdi': null,
                                                };
                                              } else {
                                                selectedTeachers.remove(tId);
                                                extraInfo.remove(
                                                  '${dersId}_$tId',
                                                );
                                              }
                                            });
                                          },
                                        ),
                                      );
                                    })
                                    .toList(),
                              ),
                            ),
                          ),
                          if (selectedTeachers.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            ...selectedTeachers.map((tId) {
                              final tName = _teachers.firstWhere(
                                (t) => t['id'] == tId,
                              )['name'];
                              final info = extraInfo['${dersId}_$tId']!;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        tName,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 45,
                                      child: TextFormField(
                                        key: ValueKey(
                                          '${dersId}_${tId}_${info['kapasite']}',
                                        ),
                                        initialValue: info['kapasite']
                                            .toString(),
                                        keyboardType: TextInputType.number,
                                        decoration: _inputDecoration('Kap')
                                            .copyWith(
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                  ),
                                            ),
                                        style: const TextStyle(fontSize: 11),
                                        onChanged: (v) => info['kapasite'] =
                                            int.tryParse(v) ?? 20,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 3,
                                      child: DropdownButtonFormField<String>(
                                        value: info['derslikId'],
                                        hint: const Text(
                                          'Derslik',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                        isExpanded: true,
                                        decoration: _inputDecoration('Derslik')
                                            .copyWith(
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                  ),
                                            ),
                                        items: [
                                          const DropdownMenuItem(
                                            value: null,
                                            child: Text(
                                              'Seçilmedi',
                                              style: TextStyle(fontSize: 10),
                                            ),
                                          ),
                                          ..._classrooms.map(
                                            (c) => DropdownMenuItem(
                                              value: c['id'],
                                              child: Text(
                                                c['name'],
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                        ],
                                        onChanged: (v) async {
                                          if (v != null) {
                                            // Çakışma Kontrolü
                                            bool conflict = false;
                                            String? conflictTeacher;

                                            // 1. Mevcut slotta kaydedilmiş olanlar
                                            for (var entry
                                                in slot.ogretmenGirisler) {
                                              if (entry.derslikId == v) {
                                                conflict = true;
                                                conflictTeacher =
                                                    entry.ogretmenAdi;
                                                break;
                                              }
                                            }

                                            // 2. Şu an seçilmekte olan diğer satırlar
                                            if (!conflict) {
                                              extraInfo.forEach((key, val) {
                                                if (key != '${dersId}_$tId' &&
                                                    val['derslikId'] == v) {
                                                  conflict = true;
                                                  // Ogretmen adını bul
                                                  final otherTId = key
                                                      .split('_')
                                                      .last;
                                                  conflictTeacher = _teachers
                                                      .firstWhere(
                                                        (t) =>
                                                            t['id'] == otherTId,
                                                        orElse: () => {
                                                          'name':
                                                              'Başka bir öğretmen',
                                                        },
                                                      )['name'];
                                                }
                                              });
                                            }

                                            if (conflict) {
                                              final proceed = await showDialog<bool>(
                                                context: ctx,
                                                builder: (dCtx) => AlertDialog(
                                                  title: const Text(
                                                    'Derslik Çakışması',
                                                  ),
                                                  content: Text(
                                                    'Bu derslik bu saatte zaten "$conflictTeacher" tarafından kullanılıyor.\n\nYine de atamak istiyor musunuz?',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                            dCtx,
                                                            false,
                                                          ),
                                                      child: const Text(
                                                        'İPTAL',
                                                      ),
                                                    ),
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                            dCtx,
                                                            true,
                                                          ),
                                                      child: const Text(
                                                        'EVET, ATAYALIM',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (proceed != true) return;
                                            }
                                          }

                                          setSt(() {
                                            info['derslikId'] = v;
                                            if (v == null) {
                                              info['derslikAdi'] = null;
                                            } else {
                                              final cr = _classrooms.firstWhere(
                                                (c) => c['id'] == v,
                                              );
                                              info['derslikAdi'] = cr['name'];
                                              // Artık manuel kapasite korunuyor, derslik kapasitesiyle ezilmiyor
                                              // info['kapasite'] = cr['capacity'] ?? 20;
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    onPressed: () {
                      // Bu slot için anlık otomatik seçim yap
                      final rooms = List<Map<String, dynamic>>.from(_classrooms);
                      rooms.sort((a, b) => _compareNatural(a['name']!, b['name']!));

                      final Set<String> occupied = {};
                      // 1. Zaten bu slotta kayıtlı olanlar
                      for (final e in slot.ogretmenGirisler) {
                        if (e.derslikId != null) occupied.add(e.derslikId!);
                      }
                      // 2. Şu an seçilmiş olanlar
                      extraInfo.forEach((k, v) {
                        if (v['derslikId'] != null) occupied.add(v['derslikId']!);
                      });

                      setSt(() {
                        extraInfo.forEach((key, info) {
                          if (info['derslikId'] == null) {
                            for (final r in rooms) {
                              final rid = r['id']!;
                              if (!occupied.contains(rid)) {
                                info['derslikId'] = rid;
                                info['derslikAdi'] = r['name'];
                                occupied.add(rid);
                                break;
                              }
                            }
                          }
                        });
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade50,
                      foregroundColor: Colors.teal,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.teal.shade100),
                      ),
                    ),
                    label: const Text(
                      'Derslikleri Otomatik Dağıt',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        secilenDersIds.isEmpty ||
                            dersOgretmenMap.values.every((v) => v.isEmpty)
                        ? null
                        : () async {
                            final List<AgmSlotTeacherEntry> newEntries = [];
                            for (var dersId in secilenDersIds) {
                              final dersAdi = _examDersler[dersId] ?? dersId;
                              for (var tId in dersOgretmenMap[dersId]!) {
                                final tName = _teachers.firstWhere(
                                  (t) => t['id'] == tId,
                                )['name'];
                                final info = extraInfo['${dersId}_$tId']!;
                                newEntries.add(
                                  AgmSlotTeacherEntry(
                                    dersId: dersId,
                                    dersAdi: dersAdi,
                                    ogretmenId: tId,
                                    ogretmenAdi: tName,
                                    kapasite: info['kapasite'],
                                    derslikId: info['derslikId'],
                                    derslikAdi: info['derslikAdi'],
                                  ),
                                );
                              }
                            }

                            final updatedEntries = [
                              ...slot.ogretmenGirisler,
                              ...newEntries,
                            ];
                            await _repo.updateTimeSlotTeachers(
                              slot.id,
                              updatedEntries,
                            );

                            setState(() {
                              _existingSlots[slotIndex] = AgmTimeSlot(
                                id: slot.id,
                                institutionId: slot.institutionId,
                                ad: slot.ad,
                                gun: slot.gun,
                                baslangicSaat: slot.baslangicSaat,
                                bitisSaat: slot.bitisSaat,
                                ogretmenGirisler: updatedEntries,
                              );
                            });
                            Navigator.pop(ctx);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Seçimleri Kaydet ve Ekle'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _removeTeacherEntry(
    AgmTimeSlot slot,
    int slotIndex,
    AgmSlotTeacherEntry entry,
  ) async {
    final updated = slot.ogretmenGirisler
        .where(
          (e) =>
              !(e.dersId == entry.dersId && e.ogretmenId == entry.ogretmenId),
        )
        .toList();
    final updatedSlot = AgmTimeSlot(
      id: slot.id,
      institutionId: slot.institutionId,
      ad: slot.ad,
      gun: slot.gun,
      baslangicSaat: slot.baslangicSaat,
      bitisSaat: slot.bitisSaat,
      ogretmenGirisler: updated,
    );
    await _repo.updateTimeSlotTeachers(slot.id, updated);
    setState(() => _existingSlots[slotIndex] = updatedSlot);
  }

  /// Mevcut tüm slotlara alfanümerik sıraya göre derslikleri otomatik dağıtır.
  /// Kural: Aynı branş dersleri mümkünse aynı derslikte (farklı seanslarda) olur.
  Future<void> _autoDistributeClassrooms() async {
    if (_classrooms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Atanacak derslik bulunamadı.')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Derslikler otomatik dağıtılıyor...')),
    );

    // 1) Derslikleri doğal sıraya göre al
    final classroomList = List<Map<String, dynamic>>.from(_classrooms);
    classroomList.sort((a, b) => _compareNatural(a['name']!, b['name']!));

    // 2) Mevcut derslik kullanımını takip et (Day -> SlotKey -> List<RoomID>)
    final Map<String, Map<String, Set<String>>> usage = {};

    // Mevcut (elle atanmış) derslikleri rezerve et
    for (final slot in _existingSlots) {
      final slotKey = '${slot.baslangicSaat}-${slot.bitisSaat}';
      for (final entry in slot.ogretmenGirisler) {
        if (entry.derslikId != null) {
          usage
              .putIfAbsent(slot.gun, () => {})
              .putIfAbsent(slotKey, () => {})
              .add(entry.derslikId!);
        }
      }
    }

    // 3) Atama bekleyenleri işle
    // Kural: Aynı branş dersleri mümkünse aynı derslikte olur.
    final Map<String, Map<String, String>> branchRoomPref = {}; // Day -> Branch -> RoomId

    final List<AgmTimeSlot> updatedSlots = List.from(_existingSlots);

    for (int i = 0; i < updatedSlots.length; i++) {
      final slot = updatedSlots[i];
      final slotKey = '${slot.baslangicSaat}-${slot.bitisSaat}';
      final updatedEntries = List<AgmSlotTeacherEntry>.from(slot.ogretmenGirisler);
      bool slotChanged = false;

      for (int j = 0; j < updatedEntries.length; j++) {
        final entry = updatedEntries[j];
        if (entry.derslikId == null) {
          String? selectedRoomId;
          String? selectedRoomName;

          // Önce bu branşın bu gün kullandığı odayı dene
          final prefId = branchRoomPref[slot.gun]?[entry.dersAdi];
          if (prefId != null) {
            final usedRoomsInSlot = usage[slot.gun]?[slotKey] ?? {};
            if (!usedRoomsInSlot.contains(prefId)) {
              selectedRoomId = prefId;
            }
          }

          // Tercih edilen oda doluysa veya yoksa boş oda ara
          if (selectedRoomId == null) {
            for (final room in classroomList) {
              final rid = room['id']!;
              final usedRoomsInSlot = usage[slot.gun]?[slotKey] ?? {};
              if (!usedRoomsInSlot.contains(rid)) {
                selectedRoomId = rid;
                branchRoomPref.putIfAbsent(slot.gun, () => {})[entry.dersAdi] = rid;
                break;
              }
            }
          }

          if (selectedRoomId != null) {
            selectedRoomName = classroomList.firstWhere((r) => r['id'] == selectedRoomId)['name'];
            updatedEntries[j] = AgmSlotTeacherEntry(
              dersId: entry.dersId,
              dersAdi: entry.dersAdi,
              ogretmenId: entry.ogretmenId,
              ogretmenAdi: entry.ogretmenAdi,
              kapasite: entry.kapasite, // Manuel kapasite korunur
              derslikId: selectedRoomId,
              derslikAdi: selectedRoomName,
            );
            usage
                .putIfAbsent(slot.gun, () => {})
                .putIfAbsent(slotKey, () => {})
                .add(selectedRoomId);
            slotChanged = true;
          }
        }
      }

      if (slotChanged) {
        updatedSlots[i] = AgmTimeSlot(
          id: slot.id,
          institutionId: slot.institutionId,
          ad: slot.ad,
          gun: slot.gun,
          baslangicSaat: slot.baslangicSaat,
          bitisSaat: slot.bitisSaat,
          ogretmenGirisler: updatedEntries,
        );
        // DB güncelle (Persistence)
        await _repo.updateTimeSlotTeachers(slot.id, updatedEntries);
      }
    }

    setState(() {
      _existingSlots = updatedSlots;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Derslikler başarıyla dağıtıldı.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// Alfanümerik metinleri "doğal" sırada karşılaştırır (1, 2, 10...)
  int _compareNatural(String a, String b) {
    final RegExp re = RegExp(r'(\d+)|\D+');
    final Iterable<Match> aMatch = re.allMatches(a.toLowerCase());
    final Iterable<Match> bMatch = re.allMatches(b.toLowerCase());
    final itA = aMatch.iterator;
    final itB = bMatch.iterator;
    while (itA.moveNext() && itB.moveNext()) {
      final aStr = itA.current.group(0)!;
      final bStr = itB.current.group(0)!;
      if (itA.current.group(1) != null && itB.current.group(1) != null) {
        final aNum = int.parse(aStr);
        final bNum = int.parse(bStr);
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else {
        final cmp = aStr.compareTo(bStr);
        if (cmp != 0) return cmp;
      }
    }
    return a.length.compareTo(b.length);
  }

  Future<void> _editTeacherEntry(
    AgmTimeSlot slot,
    int slotIndex,
    AgmSlotTeacherEntry entry,
  ) async {
    String eOgretmenId = entry.ogretmenId;
    String eOgretmenAdi = entry.ogretmenAdi;
    int eKapasite = entry.kapasite;
    String? eDerslikId = entry.derslikId;
    String? eDerslikAdi = entry.derslikAdi;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              '${entry.dersAdi} Düzenle',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: _teachers.any((t) => t['id'] == eOgretmenId)
                        ? eOgretmenId
                        : null,
                    decoration: _inputDecoration('Öğretmen'),
                    items: _teachers
                        .map(
                          (t) => DropdownMenuItem(
                            value: t['id'] as String,
                            child: Text(
                              t['name'] as String,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setSt(() {
                          eOgretmenId = v;
                          eOgretmenAdi =
                              _teachers.firstWhere((t) => t['id'] == v)['name']
                                  as String;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: eKapasite.toString(),
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration('Kapasite'),
                    onChanged: (v) => eKapasite = int.tryParse(v) ?? 20,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: eDerslikId,
                    decoration: _inputDecoration('Derslik (Opsiyonel)'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text(
                          'Seçilmedi',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      ..._classrooms.map(
                        (c) => DropdownMenuItem(
                          value: c['id'] as String,
                          child: Text(
                            c['name'] as String,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setSt(() {
                        eDerslikId = v;
                        if (v != null) {
                          eDerslikAdi =
                              _classrooms.firstWhere(
                                    (c) => c['id'] == v,
                                  )['name']
                                  as String;
                        } else {
                          eDerslikAdi = null;
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final updatedList = List<AgmSlotTeacherEntry>.from(
                    slot.ogretmenGirisler,
                  );
                  final idx = updatedList.indexWhere(
                    (e) =>
                        e.dersId == entry.dersId &&
                        e.ogretmenId == entry.ogretmenId,
                  );

                  if (idx != -1) {
                    updatedList[idx] = AgmSlotTeacherEntry(
                      dersId: entry.dersId,
                      dersAdi: entry.dersAdi,
                      ogretmenId: eOgretmenId,
                      ogretmenAdi: eOgretmenAdi,
                      derslikId: eDerslikId,
                      derslikAdi: eDerslikAdi,
                      kapasite: eKapasite,
                    );

                    final updatedSlot = AgmTimeSlot(
                      id: slot.id,
                      institutionId: slot.institutionId,
                      ad: slot.ad,
                      gun: slot.gun,
                      baslangicSaat: slot.baslangicSaat,
                      bitisSaat: slot.bitisSaat,
                      ogretmenGirisler: updatedList,
                    );

                    await _repo.updateTimeSlotTeachers(slot.id, updatedList);
                    setState(() => _existingSlots[slotIndex] = updatedSlot);
                  }
                  if (context.mounted) Navigator.pop(ctx);
                },
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteSlot(AgmTimeSlot slot) async {
    // Arşivle (isActive = false yap)
    await _repo.deleteTimeSlot(slot.id);
    setState(() {
      final index = _allLibrarySlots.indexWhere((s) => s.id == slot.id);
      if (index != -1) {
        _allLibrarySlots[index] = AgmTimeSlot(
          id: slot.id,
          institutionId: slot.institutionId,
          ad: slot.ad,
          gun: slot.gun,
          baslangicSaat: slot.baslangicSaat,
          bitisSaat: slot.bitisSaat,
          ogretmenGirisler: slot.ogretmenGirisler,
          isActive: false,
        );
      }
      _existingSlots.removeWhere((s) => s.id == slot.id);
    });
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saat dilimi arşivlendi.')));
    }
  }

  // ════════════════════════════════════════════════════════
  //  CYCLE OLUŞTUR
  // ════════════════════════════════════════════════════════

  Future<void> _saveCycle() async {
    setState(() => _saving = true);
    final sw = Stopwatch()..start();
    print('DEBUG: [UI] _saveCycle entry');

    try {
      // 45 saniyelik genel bir zaman aşımı koruması
      await Future.any([
        _performSave(sw),
        Future.delayed(const Duration(seconds: 45)).then(
          (_) => throw Exception('İşlem 45 saniye sürdü ve iptal edildi (Zaman Aşımı)'),
        ),
      ]);
    } catch (e, stack) {
      print('DEBUG: [UI] _saveCycle GLOBAL ERROR: $e');
      print('DEBUG: [UI] $stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    } finally {
      print('DEBUG: [UI] _saveCycle finally exit at ${sw.elapsedMilliseconds}ms');
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _performSave(Stopwatch sw) async {
    print('DEBUG: [UI] _performSave starting');

    // 1) İstenen (güncel) grupları oluştur
    final List<AgmGroup> proposedGroups = [];
    for (final slot in _existingSlots) {
      for (final entry in slot.ogretmenGirisler) {
        proposedGroups.add(
          AgmGroup(
            id: '', 
            cycleId: widget.initialCycle?.id ?? '',
            institutionId: widget.institutionId,
            dersId: entry.dersId,
            dersAdi: entry.dersAdi,
            saatDilimiId: slot.id,
            saatDilimiAdi: slot.ad,
            gun: slot.gun,
            baslangicSaat: slot.baslangicSaat,
            bitisSaat: slot.bitisSaat,
            ogretmenId: entry.ogretmenId,
            ogretmenAdi: entry.ogretmenAdi,
            derslikId: entry.derslikId,
            derslikAdi: entry.derslikAdi,
            kapasite: entry.kapasite,
            mevcutOgrenciSayisi: 0,
          ),
        );
      }
    }

    // 2) Cycle nesnesini hazırla
    final cycle = AgmCycle(
      id: widget.initialCycle?.id ?? '',
      institutionId: widget.institutionId,
      schoolTypeId: widget.schoolTypeId,
      title: _titleController.text,
      referansDenemeSinavId: _selectedExamIds.isNotEmpty ? _selectedExamIds.first : '',
      referansDenemeSinavAdi: _selectedExamNames.isNotEmpty ? _selectedExamNames.first : '',
      referansDenemeSinavIds: _selectedExamIds,
      referansDenemeSinavAdlari: _selectedExamNames,
      baslangicTarihi: _baslangic,
      bitisTarihi: _bitis,
      status: widget.initialCycle?.status ?? AgmCycleStatus.draft,
      olusturulmaZamani: widget.initialCycle?.olusturulmaZamani ?? DateTime.now(),
      olusturanKullaniciId: widget.initialCycle?.olusturanKullaniciId ?? '',
      haftalikMaksimumSaat: _maxSaat,
      minimumDersSayisi: _minDers,
    );

    // 3) Servis üzerinden kaydet (SMART UPDATE)
    await _service.saveCycle(cycle: cycle, proposedGroups: proposedGroups);
    print('DEBUG: [UI] Service.saveCycle finished at ${sw.elapsedMilliseconds}ms');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.initialCycle != null
                ? 'Cycle başarıyla güncellendi!'
                : 'Cycle başarıyla oluşturuldu!',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  }

  Widget _buildSlotLibrary() {
    final activeLibrarySlots = _allLibrarySlots
        .where((s) => s.isActive)
        .toList();

    return Container(
      height: 140,
      width: double.infinity,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Slot Kütüphanesi (Tanımlı Dilimler)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.deepOrange,
              ),
            ),
          ),
          Expanded(
            child: activeLibrarySlots.isEmpty
                ? const Center(
                    child: Text(
                      'Henüz tanımlı slot yok',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: activeLibrarySlots.length,
                    itemBuilder: (context, i) {
                      final slot = activeLibrarySlots[i];
                      final isAdded = _existingSlots.any(
                        (s) => s.id == slot.id,
                      );

                      return Container(
                        width: 160,
                        margin: const EdgeInsets.only(right: 10, bottom: 12),
                        decoration: BoxDecoration(
                          color: isAdded
                              ? Colors.deepOrange.shade50
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isAdded
                                ? Colors.deepOrange.shade200
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: InkWell(
                          onTap: isAdded
                              ? null
                              : () {
                                  setState(() {
                                    _existingSlots.add(slot);
                                  });
                                },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 14,
                                      color: isAdded
                                          ? Colors.deepOrange
                                          : Colors.grey,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        slot.ad,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: isAdded
                                              ? Colors.deepOrange
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${slot.ogretmenGirisler.length} Grup Tanımlı',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const Spacer(),
                                if (isAdded)
                                  const Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        size: 16,
                                        color: Colors.green,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Eklendi',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  const Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      '+ Ekle',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.deepOrange,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  YARDIMCI WİDGET'LAR
  // ════════════════════════════════════════════════════════

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
    );
  }

  Widget _sectionHeader(String text, IconData icon, {String? subtitle}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.deepOrange),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDateButton({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    final formatter = DateFormat('dd.MM.yyyy');
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: Colors.deepOrange),
                const SizedBox(width: 6),
                Text(
                  formatter.format(date),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _baslangic : _bitis,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('tr'),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _baslangic = picked;
        } else {
          _bitis = picked;
        }
      });
    }
  }

  Widget _buildTimePicker({
    required BuildContext ctx,
    required String label,
    required TimeOfDay time,
    required Function(TimeOfDay) onPicked,
  }) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: ctx,
          initialTime: time,
          builder: (context, child) => Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Colors.deepOrange,
                onPrimary: Colors.white,
                onSurface: Colors.black87,
              ),
            ),
            child: child!,
          ),
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.access_time,
                  size: 14,
                  color: Colors.deepOrange,
                ),
                const SizedBox(width: 6),
                Text(
                  time.format(ctx),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassroomAnalysisPanel() {
    if (_existingSlots.isEmpty) return const SizedBox.shrink();

    final totalClassrooms = _classrooms.length;
    Map<String, int> slotNeeds = {};
    Map<String, int> unassignedInSlot = {};

    for (var slot in _existingSlots) {
      slotNeeds[slot.id] = slot.ogretmenGirisler.length;
      unassignedInSlot[slot.id] = slot.ogretmenGirisler
          .where((e) => e.derslikId == null)
          .length;
    }

    final maxNeed = slotNeeds.values.isEmpty
        ? 0
        : slotNeeds.values.reduce((a, b) => a > b ? a : b);
    final hasShortage = maxNeed > totalClassrooms;
    final hasUnassigned = unassignedInSlot.values.any((v) => v > 0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasShortage ? Colors.red.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasShortage ? Colors.red.shade200 : Colors.blue.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasShortage ? Icons.warning_amber : Icons.analytics_outlined,
                color: hasShortage ? Colors.red : Colors.blue.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Derslik İhtiyaç Analizi',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: hasShortage
                      ? Colors.red.shade900
                      : Colors.blue.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Toplam Kayıtlı Derslik: $totalClassrooms',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          Text(
            'En Yoğun Slot İhtiyacı: $maxNeed derslik',
            style: TextStyle(
              fontSize: 13,
              color: hasShortage ? Colors.red.shade700 : Colors.black87,
              fontWeight: hasShortage ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (hasShortage)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '⚠️ Dikkat: Mevcut derslik sayınız en yoğun saatteki ihtiyacı karşılamıyor. Bazı gruplar dersliksiz kalabilir.',
                style: TextStyle(fontSize: 12, color: Colors.red.shade800),
              ),
            ),
          if (hasUnassigned)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'ℹ️ Bazı gruplara henüz derslik atanmamış. Algoritma bu grupları boş dersliklere otomatik atamaya çalışacaktır.',
                style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSlotsHeader(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Bu Cycle\'daki Saat Dilimleri',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isMobile ? 18 : 16,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${_existingSlots.length} dilim seçildi',
          style: TextStyle(
            fontSize: isMobile ? 13 : 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderActionBtn({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.08),
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withOpacity(0.2)),
        ),
      ),
    );
  }
}
