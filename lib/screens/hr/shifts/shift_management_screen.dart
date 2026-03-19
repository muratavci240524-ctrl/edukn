import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../../../services/shift_service.dart';

class ShiftManagementScreen extends StatefulWidget {
  const ShiftManagementScreen({super.key});

  @override
  State<ShiftManagementScreen> createState() => _ShiftManagementScreenState();
}

class _ShiftManagementScreenState extends State<ShiftManagementScreen>
    with SingleTickerProviderStateMixin {
  final ShiftService _service = ShiftService();
  late TabController _tabController;

  bool _loading = true;
  String? _myInstitutionId;
  DateTime _selectedDate = DateTime.now();
  DateTime _calendarDate = DateTime.now();
  bool _isPersonalCalendar = false;
  String? _selectedCalendarStaffId;

  // Data
  List<Map<String, dynamic>> _templates = [];
  List<Map<String, dynamic>> _staffWithAssignments = [];
  Map<String, dynamic> _dailySummary = {};
  List<Map<String, dynamic>> _overtimes = [];
  Map<int, String> _calendarData = {};

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('tr_TR', null);
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadTabContent();
      }
    });
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _loading = true);
    await _getInstitutionId();
    await _loadTabContent();
    setState(() => _loading = false);
  }

  Future<void> _getInstitutionId() async {
    if (_myInstitutionId == null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Try to get from user document first for accuracy
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (userDoc.exists && userDoc.data()?['institutionId'] != null) {
          _myInstitutionId = userDoc.data()!['institutionId'];
          debugPrint('🆔 Found Institution ID in user doc: $_myInstitutionId');
        } else if (user.email != null) {
          // Fallback to email domain
          final domain = user.email!.split('@')[1];
          _myInstitutionId = domain.split('.')[0].toUpperCase();
          debugPrint('🆔 Derived Institution ID from email: $_myInstitutionId (${user.email})');
        }
      }
    }
  }

  Future<void> _loadTabContent() async {
    if (_myInstitutionId == null) return;
    if (!mounted) return;
    try {
      _staffWithAssignments = await _service.getAllStaffWithAssignments(_myInstitutionId!);

      switch (_tabController.index) {
        case 0: // Şablonlar
          _templates = await _service.getShiftTemplates(_myInstitutionId!);
          break;
        case 1: // Personel Atama
          _templates = await _service.getShiftTemplates(_myInstitutionId!);
          break;
        case 2: // Yoklama Takip
          _dailySummary = await _service.getDailySummary(_myInstitutionId!, DateFormat('yyyy-MM-dd').format(_selectedDate));
          break;
        case 3: // Fazla Mesai
          _overtimes = await _service.getStaffOvertime(_myInstitutionId!, DateFormat('yyyy-MM').format(_selectedDate));
          break;
        case 4: // Takvim
          final ym = DateFormat('yyyy-MM').format(_calendarDate);
          if (_isPersonalCalendar) {
            String? targetUid = _selectedCalendarStaffId ?? FirebaseAuth.instance.currentUser?.uid;
            if (targetUid != null) {
              _calendarData = await _service.getUserMonthlyStatus(targetUid, _myInstitutionId!, ym);
            }
          } else {
            _calendarData = await _service.getGeneralMonthlyStatus(_myInstitutionId!, ym, _staffWithAssignments.length);
          }
          break;
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading tab content: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
          ),
        ),
        child: Column(
          children: [
            _buildAppBar(),
            _buildTabBar(),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTemplatesTab(),
                      _buildStaffAssignmentTab(),
                      _buildAttendanceTab(),
                      _buildOvertimeTab(),
                      _buildCalendarTab(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildAnimatedFAB(),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, left: 20, right: 20, bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
          const SizedBox(width: 8),
          const Text('Mesai ve Vardiya', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const Spacer(),
          IconButton(onPressed: _loadTabContent, icon: const Icon(Icons.refresh, color: Color(0xFF6366F1))),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      width: double.infinity,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            labelColor: const Color(0xFF6366F1),
            unselectedLabelColor: const Color(0xFF94A3B8),
            indicator: const UnderlineTabIndicator(
              borderSide: BorderSide(width: 3.0, color: Color(0xFF6366F1)),
              insets: EdgeInsets.symmetric(horizontal: 16.0),
            ),
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(text: 'Şablonlar'),
              Tab(text: 'Personel Atama'),
              Tab(text: 'Yoklama Takip'),
              Tab(text: 'Fazla Mesai'),
              Tab(text: 'Aylık Takvim'),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildAnimatedFAB() {
    return ListenableBuilder(
      listenable: _tabController.animation!,
      builder: (context, child) {
        final index = _tabController.index;
        IconData? icon;
        String? label;
        VoidCallback? action;

        if (index == 0) {
          icon = Icons.add; label = 'Yeni Şablon'; action = _showAddTemplateView;
        } else if (index == 2) {
          icon = Icons.edit_calendar; label = 'Hızlı Giriş'; action = _showManualAttendanceView;
        } else if (index == 3) {
          icon = Icons.more_time; label = 'Mesai Ekle'; action = _showAddOvertimeView;
        }

        if (label == null) return const SizedBox.shrink();

        return FloatingActionButton.extended(
          onPressed: action,
          backgroundColor: const Color(0xFF6366F1),
          foregroundColor: Colors.white,
          elevation: 4,
          icon: Icon(icon, color: Colors.white),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        );
      },
    );
  }

  // ==================== TAB 1: TEMPLATES ====================
  Widget _buildTemplatesTab() {
    if (_templates.isEmpty) return _buildEmptyState('Henüz şablon tanımlanmamış.');
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _templates.length,
      itemBuilder: (context, index) {
        final t = _templates[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(15)),
                  child: const Icon(Icons.schedule, color: Color(0xFF6366F1), size: 28),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1E293B))),
                      const SizedBox(height: 6),
                      Text('${t['startTime']} - ${t['endTime']}', style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text('Mola: ${t['breakDuration']} dk | Tolerans: ${t['toleranceMinutes'] ?? 0} dk', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Color(0xFF64748B)),
                  onSelected: (val) {
                    if (val == 'delete') {
                      _deleteTemplate(t);
                    } else if (val == 'edit') {
                      _showAddTemplateView(template: t);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('Düzenle')])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, color: Colors.red, size: 18), SizedBox(width: 8), Text('Sil', style: TextStyle(color: Colors.red))])),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==================== TAB 2: STAFF ASSIGNMENT ====================
  Widget _buildStaffAssignmentTab() {
    if (_staffWithAssignments.isEmpty) return _buildEmptyState('Personel listesi yükleniyor veya boş.');
    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.1))),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Color(0xFF6366F1)),
              SizedBox(width: 12),
              Expanded(child: Text('Çalışanları mevcut çalışma şablonlarına buradan bağlayabilirsiniz. Her personelin bir çalışma planı olmalıdır.', style: TextStyle(color: Color(0xFF1E293B), fontSize: 13))),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _staffWithAssignments.length,
            itemBuilder: (context, index) {
              final s = _staffWithAssignments[index];
              final role = s['role'] ?? 'Personel';
              final currentTemplateId = s['assignment']?['templateId'];
              
              // Varsayılan kuralı uygula
              Map<String, dynamic>? assignedTemplate;

              if (currentTemplateId != null) {
                assignedTemplate = _templates.firstWhere((t) => t['id'] == currentTemplateId, orElse: () => _templates.isNotEmpty ? _templates.first : {'name': 'Atanmamış'});
              } else {
                // Şablona bak, ismine göre eşleşen var mı?
                final searchKey = (role == 'Öğretmen') ? 'Öğretmen' : 'Personel';
                try {
                  assignedTemplate = _templates.firstWhere((t) => t['name'].toString().toLowerCase().contains(searchKey.toLowerCase()));
                } catch (_) {
                  assignedTemplate = {'name': 'Atanmamış'};
                }
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2))],
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFEEF2FF),
                    child: Text(s['name']?[0] ?? 'P', style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                  ),
                  title: Text(s['name'] ?? 'İsimsiz Personel', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                  subtitle: Text('Rol: $role • Atanan: ${assignedTemplate['name']}', style: const TextStyle(color: Color(0xFF64748B))),
                  trailing: PopupMenuButton<String>(
                    onSelected: (tid) async {
                      await _service.assignTemplateToStaff(staffId: s['id'], templateId: tid, institutionId: _myInstitutionId!);
                      _loadTabContent();
                    },
                    itemBuilder: (ctx) => _templates.map((t) => PopupMenuItem<String>(value: t['id'], child: Text(t['name']))).toList(),
                    icon: const Icon(Icons.swap_horiz, color: Color(0xFF6366F1)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== TAB 3: ATTENDANCE ====================
  Widget _buildAttendanceTab() {
    final logs = _dailySummary['logs'] as List? ?? [];
    return Column(
      children: [
        _buildAttendanceHeader(),
        Expanded(
          child: logs.isEmpty 
            ? _buildEmptyState('Bu tarih için kayıt bulunamadı.') 
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: logs.length,
                itemBuilder: (ctx, i) {
                  final log = logs[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      title: Text(log['name'] ?? log['userId'].toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text('Durum: ${log['status'].toString().toUpperCase()}${log['checkInTime'] != null ? " • Giriş: ${log['checkInTime']}" : ""}${log['source'] == 'puantaj' ? ' (Puantaj)' : ''}', style: const TextStyle(fontSize: 12)),
                      trailing: _buildStatusBadge(log['status']),
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  Widget _buildAttendanceHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          _buildDateSelector(),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () async {
              await _service.markAllArrived(_myInstitutionId!, DateFormat('yyyy-MM-dd').format(_selectedDate), _staffWithAssignments.map((e) => e['id'] as String).toList());
              if (mounted) _loadTabContent();
            },
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('Toplu Onay'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2024), lastDate: DateTime.now(), locale: const Locale('tr', 'TR'));
        if (d != null) { _selectedDate = d; _loadTabContent(); }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Row(
          children: [
            const Icon(Icons.calendar_month, size: 18, color: Color(0xFF6366F1)),
            const SizedBox(width: 8),
            Text(DateFormat('d MMMM yyyy', 'tr_TR').format(_selectedDate), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          ],
        ),
      ),
    );
  }

  // ==================== TAB 4: OVERTIME ====================
  Widget _buildOvertimeTab() {
    if (_overtimes.isEmpty) return _buildEmptyState('Bu ay için fazla mesai kaydı yok.');
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _overtimes.length,
      itemBuilder: (ctx, i) {
        final o = _overtimes[i];
        final isPending = o['status'] == 'bekliyor';
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            title: Text(o['userId'].toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${DateFormat('d MMMM', 'tr_TR').format(DateTime.parse(o['date']))} • ${o['durationMinutes']} dk\n${o['description']}'),
            isThreeLine: true,
            trailing: isPending 
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.check_circle_outline, color: Colors.green), onPressed: () async { await _service.approveOvertime(o['id'], true); _loadTabContent(); }),
                    IconButton(icon: const Icon(Icons.cancel_outlined, color: Colors.red), onPressed: () async { await _service.approveOvertime(o['id'], false); _loadTabContent(); }),
                  ],
                )
              : _buildStatusBadge(o['status']),
          ),
        );
      },
    );
  }

  // ==================== TAB 5: CALENDAR ====================
  Widget _buildCalendarTab() {
    return Column(
      children: [
        _buildCalendarHeader(),
        _buildCalendarGrid(),
        _buildCalendarLegend(),
      ],
    );
  }

  void _changeMonth(int delta) {
    if (!mounted) return;
    setState(() {
      _calendarDate = DateTime(_calendarDate.year, _calendarDate.month + delta);
    });
    _loadTabContent();
  }

  Widget _buildCalendarHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left)),
              Text(DateFormat('MMMM yyyy', 'tr_TR').format(_calendarDate).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right)),
              const Spacer(),
              _buildCalendarToggle(),
            ],
          ),
          if (_isPersonalCalendar) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _pickCalendarStaff(),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.person_search, color: Color(0xFF6366F1), size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_selectedCalendarStaffId == null ? 'Giriş Yapan Kullanıcı (Siz)' : (_staffWithAssignments.firstWhere((s) => s['id'] == _selectedCalendarStaffId, orElse: () => {'name': '...'})['name']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)))),
                  const Icon(Icons.arrow_drop_down, color: Color(0xFF6366F1), size: 18),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _pickCalendarStaff() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _StaffPicker(
        staff: _staffWithAssignments,
        selectedIds: _selectedCalendarStaffId == null ? [] : [_selectedCalendarStaffId!],
        onSelected: (ids) {
          if (ids.isNotEmpty) {
            setState(() { _selectedCalendarStaffId = ids.first; _loadTabContent(); });
          }
        },
      ),
    );
  }

  Widget _buildCalendarToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(
        children: [
          _toggleBtn('Kurum', !_isPersonalCalendar, () => _setCalendarType(false)),
          _toggleBtn('Kişisel', _isPersonalCalendar, () => _setCalendarType(true)),
        ],
      ),
    );
  }

  Widget _toggleBtn(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: active ? const Color(0xFF6366F1) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: TextStyle(color: active ? Colors.white : const Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  void _setCalendarType(bool personal) {
    if (!mounted) return;
    setState(() {
      _isPersonalCalendar = personal;
    });
    _loadTabContent();
  }

  Widget _buildCalendarGrid() {
    final daysInMonth = DateTime(_calendarDate.year, _calendarDate.month + 1, 0).day;
    return Expanded(
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 1, mainAxisSpacing: 10, crossAxisSpacing: 10),
        itemCount: daysInMonth,
        itemBuilder: (ctx, i) {
          final day = i + 1;
          final status = _calendarData[day] ?? 'bos';
          return Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF1F5F9))),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(day.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                if (status != 'bos') Container(width: 8, height: 8, decoration: BoxDecoration(color: _getStatusColor(status), shape: BoxShape.circle)),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _getStatusColor(String status) {
    if (status == 'geldi') return Colors.green;
    if (status == 'geckaldi') return Colors.orange;
    if (status == 'gelmedi') return Colors.red;
    if (status == 'izinli') return Colors.blue;
    return Colors.transparent;
  }

  Widget _buildCalendarLegend() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _LegendItem(Colors.green, 'Tam'),
          _LegendItem(Colors.orange, 'Geç'),
          _LegendItem(Colors.red, 'Yok'),
          _LegendItem(Colors.blue, 'İzin'),
        ],
      ),
    );
  }

  // ==================== UTILS & SUB-VIEWS ====================
  Widget _buildStatusBadge(String status) {
    Color color = Colors.grey; if (status == 'geldi' || status == 'onaylandi') color = const Color(0xFF10B981);
    if (status == 'geckaldi') color = const Color(0xFFF59E0B); if (status == 'gelmedi' || status == 'reddedildi') color = const Color(0xFFEF4444);
    if (status == 'izinli') color = const Color(0xFF3B82F6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.layers_clear, size: 64, color: Colors.grey.shade300), const SizedBox(height: 16), Text(msg, style: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w500))]));
  }

  // --- FULL SCREEN MODALS ---
  void _showAddTemplateView({Map<String, dynamic>? template}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (ctx) => _TemplateAddScreen(institutionId: _myInstitutionId!, service: _service, template: template), fullscreenDialog: true));
    _loadTabContent();
  }

  void _deleteTemplate(Map<String, dynamic> template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Şablonu Sil'),
        content: Text('${template['name']} şablonunu silmek istediğinize emin misiniz? Bu işlem geri alınamaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('VAZGEÇ')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SİL', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await _service.deleteTemplate(template['id']);
      _loadTabContent();
    }
  }

  void _showManualAttendanceView() async {
    await Navigator.push(context, MaterialPageRoute(builder: (ctx) => _ManualAttendanceScreen(institutionId: _myInstitutionId!, staff: _staffWithAssignments, service: _service), fullscreenDialog: true));
    _loadTabContent();
  }

  void _showAddOvertimeView() async {
    await Navigator.push(context, MaterialPageRoute(builder: (ctx) => _AddOvertimeScreen(institutionId: _myInstitutionId!, staff: _staffWithAssignments, service: _service), fullscreenDialog: true));
    _loadTabContent();
  }
}

// ==================== SUB SCREENS ====================

class _TemplateAddScreen extends StatefulWidget {
  final String institutionId;
  final ShiftService service;
  final Map<String, dynamic>? template;
  const _TemplateAddScreen({required this.institutionId, required this.service, this.template});
  @override State<_TemplateAddScreen> createState() => _TemplateAddScreenState();
}

class _TemplateAddScreenState extends State<_TemplateAddScreen> {
  late final TextEditingController nameController;
  late final TextEditingController startController;
  late final TextEditingController endController;
  late final TextEditingController breakController;
  late final TextEditingController toleranceController;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.template?['name']);
    startController = TextEditingController(text: widget.template?['startTime'] ?? '08:30');
    endController = TextEditingController(text: widget.template?['endTime'] ?? '17:00');
    breakController = TextEditingController(text: widget.template?['breakDuration']?.toString() ?? '60');
    toleranceController = TextEditingController(text: widget.template?['toleranceMinutes']?.toString() ?? '15');
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Text(widget.template == null ? 'Yeni Şablon Oluştur' : 'Şablonu Düzenle'), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              _buildInputGroup('Genel Bilgiler', [
                _textField(nameController, 'Şablon İsmi (Örn: Öğretmen Mesai)', Icons.badge_outlined),
              ]),
              const SizedBox(height: 20),
              _buildInputGroup('Çalışma Saatleri', [
                Row(children: [
                  Expanded(child: _textField(startController, 'Giriş', Icons.login_rounded)),
                  const SizedBox(width: 16),
                  Expanded(child: _textField(endController, 'Çıkış', Icons.logout_rounded)),
                ]),
              ]),
              const SizedBox(height: 20),
              _buildInputGroup('Ek Süreler', [
                _textField(breakController, 'Mola (Dakika)', Icons.coffee_outlined, isNum: true),
                const SizedBox(height: 16),
                _textField(toleranceController, 'Giriş Toleransı (Dakika)', Icons.timer_outlined, isNum: true),
              ]),
              const SizedBox(height: 40),
              SizedBox(width: double.infinity, height: 60, child: ElevatedButton(
                onPressed: () async {
                  if (nameController.text.isEmpty) return;
                  if (widget.template == null) {
                    await widget.service.createShiftTemplate(
                      name: nameController.text, 
                      startTime: startController.text, 
                      endTime: endController.text, 
                      breakDuration: int.parse(breakController.text), 
                      toleranceMinutes: int.parse(toleranceController.text),
                      institutionId: widget.institutionId
                    );
                  } else {
                    await widget.service.updateShiftTemplate(
                      templateId: widget.template!['id'],
                      name: nameController.text, 
                      startTime: startController.text, 
                      endTime: endController.text, 
                      breakDuration: int.parse(breakController.text), 
                      toleranceMinutes: int.parse(toleranceController.text),
                    );
                  }
                  if (mounted) Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 4),
                child: Text(widget.template == null ? 'ŞABLONU KAYDET VE YAYINLA' : 'DEĞİŞİKLİKLERİ KAYDET', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white, letterSpacing: 1)),
              )),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildInputGroup(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 1.5))),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _textField(TextEditingController c, String l, IconData i, {bool isNum = false, int maxLines = 1}) => TextField(
    controller: c, 
    maxLines: maxLines,
    keyboardType: isNum ? TextInputType.number : TextInputType.text, 
    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
    decoration: InputDecoration(
      labelText: l, 
      prefixIcon: Icon(i, size: 22, color: const Color(0xFF6366F1)), 
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
    )
  );
}

class _ManualAttendanceScreen extends StatefulWidget {
  final String institutionId;
  final List<Map<String, dynamic>> staff;
  final ShiftService service;
  const _ManualAttendanceScreen({required this.institutionId, required this.staff, required this.service});
  @override State<_ManualAttendanceScreen> createState() => _ManualAttendanceScreenState();
}

class _ManualAttendanceScreenState extends State<_ManualAttendanceScreen> {
  String _searchText = "";
  @override Widget build(BuildContext context) {
    final filtered = widget.staff.where((s) => (s['name'] ?? '').toLowerCase().contains(_searchText.toLowerCase())).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Text('Hızlı Giriş Paneli'), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(20),
              child: TextField(
                onChanged: (v) => setState(() => _searchText = v), 
                decoration: InputDecoration(
                  hintText: 'İsim ile personel ara...', 
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF6366F1)), 
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                )
              ),
            ),
            Expanded(child: filtered.isEmpty 
              ? const Center(child: Text('Çalışan bulunamadı.', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final s = filtered[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)]),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: CircleAvatar(backgroundColor: const Color(0xFFEEF2FF), child: Text(s['name']?[0] ?? 'P', style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold))),
                        title: Text(s['name'] ?? 'P', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(s['role'] ?? 'Personel', style: const TextStyle(fontSize: 12)),
                        trailing: Wrap(spacing: 8, children: [
                          _actionBtn(ctx, s['id'], 'Geldı', const Color(0xFF10B981), 'geldi'),
                          _actionBtn(ctx, s['id'], 'YOK', const Color(0xFFEF4444), 'gelmedi'),
                        ]),
                      ),
                    );
                  },
                )
            ),
          ]),
        ),
      ),
    );
  }
  Widget _actionBtn(BuildContext ctx, String sid, String lbl, Color clr, String status) => ElevatedButton(
    onPressed: () async {
      await widget.service.markAttendanceManual(staffId: sid, institutionId: widget.institutionId, date: DateFormat('yyyy-MM-dd').format(DateTime.now()), status: status);
      if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$lbl kaydedildi'), backgroundColor: clr, behavior: SnackBarBehavior.floating));
    },
    style: ElevatedButton.styleFrom(backgroundColor: clr, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0),
    child: Text(lbl, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
  );
}

class _AddOvertimeScreen extends StatefulWidget {
  final String institutionId;
  final List<Map<String, dynamic>> staff;
  final ShiftService service;
  const _AddOvertimeScreen({required this.institutionId, required this.staff, required this.service});
  @override State<_AddOvertimeScreen> createState() => _AddOvertimeScreenState();
}

class _AddOvertimeScreenState extends State<_AddOvertimeScreen> {
  List<String> _selectedStaffIds = [];
  final _durationController = TextEditingController(text: '60');
  final _descController = TextEditingController();

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Text('Fazla Mesai Talebi'), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Text('PERSONEL SEÇİMİ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 1.5))),
        InkWell(
          onTap: () => _pickStaff(context),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Row(children: [
              Icon(Icons.people_outline, color: _selectedStaffIds.isEmpty ? const Color(0xFF94A3B8) : const Color(0xFF6366F1), size: 22),
              const SizedBox(width: 12),
              Expanded(child: _selectedStaffIds.isEmpty 
                ? const Text('Personel seçiniz...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13))
                : Wrap(spacing: 6, runSpacing: 6, children: _selectedStaffIds.map((id) {
                    final staff = widget.staff.firstWhere((s) => s['id'] == id, orElse: () => {'name': '...'});
                    return Chip(
                      label: Text(staff['name'] ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                      backgroundColor: const Color(0xFFEEF2FF),
                      deleteIcon: const Icon(Icons.close, size: 14, color: Color(0xFF6366F1)),
                      onDeleted: () => setState(() => _selectedStaffIds.remove(id)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    );
                  }).toList())
              ),
              const Icon(Icons.add_circle_outline, color: Color(0xFF6366F1), size: 20),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Text('MESAİ DETAYLARI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 1.5))),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Column(children: [
            _textField(_durationController, 'Süre (Dakika)', Icons.schedule_outlined, isNum: true),
            const SizedBox(height: 16),
            _textField(_descController, 'Açıklama / Neden', Icons.notes_rounded, maxLines: 3),
          ]),
        ),
        const SizedBox(height: 40),
        SizedBox(width: double.infinity, height: 60, child: ElevatedButton(
          onPressed: () async {
            if (_selectedStaffIds.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen personel seçin!'), backgroundColor: Colors.orange));
              return;
            }
            for (var staffId in _selectedStaffIds) {
              await widget.service.addOvertime(
                staffId: staffId, 
                institutionId: widget.institutionId, 
                date: DateFormat('yyyy-MM-dd').format(DateTime.now()), 
                durationMinutes: int.parse(_durationController.text), 
                description: _descController.text
              );
            }
            if (mounted) Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 4),
          child: const Text('TALEBİ OLUŞTUR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
        )),
      ])),
        ),
      ),
    );
  }

  void _pickStaff(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _StaffPicker(
        staff: widget.staff,
        selectedIds: _selectedStaffIds,
        onSelected: (ids) => setState(() => _selectedStaffIds = ids),
      ),
    );
  }

  Widget _textField(TextEditingController c, String l, IconData i, {bool isNum = false, int maxLines = 1}) => TextField(
    controller: c, 
    maxLines: maxLines,
    keyboardType: isNum ? TextInputType.number : TextInputType.text, 
    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
    decoration: InputDecoration(
      labelText: l, 
      prefixIcon: Icon(i, size: 22, color: const Color(0xFF6366F1)), 
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
    )
  );
}

class _StaffPicker extends StatefulWidget {
  final List<Map<String, dynamic>> staff;
  final List<String> selectedIds;
  final Function(List<String>) onSelected;
  const _StaffPicker({required this.staff, required this.selectedIds, required this.onSelected});
  @override State<_StaffPicker> createState() => _StaffPickerState();
}

class _StaffPickerState extends State<_StaffPicker> {
  String _search = "";
  String _selectedDept = "Hepsi";
  late List<String> _tempSelected;

  @override
  void initState() {
    super.initState();
    _tempSelected = List.from(widget.selectedIds);
  }

  @override Widget build(BuildContext context) {
    final depts = ["Hepsi", ...{...widget.staff.map((s) => s['department'] as String).where((d) => d != 'Genel')}];
    final filtered = widget.staff.where((s) {
      final nameMatches = (s['name'] ?? '').toLowerCase().contains(_search.toLowerCase());
      final deptMatches = _selectedDept == "Hepsi" || s['department'] == _selectedDept;
      return nameMatches && deptMatches;
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Personel Seç', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            TextButton(onPressed: () { widget.onSelected(_tempSelected); Navigator.pop(context); }, child: const Text('Tamamla', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
        )),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: TextField(
          onChanged: (v) => setState(() => _search = v),
          decoration: InputDecoration(
            hintText: 'Personel ara...',
            prefixIcon: const Icon(Icons.search, size: 20),
            filled: true,
            fillColor: const Color(0xFFF1F5F9),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            contentPadding: EdgeInsets.zero,
          ),
        )),
        const SizedBox(height: 12),
        SizedBox(
          height: 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: depts.length,
            itemBuilder: (ctx, i) {
              final d = depts[i];
              final isSel = _selectedDept == d;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(d, style: TextStyle(fontSize: 11, color: isSel ? Colors.white : const Color(0xFF64748B), fontWeight: FontWeight.bold)),
                  selected: isSel,
                  onSelected: (v) => setState(() => _selectedDept = d),
                  selectedColor: const Color(0xFF6366F1),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: isSel ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: filtered.isEmpty ? const Center(child: Text('Personel bulunamadı.')) : ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (ctx, i) {
            final s = filtered[i];
            final isChecked = _tempSelected.contains(s['id']);
            return CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              value: isChecked,
              onChanged: (v) => setState(() { v! ? _tempSelected.add(s['id']) : _tempSelected.remove(s['id']); }),
              title: Text(s['name'] ?? '...', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text('${s['role'] ?? ''} • ${s['department']}', style: const TextStyle(fontSize: 11)),
              activeColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            );
          },
        )),
        const SizedBox(height: 20),
      ]),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem(this.color, this.label);
  @override Widget build(BuildContext context) {
    return Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)))]);
  }
}
