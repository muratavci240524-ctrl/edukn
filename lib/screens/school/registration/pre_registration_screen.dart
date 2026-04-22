import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../services/user_permission_service.dart';
import 'add_pre_registration_screen.dart';
import 'pre_registration_settings_screen.dart';
import '../../../services/pdf_service.dart';
import 'package:printing/printing.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../constants/turkey_address_data.dart';
import '../../../widgets/edukn_dropdown.dart';
import '../../../widgets/edukn_logo.dart';

class PreRegistrationScreen extends StatefulWidget {
  const PreRegistrationScreen({Key? key}) : super(key: key);

  @override
  _PreRegistrationScreenState createState() => _PreRegistrationScreenState();
}

class _PreRegistrationScreenState extends State<PreRegistrationScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  String? _institutionId;
  Map<String, dynamic>? userData;
  List<Map<String, dynamic>> _preRegistrations = [];
  List<Map<String, dynamic>> _filteredPreRegistrations = [];
  Map<String, dynamic>? _selectedPreReg;
  bool _isAdding = false;
  String? _selectedPreRegId;

  // Filtreler
  String _statusFilter = 'pending';
  String? _selectedTermFilter;
  String? _schoolTypeFilter;
  String? _gradeLevelFilter;
  List<Map<String, dynamic>> _terms = [];
  List<Map<String, dynamic>> _schoolTypes = [];
  DateTime? _priceDate; // For price robot date selection
  String? _lastPricedStudentId; // Track which student's prices were last loaded
  Map<String, String?> _perTypePaymentMethod = {};
  Map<String, dynamic> _cachedSettings = {}; // Settings cached to avoid repeated Firestore fetches


  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final data = await UserPermissionService.loadUserData();
      setState(() => userData = data);
      
      if (data != null && data['institutionId'] != null) {
        _institutionId = data['institutionId'];
      } else {
        final email = user.email!;
        _institutionId = email.split('@')[1].split('.')[0].toUpperCase();
      }

      final termsQuery = await FirebaseFirestore.instance
          .collection('terms')
          .where('institutionId', isEqualTo: _institutionId)
          .get();
      _terms = termsQuery.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      
      final schoolTypesQuery = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .where('institutionId', isEqualTo: _institutionId)
          .get();
      _schoolTypes = schoolTypesQuery.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();

      if (_terms.isNotEmpty) {
        _selectedTermFilter = _terms.firstWhere((t) => t['isActive'] == true, orElse: () => _terms.first)['id'];
      }

      // Load settings once and cache
      final settingsDoc = await FirebaseFirestore.instance.collection('preRegistrationSettings').doc(_institutionId).get();
        setState(() => _cachedSettings = settingsDoc.data() ?? {});

      await _loadPreRegistrations();
    } catch (e) {
      debugPrint('Error loading initial data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPreRegistrations() async {
    if (_institutionId == null) return;

    final query = await FirebaseFirestore.instance
        .collection('preRegistrations')
        .where('institutionId', isEqualTo: _institutionId)
        .orderBy('meetingDate', descending: true)
        .get();

    setState(() {
      _preRegistrations = query.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      _filterPreRegistrations();
      // CRITICAL: sync _selectedPreReg with fresh data from Firestore
      if (_selectedPreRegId != null) {
        final updated = _preRegistrations.firstWhere(
          (r) => r['id'] == _selectedPreRegId,
          orElse: () => _selectedPreReg ?? {},
        );
        if (updated.isNotEmpty) _selectedPreReg = updated;
      }
    });
  }

  void _filterPreRegistrations() {
    final query = _searchController.text.toLowerCase();
    _filteredPreRegistrations = _preRegistrations.where((reg) {
      final matchesSearch = (reg['fullName'] ?? '').toLowerCase().contains(query) ||
          (reg['phone'] ?? '').toLowerCase().contains(query);
      
      final matchesStatus = _statusFilter == 'all' || 
          (_statusFilter == 'pending' && (reg['status'] == 'pending' || reg['status'] == null)) ||
          (_statusFilter == 'converted' && (reg['isConverted'] == true)) ||
          (_statusFilter == 'negative' && (reg['status'] == 'negative'));
          
      final matchesTerm = _selectedTermFilter == null || reg['termId'] == _selectedTermFilter;
      final matchesSchoolType = _schoolTypeFilter == null || reg['schoolTypeId'] == _schoolTypeFilter;
      final matchesGrade = _gradeLevelFilter == null || reg['classLevel'] == _gradeLevelFilter;

      return matchesSearch && matchesStatus && matchesTerm && matchesSchoolType && matchesGrade;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isWideScreen = MediaQuery.of(context).size.width > 900;

    // MOBILE REACTIVE DETAIL VIEW
    if (!isWideScreen && _selectedPreReg != null) {
      return WillPopScope(
        onWillPop: () async {
          setState(() {
            _selectedPreReg = null;
            _selectedPreRegId = null;
          });
          return false;
        },
        child: Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1E293B), size: 18),
              onPressed: () => setState(() {
                _selectedPreReg = null;
                _selectedPreRegId = null;
              }),
            ),
            title: Text(_selectedPreReg!['fullName'] ?? 'Aday Detayı', 
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: const Color(0xFF1E293B))),
            centerTitle: true,
          ),
          body: _buildPreRegDetail(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Ön Kayıt ve Görüşme Yönetimi', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Fiyat ve İndirim Ayarları',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PreRegistrationSettingsScreen(
                    institutionId: _institutionId!,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_task_rounded),
            onPressed: () => _handleAddNew(),
            tooltip: 'Yeni Ön Kayıt / Görüşme',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: isWideScreen
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 400, child: _buildPreRegList()),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: _isAdding
                            ? PreRegistrationFormWidget(
                                institutionId: _institutionId,
                                selectedTermId: _selectedTermFilter,
                                schoolTypes: _schoolTypes,
                                onCancel: () => setState(() => _isAdding = false),
                                onSave: () {
                                  setState(() => _isAdding = false);
                                  _loadPreRegistrations();
                                },
                              )
                            : _selectedPreReg != null
                                ? _buildPreRegDetail()
                                : _buildEmptyDetailPlaceholder(),
                      ),
                    ),
                  ),
                ],
              )
            : _preRegistrations.isEmpty ? _buildEmptyState() : _buildPreRegList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.contact_phone_rounded, size: 80, color: Colors.indigo.shade400),
          ),
          const SizedBox(height: 24),
          Text(
            'Henüz Ön Kayıt Bulunmuyor',
            style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 12),
          Text(
            'Aday görüşmelerinizi buradan kaydederek\nprofesyonelce takip edebilirsiniz.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 16),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => _handleAddNew(),
            icon: const Icon(Icons.add, color: Colors.white),
            label: Text('İLK ÖN KAYDI OLUŞTUR', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
            ),
          ),
        ],
      ),
    );
  }

  void _handleAddNew() async {
    if (MediaQuery.of(context).size.width > 900) {
      setState(() {
        _isAdding = true;
        _selectedPreRegId = null;
        _selectedPreReg = null;
      });
    } else {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AddPreRegistrationScreen(
            institutionId: _institutionId,
            selectedTermId: _selectedTermFilter,
            schoolTypes: _schoolTypes,
          ),
        ),
      );
      if (result == true) _loadPreRegistrations();
    }
  }

  Widget _buildPreRegList() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() => _filterPreRegistrations()),
                style: GoogleFonts.inter(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'İsim veya telefon ara...',
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.indigo),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _schoolTypeFilter,
                          hint: Text('Tüm Türler', style: GoogleFonts.inter(fontSize: 13)),
                          isExpanded: true,
                          items: [
                            DropdownMenuItem(value: null, child: Text('Tüm Türler', style: GoogleFonts.inter(fontSize: 13))),
                            ..._schoolTypes.map((t) => DropdownMenuItem(value: t['id'], child: Text(t['schoolTypeName'] ?? t['typeName'] ?? '', style: GoogleFonts.inter(fontSize: 13)))),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _schoolTypeFilter = v;
                              _filterPreRegistrations();
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _gradeLevelFilter,
                          hint: Text('Tüm Kademeler', style: GoogleFonts.inter(fontSize: 13)),
                          isExpanded: true,
                          items: [
                            DropdownMenuItem(value: null, child: Text('Tüm Kademeler', style: GoogleFonts.inter(fontSize: 13))),
                            ...['3 YAŞ', '4 YAŞ', '5 YAŞ', '1. SINIF', '2. SINIF', '3. SINIF', '4. SINIF', '5. SINIF', '6. SINIF', '7. SINIF', '8. SINIF', '9. SINIF', '10. SINIF', '11. SINIF', '12. SINIF', 'MEZUN']
                                .where((l) => _preRegistrations.any((r) => r['classLevel'] == l))
                                .map((l) => DropdownMenuItem(value: l, child: Text(_formatLevelLabel(l), style: GoogleFonts.inter(fontSize: 13)))),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _gradeLevelFilter = v;
                              _filterPreRegistrations();
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildStatusChip('pending', 'Bekleyen', Icons.schedule_rounded),
                    const SizedBox(width: 8),
                    _buildStatusChip('converted', 'Kaydolmuş', Icons.verified_rounded),
                    const SizedBox(width: 8),
                    _buildStatusChip('negative', 'Olumsuz', Icons.cancel_rounded),
                    const SizedBox(width: 8),
                    _buildStatusChip('all', 'Hepsi', Icons.list_rounded),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _filteredPreRegistrations.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  itemCount: _filteredPreRegistrations.length,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemBuilder: (context, index) {
                    final reg = _filteredPreRegistrations[index];
                    final isSelected = reg['id'] == _selectedPreRegId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedPreReg = reg;
                            _selectedPreRegId = reg['id'];
                            _isAdding = false;
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.indigo.shade50 : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isSelected ? Colors.indigo : Colors.transparent, width: 1.5),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: reg['isConverted'] == true ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  reg['isConverted'] == true ? Icons.how_to_reg_rounded : Icons.person_search_rounded,
                                  color: reg['isConverted'] == true ? Colors.green : Colors.orange,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(reg['fullName'] ?? 'İsimsiz', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_getSchoolTypeName(reg['schoolTypeId'])} • ${_formatLevelLabel(reg['classLevel'])}',
                                      style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8), size: 20),
                                onSelected: (val) {
                                  if (val == 'edit') {
                                    _handleEdit(reg);
                                  } else if (val == 'delete') {
                                    _handleDelete(reg['id']);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(value: 'edit', child: ListTile(leading: const Icon(Icons.edit_rounded, size: 18), title: const Text('Düzenle'), dense: true)),
                                  PopupMenuItem(value: 'delete', child: ListTile(leading: const Icon(Icons.delete_rounded, size: 18, color: Colors.red), title: const Text('Sil', style: TextStyle(color: Colors.red)), dense: true)),
                                ],
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
    );
  }

  Widget _buildStatusChip(String value, String label, IconData icon) {
    final isSelected = _statusFilter == value;
    return InkWell(
      onTap: () {
        setState(() => _statusFilter = value);
        _filterPreRegistrations();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.indigo : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : const Color(0xFF64748B)),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.inter(color: isSelected ? Colors.white : const Color(0xFF64748B), fontSize: 12, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildPreRegDetail() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(27),
            ),
            child: TabBar(
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.all(4),
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(27),
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              labelColor: Colors.indigo,
              unselectedLabelColor: const Color(0xFF64748B),
              overlayColor: MaterialStateProperty.all(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
              labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
              tabs: const [
                Tab(text: 'Görüşme Bilgileri'),
                Tab(text: 'Fiyat Robotu / Teklif'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildMeetingInfoTab(),
                _buildPriceRobotTab(),
              ],
            ),
          ),
          _buildActionFooter(),
        ],
      ),
    );
  }

  Widget _buildMeetingInfoTab() {
    final reg = _selectedPreReg!;
    final date = (reg['meetingDate'] as Timestamp?)?.toDate();
    final dateStr = date != null ? DateFormat('dd.MM.yyyy HH:mm').format(date) : '-';
    final addr = reg['address'] as Map<String, dynamic>? ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            title: 'Aday Bilgileri',
            icon: Icons.person_rounded,
            onTap: () => _editCandidateInfo(reg),
            children: [
              _buildDetailRow('Ad Soyad', reg['fullName']),
              _buildDetailRow('Cinsiyet', reg['gender'] ?? '-'),
              _buildDetailRow('Sınıf Seviyesi', _formatLevelLabel(reg['classLevel'])),
              _buildDetailRow('Okul Türü', _getSchoolTypeName(reg['schoolTypeId'])),
              _buildDetailRow('Eski Okulu', reg['previousSchool'] ?? '-'),
            ],
          ),
          _buildInfoCard(
            title: 'Veli Bilgileri',
            icon: Icons.family_restroom_rounded,
            onTap: () => _editGuardianInfo(reg),
            children: [
              _buildDetailRow('Veli Adı', reg['guardian1Name'] ?? reg['guardianName']),
              _buildDetailRow('İletişim No', reg['phone']),
              _buildDetailRow('E-posta', reg['email'] ?? '-'),
              _buildDetailRow('Yakınlık', reg['guardian1Kinship'] ?? reg['relationship'] ?? '-'),
              _buildDetailRow('Meslek', reg['guardianJob'] ?? '-'),
            ],
          ),
          _buildInfoCard(
            title: 'Adres Bilgileri',
            icon: Icons.location_on_rounded,
            onTap: () => _editAddressInfo(reg),
            children: [
              _buildDetailRow('Şehir / İlçe', '${addr['city'] ?? '-'} / ${addr['district'] ?? '-'}'),
              _buildDetailRow('Mahalle / Adres', addr['neighborhood'] ?? addr['fullAddress'] ?? '-'),
            ],
          ),
          _buildInfoCard(
            title: 'Görüşme Detayı',
            icon: Icons.event_note_rounded,
            onTap: () => _editMeetingMeta(reg),
            children: [
              _buildDetailRow('Görüşme Tarihi', dateStr),
              _buildDetailRow('Görüşen Kişi', reg['interviewerName'] ?? '-'),
              _buildDetailRow('Nasıl Haberdar Oldu?', reg['discoverySource'] ?? '-'),
            ],
          ),
          _buildNotesSection(reg),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildNotesSection(Map<String, dynamic> reg) {
    final List<dynamic> notes = reg['notes'] as List<dynamic>? ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.edit_note_rounded, color: Colors.indigo, size: 22),
                const SizedBox(width: 8),
                Text('Görüşme Notları', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: const Color(0xFF1E293B))),
              ],
            ),
          ),
          const Divider(height: 1),
          if (notes.isEmpty && (reg['meetingNotes'] ?? '').toString().isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('Henüz not eklenmemiş.', style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 14)),
              ),
            )
          else
            ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                if ((reg['meetingNotes'] ?? '').toString().isNotEmpty)
                  _buildNoteItem({
                    'note': reg['meetingNotes'],
                    'author': reg['interviewerName'] ?? 'Sistem',
                    'date': reg['meetingDate'],
                  }),
                ...notes.map((n) => _buildNoteItem(n as Map<String, dynamic>)),
              ],
            ),
          _buildAddNoteField(),
        ],
      ),
    );
  }

  Widget _buildNoteItem(Map<String, dynamic> noteData) {
    final date = (noteData['date'] as Timestamp?)?.toDate();
    final dateStr = date != null ? DateFormat('dd.MM.yyyy HH:mm').format(date) : '-';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(noteData['author'] ?? 'Hocamız', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.indigo)),
              Text(dateStr, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
            ],
          ),
          const SizedBox(height: 6),
          Text(noteData['note'] ?? '', style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF334155), height: 1.5)),
        ],
      ),
    );
  }

  final TextEditingController _newNoteController = TextEditingController();

  Widget _buildAddNoteField() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _newNoteController,
              style: GoogleFonts.inter(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Yeni not ekleyin...',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: () => _addNote(),
            icon: const Icon(Icons.send_rounded, size: 20),
            style: IconButton.styleFrom(backgroundColor: Colors.indigo),
          ),
        ],
      ),
    );
  }

  Future<void> _addNote() async {
    if (_newNoteController.text.trim().isEmpty) return;
    try {
      final newNote = {
        'note': _newNoteController.text.trim(),
        'author': userData?['fullName'] ?? 'Yönetici',
        'date': Timestamp.now(),
      };
      
      await FirebaseFirestore.instance.collection('preRegistrations').doc(_selectedPreRegId).update({
        'notes': FieldValue.arrayUnion([newNote]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      _newNoteController.clear();
      _loadPreRegistrations();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not başarıyla eklendi.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Not ekleme hatası: $e')));
    }
  }

  Widget _buildInfoCard({required String title, required IconData icon, required List<Widget> children, VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Icon(icon, color: Colors.indigo, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: const Color(0xFF1E293B))),
                  ],
                ),
                const SizedBox(height: 16),
                ...children,
              ],
            ),
          ),
          if (onTap != null)
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: const Icon(Icons.edit_rounded, color: Colors.indigo, size: 18),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value?.isNotEmpty == true ? value! : '-', style: GoogleFonts.inter(color: const Color(0xFF334155), fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showEditBottomSheet(String title, List<Widget> fields, VoidCallback onSave) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          top: 24,
          left: 24,
          right: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ],
            ),
            const SizedBox(height: 24),
            ...fields,
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () {
                  onSave();
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text('DEĞİŞİKLİKLERİ KAYDET', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _editCandidateInfo(Map<String, dynamic> reg) {
    final nameCtrl = TextEditingController(text: reg['fullName']);
    final schoolCtrl = TextEditingController(text: reg['previousSchool']);
    String? selectedLevel = reg['classLevel']?.toString()
        .replaceAll('. Sınıf', '')
        .replaceAll('. SINIF', '')
        .trim()
        .toUpperCase();
    
    // Ensure the selectedLevel exists in our items list, if not set null
    final List<String> levelItems = ['3 YAŞ', '4 YAŞ', '5 YAŞ', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', 'MEZUN'];
    if (selectedLevel != null && !levelItems.contains(selectedLevel)) {
      selectedLevel = null;
    }

    String? selectedType = reg['schoolTypeId'];
    String? selectedGender = reg['gender'] ?? 'Erkek';
    
    _showEditBottomSheet(
      'Aday Bilgilerini Düzenle',
      [
        _buildPopupField('Ad Soyad', nameCtrl),
        _buildPopupField('Eski Okulu', schoolCtrl),
        StatefulBuilder(builder: (context, setModalState) {
          return Column(
            children: [
              EduKnDropdown<String>(
                label: 'Sınıf Seviyesi',
                value: selectedLevel,
                items: levelItems
                    .map((l) => DropdownMenuItem<String>(value: l, child: Text(_formatLevelLabel(l)))).toList(),
                onChanged: (v) => setModalState(() => selectedLevel = v),
              ),
              const SizedBox(height: 12),
              EduKnDropdown<String>(
                label: 'Okul Türü',
                value: selectedType,
                items: _schoolTypes.map((t) => DropdownMenuItem<String>(value: t['id'], child: Text(t['schoolTypeName'] ?? t['typeName'] ?? ''))).toList(),
                onChanged: (v) => setModalState(() => selectedType = v),
              ),
              const SizedBox(height: 12),
              EduKnDropdown<String>(
                label: 'Cinsiyet',
                value: selectedGender,
                items: ['Erkek', 'Kız'].map((g) => DropdownMenuItem<String>(value: g, child: Text(g))).toList(),
                onChanged: (v) => setModalState(() => selectedGender = v),
              ),
            ],
          );
        }),
      ],
      () async {
        await FirebaseFirestore.instance.collection('preRegistrations').doc(reg['id']).update({
          'fullName': nameCtrl.text.toUpperCase(),
          'previousSchool': schoolCtrl.text,
          'classLevel': selectedLevel,
          'schoolTypeId': selectedType,
          'gender': selectedGender,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _loadPreRegistrations();
      }
    );
  }

  void _editGuardianInfo(Map<String, dynamic> reg) {
    final nameCtrl = TextEditingController(text: reg['guardian1Name'] ?? reg['guardianName']);
    final phoneCtrl = TextEditingController(text: reg['phone']);
    final emailCtrl = TextEditingController(text: reg['email']);
    final relationCtrl = TextEditingController(text: reg['guardian1Kinship'] ?? reg['relationship']);
    final jobCtrl = TextEditingController(text: reg['guardianJob']);
    
    _showEditBottomSheet(
      'Veli Bilgilerini Düzenle',
      [
        _buildPopupField('Veli Ad Soyad', nameCtrl),
        _buildPopupField('İletişim No', phoneCtrl),
        _buildPopupField('E-posta', emailCtrl),
        _buildPopupField('Yakınlık Derecesi', relationCtrl),
        _buildPopupField('Veli Mesleği', jobCtrl),
      ],
      () async {
        await FirebaseFirestore.instance.collection('preRegistrations').doc(reg['id']).update({
          'guardian1Name': nameCtrl.text.toUpperCase(),
          'phone': phoneCtrl.text,
          'email': emailCtrl.text.toLowerCase(),
          'guardian1Kinship': relationCtrl.text,
          'guardianJob': jobCtrl.text,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _loadPreRegistrations();
      }
    );
  }

  void _editAddressInfo(Map<String, dynamic> reg) {
    final addr = reg['address'] as Map<String, dynamic>? ?? {};
    final cityCtrl = TextEditingController(text: addr['city'] ?? reg['city']);
    final distCtrl = TextEditingController(text: addr['district'] ?? reg['district']);
    final neighborhoodCtrl = TextEditingController(text: addr['neighborhood'] ?? reg['neighborhood'] ?? addr['fullAddress']);
    
    _showEditBottomSheet(
      'Adres Bilgilerini Düzenle',
      [
        StatefulBuilder(builder: (context, setModalState) {
          final currentCity = cityCtrl.text.toUpperCase();
          final currentDist = distCtrl.text.toUpperCase();
          
          return Column(
            children: [
              EduKnDropdown<String>(
                label: 'İl',
                value: TurkeyAddressData.cities.contains(currentCity) ? currentCity : null,
                items: TurkeyAddressData.cities
                    .map((c) => DropdownMenuItem<String>(value: c, child: Text(c))).toList(),
                onChanged: (v) {
                  setModalState(() {
                    cityCtrl.text = v ?? '';
                    distCtrl.text = ''; // Reset district when city changes
                  });
                },
              ),
              const SizedBox(height: 12),
              EduKnDropdown<String>(
                label: 'İlçe',
                value: (cityCtrl.text.isNotEmpty && 
                        TurkeyAddressData.getDistricts(cityCtrl.text).contains(currentDist)) 
                    ? currentDist 
                    : null,
                items: (cityCtrl.text.isNotEmpty)
                    ? TurkeyAddressData.getDistricts(cityCtrl.text)
                        .map((d) => DropdownMenuItem<String>(value: d, child: Text(d))).toList()
                    : [],
                onChanged: (v) => setModalState(() => distCtrl.text = v ?? ''),
              ),
              const SizedBox(height: 12),
            ],
          );
        }),
        _buildPopupField('Mahalle / Tam Adres', neighborhoodCtrl),
      ],
      () async {
        await FirebaseFirestore.instance.collection('preRegistrations').doc(reg['id']).update({
          'address': {
            'city': cityCtrl.text.toUpperCase(),
            'district': distCtrl.text.toUpperCase(),
            'neighborhood': neighborhoodCtrl.text.toUpperCase(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _loadPreRegistrations();
      }
    );
  }

  void _editMeetingMeta(Map<String, dynamic> reg) {
    final intCtrl = TextEditingController(text: reg['interviewerName']);
    final srcCtrl = TextEditingController(text: reg['discoverySource']);
    
    _showEditBottomSheet(
      'Görüşme Detaylarını Düzenle',
      [
        _buildPopupField('Görüşmeyi Yapan', intCtrl),
        _buildPopupField('Kaynağı', srcCtrl),
      ],
      () async {
        await FirebaseFirestore.instance.collection('preRegistrations').doc(reg['id']).update({
          'interviewerName': intCtrl.text,
          'discoverySource': srcCtrl.text,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _loadPreRegistrations();
      }
    );
  }

  Widget _buildPopupField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
      ),
    );
  }

  Widget _buildPriceRobotTab() {
    final reg = _selectedPreReg!;
    final offer = Map<String, dynamic>.from(reg['priceOffer'] as Map? ?? {});
    
    // Sync _perTypePaymentMethod state with reg data at first load
    if (_perTypePaymentMethod.isEmpty && offer.containsKey('perTypePaymentMethods')) {
      final savedMethods = offer['perTypePaymentMethods'] as Map<String, dynamic>;
      savedMethods.forEach((key, value) {
        _perTypePaymentMethod[key] = value?.toString();
      });
    }

    // Use cached settings — no Firestore call on every rebuild
    final settings = _cachedSettings;
    
    // If settings not loaded yet, show spinner
    if (settings.isEmpty && _institutionId != null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    final priceTypes = settings['priceTypes'] as List<dynamic>? ?? ['Eğitim', 'Yemek'];
    final discounts = settings['discounts'] as List<dynamic>? ?? [];
    final paymentMethods = settings['paymentMethods'] as List<dynamic>? ?? [];

    // Reload prices from Settings whenever a new student is selected
    final needsPriceLoad = _lastPricedStudentId != _selectedPreRegId;
    if (needsPriceLoad) {
      _lastPricedStudentId = _selectedPreRegId; // Mark as loading started to avoid duplicate calls
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _generateAutoOffer(settings);
        }
      });
      return const Center(child: EduKnLoader(size: 80));
    }

    final selectedPaymentMethodId = offer['selectedPaymentMethodId'];
    
    double subtotal = 0.0;
    for (var type in priceTypes) {
      subtotal += (offer[type] ?? 0.0).toDouble();
    }
    final totalDiscount = (offer['discount'] ?? 0.0).toDouble();
    double netBeforePayment = (offer['total'] ?? 0.0).toDouble();
    
    double paymentMethodDiscountAmount = 0.0;
    if (selectedPaymentMethodId != null) {
      final method = paymentMethods.firstWhere((m) => m['id'] == selectedPaymentMethodId, orElse: () => {});
      if (method.isNotEmpty) {
        final discPerc = (method['discount'] as num?)?.toDouble() ?? 0.0;
        paymentMethodDiscountAmount = netBeforePayment * (discPerc / 100);
      }
    }
    final finalNetTotal = netBeforePayment - paymentMethodDiscountAmount;

    // Calculate per-type final amounts (CORRECTED: including global discounts)
    double perTypeGrandTotal = 0.0;
    bool anyPerTypeSelected = _perTypePaymentMethod.values.any((v) => v != null);
    if (anyPerTypeSelected) {
      for (var type in priceTypes) {
        final typeStr = type.toString();
        final baseAmt = (offer[typeStr] ?? 0.0).toDouble();
        
        // 1. Apply applicable global discounts to this type's base amount
        double amtAfterGlobal = baseAmt;
        final appliedIds = offer['appliedDiscounts'] as List<dynamic>? ?? [];
        for (var d in discounts) {
          if (appliedIds.contains(d['id'])) {
            final perc = (offer['_manualPerc_${d['id']}'] as num?)?.toDouble() ?? (d['percentage'] as num?)?.toDouble() ?? 0.0;
            final dApplyToRaw = d['applyTo'] as List<dynamic>?;
            
            if (dApplyToRaw == null || dApplyToRaw.isEmpty) {
              // DEFAULT: Apply to all (Global)
              amtAfterGlobal -= baseAmt * (perc / 100);
            } else {
              final typeLow = typeStr.toLowerCase().replaceAll('ğ', 'g').replaceAll('ş', 's').replaceAll('ı', 'i').replaceAll('ü', 'u').replaceAll('ö', 'o').replaceAll('ç', 'c');
              bool applyToThisType = false;
              for (var a in dApplyToRaw) {
                final aLow = a.toString().toLowerCase().replaceAll('ğ', 'g').replaceAll('ş', 's').replaceAll('ı', 'i').replaceAll('ü', 'u').replaceAll('ö', 'o').replaceAll('ç', 'c');
                if (typeLow.contains(aLow) || aLow.contains(typeLow)) {
                  applyToThisType = true;
                  break;
                }
              }
              if (applyToThisType) {
                amtAfterGlobal -= baseAmt * (perc / 100);
              }
            }
          }
        }

        // 2. Apply per-type payment method discount
        final methodId = _perTypePaymentMethod[typeStr];
        double finalAmt = amtAfterGlobal;
        if (methodId != null) {
          final method = paymentMethods.firstWhere((m) => m['id'] == methodId, orElse: () => {});
          if (method.isNotEmpty) {
            final disc = (method['discount'] as num?)?.toDouble() ?? 0.0;
            finalAmt = amtAfterGlobal * (1 - disc / 100);
          }
        }
        perTypeGrandTotal += finalAmt;
      }
    }

    return ScrollConfiguration(
      behavior: const ScrollBehavior().copyWith(
        dragDevices: {PointerDeviceKind.mouse, PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.trackpad},
      ),
      child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Stats Row with date selector on top-right
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildPriceCircle('TOPLAM', subtotal, Colors.indigo),
                        _buildPriceCircle('İNDİRİM', totalDiscount, Colors.orange),
                        _buildPriceCircle('NET TUTAR', anyPerTypeSelected ? perTypeGrandTotal : finalNetTotal, Colors.green),
                      ],
                    ),
                  ),
                  // Date selector button
                  GestureDetector(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _priceDate ?? now,
                        firstDate: DateTime(now.year - 3),
                        lastDate: DateTime(now.year + 2),
                        helpText: 'Fiyat Tarihi Seçin',
                        locale: const Locale('tr', 'TR'),
                      );
                      if (picked != null) {
                        setState(() {
                          _priceDate = picked;
                          // Reset autoGenerated flag so robot reloads prices for new month
                          if (_selectedPreReg != null && _selectedPreReg!['priceOffer'] != null) {
                             _lastPricedStudentId = null; // Forces reload in next frame
                          }
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.indigo.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_today_rounded, size: 14, color: Colors.indigo.shade600),
                          const SizedBox(width: 6),
                          Text(
                            _priceDate != null
                                ? _monthNames[_priceDate!.month - 1] + ' ' + _priceDate!.year.toString()
                                : _monthNames[DateTime.now().month - 1] + ' ' + DateTime.now().year.toString(),
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.indigo.shade700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // 2. Pricing Inputs Card — baz fiyatlar (sadece gösterim)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: priceTypes.asMap().entries.map((entry) {
                    final type = entry.value;
                    final typeStr = type.toString();
                    final isLast = entry.key == priceTypes.length - 1;
                    return Column(
                      children: [
                        _buildRobotInputRow('$typeStr Baz Fiyatı', typeStr, (offer[typeStr] ?? 0.0).toDouble(), _getIconForPriceType(typeStr)),
                        if (!isLast) const Divider(height: 24),
                      ],
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 32),
              
              // 3. Discount Selection
              // 3. Discount Selection — Yatay Kaydırılabilir
              Text('Kullanılabilir İndirimler', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
              const SizedBox(height: 12),
              ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                  children: discounts.map((d) {
                    final dId = d['id'] as String? ?? '';
                    final dName = d['name'] as String? ?? '';
                    final dPerc = d['percentage'];
                    final isManual = dPerc == null || dPerc == 0;
                    final applied = (offer['appliedDiscounts'] as List<dynamic>? ?? []).contains(dId);
                    final manualPerc = offer['_manualPerc_$dId'];
                    final percLabel = isManual 
                        ? (manualPerc != null ? '%${manualPerc is double ? manualPerc.toStringAsFixed(0) : manualPerc}' : 'Manuel') 
                        : '%$dPerc';
                    
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _buildDiscountBubble(
                        dName, 
                        percLabel,
                        applied,
                        () async {
                          if (isManual) {
                            final percCtrl = TextEditingController();
                            final amountCtrl = TextEditingController();
                            
                            // Calculate base for percentage
                            double dBase = subtotal; // Default (Apply to all)
                            final dApplyToRaw = (d['applyTo'] as List<dynamic>?)?.map((e) => e.toString()).toList();
                            if (dApplyToRaw != null && dApplyToRaw.isNotEmpty) {
                              double matchedBase = 0;
                              bool anyMatched = false;
                              for (var type in priceTypes) {
                                final tN = type.toString().toLowerCase().replaceAll('ğ', 'g').replaceAll('ş', 's').replaceAll('ı', 'i').replaceAll('ü', 'u').replaceAll('ö', 'o').replaceAll('ç', 'c');
                                for (var a in dApplyToRaw) {
                                  final aN = a.toLowerCase().replaceAll('ğ', 'g').replaceAll('ş', 's').replaceAll('ı', 'i').replaceAll('ü', 'u').replaceAll('ö', 'o').replaceAll('ç', 'c');
                                  if (tN.contains(aN) || aN.contains(tN)) { matchedBase += (offer[type.toString()] ?? 0.0).toDouble(); anyMatched = true; break; }
                                }
                              }
                              if (anyMatched) dBase = matchedBase;
                            }

                            final resultPerc = await showDialog<double>(
                              context: context,
                              builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) {
                                return AlertDialog(
                                  title: Text('$dName İndirimi', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextField(
                                        controller: amountCtrl,
                                        autofocus: true,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: InputDecoration(
                                          labelText: 'İndirim Tutarı (₺)',
                                          prefixText: '₺',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        onChanged: (val) {
                                          final amt = double.tryParse(val.replaceAll(',', '.')) ?? 0;
                                          if (dBase > 0) {
                                            final p = (amt / dBase) * 100;
                                            percCtrl.text = p.toStringAsFixed(2);
                                          }
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      TextField(
                                        controller: percCtrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: InputDecoration(
                                          labelText: 'İndirim Oranı (%)',
                                          suffixText: '%',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        onChanged: (val) {
                                          final p = double.tryParse(val.replaceAll(',', '.')) ?? 0;
                                          final amt = (p * dBase) / 100;
                                          amountCtrl.text = amt.toStringAsFixed(2);
                                        },
                                      ),
                                      if (dBase > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 12),
                                          child: Text('Baz Tutar: ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(dBase)}', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
                                        ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İPTAL')),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, double.tryParse(percCtrl.text.replaceAll(',', '.')) ?? 0),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                                      child: const Text('UYGULA', style: TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                );
                              }),
                            );
                            if (resultPerc != null && resultPerc > 0) {
                              _toggleDiscountOptimistic(offer, dId, true, manualPercentage: resultPerc, discounts: discounts, priceTypes: priceTypes, applyTo: dApplyToRaw);
                            }
                          } else {
                            _toggleDiscountOptimistic(offer, dId, !applied, discounts: discounts, priceTypes: priceTypes);
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 32),
              Text('Ödeme Planı Seçiniz', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
              const SizedBox(height: 4),
              Text('Her fiyat türü için ayrı ödeme yöntemi seçebilirsiniz.', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
              const SizedBox(height: 12),
              ...priceTypes.map((type) {
                final typeStr = type.toString();
                final typeAmt = (offer[typeStr] ?? 0.0).toDouble();
                final chosenMethodId = _perTypePaymentMethod[typeStr];
                final chosenMethod = chosenMethodId != null
                    ? paymentMethods.firstWhere((m) => m['id'] == chosenMethodId, orElse: () => {})
                    : <String, dynamic>{};
                final chosenDisc = (chosenMethod['discount'] as num?)?.toDouble() ?? 0.0;
                // Calculate amount after global discounts for this specific type
                double amtAfterGlobalSelected = typeAmt;
                final appliedIdsSelected = offer['appliedDiscounts'] as List<dynamic>? ?? [];
                for (var d in discounts) {
                  if (appliedIdsSelected.contains(d['id'])) {
                    final perc = (offer['_manualPerc_${d['id']}'] as num?)?.toDouble() ?? (d['percentage'] as num?)?.toDouble() ?? 0.0;
                    final dApplyToRaw = d['applyTo'] as List<dynamic>?;
                    if (dApplyToRaw == null || dApplyToRaw.isEmpty) {
                      amtAfterGlobalSelected -= typeAmt * (perc / 100);
                    } else {
                      final typeLow = typeStr.toLowerCase().replaceAll('ğ', 'g').replaceAll('ı', 'i').replaceAll('ü', 'u').replaceAll('ö', 'o').replaceAll('ç', 'c');
                      bool applyToThisType = false;
                      for (var a in dApplyToRaw) {
                        final aLow = a.toString().toLowerCase().replaceAll('ğ', 'g').replaceAll('ş', 's').replaceAll('ı', 'i').replaceAll('ü', 'u').replaceAll('ö', 'o').replaceAll('ç', 'c');
                        if (typeLow.contains(aLow) || aLow.contains(typeLow)) { applyToThisType = true; break; }
                      }
                      if (applyToThisType) amtAfterGlobalSelected -= typeAmt * (perc / 100);
                    }
                  }
                }

                final discountedAmt = amtAfterGlobalSelected * (1 - chosenDisc / 100);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: chosenMethodId != null ? Colors.indigo.shade200 : const Color(0xFFE2E8F0)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(_getIconForPriceType(typeStr), size: 16, color: Colors.indigo),
                          const SizedBox(width: 8),
                          Text('$typeStr', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: const Color(0xFF1E293B))),
                          const Spacer(),
                          if (chosenMethodId != null && chosenDisc > 0)
                            Text(
                              NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(discountedAmt),
                              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.green.shade700),
                            )
                          else
                            Text(
                              NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(typeAmt),
                              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.indigo),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildTypePaymentChip(null, 'Seçilmedi', typeStr, chosenMethodId),
                              ...paymentMethods.map((m) {
                                final disc = (m['discount'] as num?)?.toDouble() ?? 0.0;
                                final label = disc > 0 ? '${m['name']} %${disc.toInt()}' : m['name'].toString();
                                return _buildTypePaymentChip(m['id'], label, typeStr, chosenMethodId);
                              }),
                            ],
                          ),
                        ),
                      ),
                      if (chosenMethodId != null && chosenDisc > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '→ %${chosenDisc.toInt()} indirimle: ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(discountedAmt)}',
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                );
              }),


              // Per-type summary box (after payment plan section)
              if (_perTypePaymentMethod.values.any((v) => v != null))
                Builder(builder: (_) {
                  double perTypeTotal = 0;
                  final rows = <Widget>[];
                  final appliedIds = offer['appliedDiscounts'] as List<dynamic>? ?? [];
                  
                  for (var type in priceTypes) {
                    final typeStr = type.toString();
                    final baseAmt = (offer[typeStr] ?? 0.0).toDouble();
                    
                    // A. Global discounts for this type
                    double amtAfterGlobal = baseAmt;
                    for (var d in discounts) {
                      if (appliedIds.contains(d['id'])) {
                        final perc = (offer['_manualPerc_${d['id']}'] as num?)?.toDouble() ?? (d['percentage'] as num?)?.toDouble() ?? 0.0;
                        final dApplyToRaw = d['applyTo'] as List<dynamic>?;
                        bool applies = false;
                        if (dApplyToRaw == null || dApplyToRaw.isEmpty) applies = true;
                        else {
                           final tL = typeStr.toLowerCase().replaceAll('ğ', 'g').replaceAll('ş', 's').replaceAll('ı', 'i').replaceAll('ü', 'u').replaceAll('ö', 'o').replaceAll('ç', 'c');
                           for (var a in dApplyToRaw) {
                             final aL = a.toString().toLowerCase().replaceAll('ğ', 'g').replaceAll('ş', 's').replaceAll('ı', 'i').replaceAll('ü', 'u').replaceAll('ö', 'o').replaceAll('ç', 'c');
                             if (tL.contains(aL) || aL.contains(tL)) { applies = true; break; }
                           }
                        }
                        if (applies) amtAfterGlobal -= baseAmt * (perc / 100);
                      }
                    }

                    // B. Payment method for this type
                    final methodId = _perTypePaymentMethod[typeStr];
                    double finalAmt = amtAfterGlobal;
                    String methodName = 'Seçilmedi';
                    if (methodId != null) {
                      final method = paymentMethods.firstWhere((m) => m['id'] == methodId, orElse: () => {});
                      if (method.isNotEmpty) {
                        final disc = (method['discount'] as num?)?.toDouble() ?? 0.0;
                        finalAmt = amtAfterGlobal * (1 - disc / 100);
                        methodName = method['name'];
                      }
                    }
                    perTypeTotal += finalAmt;
                    rows.add(Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(_getIconForPriceType(typeStr), size: 14, color: Colors.white70),
                          const SizedBox(width: 8),
                          Expanded(child: Text('$typeStr ($methodName)', style: GoogleFonts.inter(color: Colors.white70, fontSize: 13))),
                          Text(NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(finalAmt), style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                        ],
                      ),
                    ));
                  }
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Colors.indigo.shade700, Colors.indigo.shade900]),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [BoxShadow(color: Colors.indigo.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ÖDENECEK TOPLAM TUTARLAR', style: GoogleFonts.inter(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                        const SizedBox(height: 12),
                        ...rows,
                        const Divider(color: Colors.white24, height: 24),
                        Row(
                          children: [
                            Expanded(child: Text('GENEL TOPLAM', style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800))),
                            Text(NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(perTypeTotal), style: GoogleFonts.inter(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ],
                    ),
                  );
                }),

              // NET ÖDENECEK TUTAR — PDF butonunun üstünde
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.indigo.shade600, Colors.indigo.shade800]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.indigo.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
                ),
                child: Column(
                  children: [
                    Text('NET ÖDENECEK TUTAR', style: GoogleFonts.inter(color: Colors.white.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Text(
                      NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(anyPerTypeSelected ? perTypeGrandTotal : finalNetTotal),
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                    ),
                    if (totalDiscount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '- ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(totalDiscount)} indirim uygulandı',
                          style: GoogleFonts.inter(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    if (!anyPerTypeSelected && paymentMethodDiscountAmount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '- ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(paymentMethodDiscountAmount)} ödeme indirimi',
                          style: GoogleFonts.inter(color: Colors.greenAccent.shade100, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 48), // Daha fazla boşluk
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => _generateOfferPdf(),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('TEKLİFİ PDF OLARAK YAZDIR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade50,
                    foregroundColor: Colors.indigo,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
    );
  }

  Widget _buildPriceCircle(String label, double amount, Color color) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.1),
            border: Border.all(color: color.withOpacity(0.3), width: 2),
          ),
          alignment: Alignment.center,
          child: Text(
            NumberFormat.compact(locale: 'tr_TR').format(amount),
            style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: color, fontSize: 13),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
      ],
    );
  }

  Widget _buildActionFooter() {
    final reg = _selectedPreReg!;
    if (reg['isConverted'] == true) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: Colors.green.shade50,
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.green),
            const SizedBox(width: 12),
            Text('Öğrenci Kaydı Yapılmıştır', style: GoogleFonts.inter(color: Colors.green, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                // Navigate to student detail logic here
              },
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Dosyasına Git'),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _updateStatus('negative'),
              icon: const Icon(Icons.thumb_down_rounded),
              label: const Text('OLUMSUZ'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: () => _convertToActualRegistration(),
              icon: const Icon(Icons.thumb_up_rounded),
              label: const Text('KAYDA DÖNÜŞTÜR'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(String status) async {
    try {
      await FirebaseFirestore.instance.collection('preRegistrations').doc(_selectedPreRegId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _loadPreRegistrations();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Durum güncellendi: $status')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }


  Widget _buildEmptyDetailPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.contact_phone_rounded, size: 80, color: Colors.grey.shade200),
          const SizedBox(height: 16),
          Text('Görüntülemek için aday seçin', style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }


  Future<void> _generateOfferPdf() async {
    try {
      final settingsDoc = await FirebaseFirestore.instance
          .collection('preRegistrationSettings')
          .doc(_institutionId)
          .get();
      
      if (!settingsDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ayarlar bulunamadı.')));
        return;
      }

      final pdfBytes = await PdfService().generatePreRegistrationOfferPdf(
        _selectedPreReg!,
        settingsDoc.data()!,
      );

      await Printing.layoutPdf(onLayout: (format) async => pdfBytes);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _convertToActualRegistration() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kayda Dönüştür'),
        content: const Text('Bu aday öğrenci olarak sisteme eklenecek. Onaylıyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İPTAL')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('ONAYLA')),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      setState(() => _isLoading = true);
      
      // 1. Create student record
      final studentRef = await FirebaseFirestore.instance.collection('students').add({
        'institutionId': _institutionId,
        'fullName': _selectedPreReg!['fullName'],
        'phone': _selectedPreReg!['phone'],
        'schoolTypeId': _selectedPreReg!['schoolTypeId'],
        'classLevel': _selectedPreReg!['classLevel'],
        'termId': _selectedPreReg!['termId'],
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'registrationDate': DateFormat('dd.MM.yyyy').format(DateTime.now()),
        'entryType': 'Yeni',
        'fromPreRegistrationId': _selectedPreRegId,
      });

      // 2. Mark pre-registration as converted
      await FirebaseFirestore.instance.collection('preRegistrations').doc(_selectedPreRegId).update({
        'isConverted': true,
        'targetStudentId': studentRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓ Kayıt başarıyla tamamlandı.'), backgroundColor: Colors.green));
      _loadPreRegistrations();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  IconData _getIconForPriceType(String type) {
    final t = type.toLowerCase();
    if (t.contains('eğitim')) return Icons.school_rounded;
    if (t.contains('yemek')) return Icons.restaurant_rounded;
    if (t.contains('servis')) return Icons.directions_bus_rounded;
    if (t.contains('kitap') || t.contains('kırtasiye')) return Icons.menu_book_rounded;
    return Icons.payments_rounded;
  }

  static const List<String> _monthNames = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

  Future<void> _generateAutoOffer(Map<String, dynamic> settings, {DateTime? referenceDate}) async {
    final reg = _selectedPreReg!;
    
    // 1. Determine month: referenceDate param > _priceDate state > meetingDate field > now
    DateTime effectiveDate = referenceDate ?? _priceDate ?? DateTime.now();
    
    if (referenceDate == null && _priceDate == null) {
      final mDate = reg['meetingDate'];
      if (mDate != null) {
        if (mDate is Timestamp) {
          effectiveDate = mDate.toDate();
        } else if (mDate is String && mDate.isNotEmpty) {
          try {
            if (mDate.contains('.')) {
              final parts = mDate.split('.');
              if (parts.length >= 3) {
                effectiveDate = DateTime(
                  int.tryParse(parts[2]) ?? DateTime.now().year,
                  int.tryParse(parts[1]) ?? DateTime.now().month,
                  int.tryParse(parts[0]) ?? 1,
                );
              }
            } else {
              effectiveDate = DateTime.parse(mDate);
            }
          } catch (_) {}
        }
      }
    }
    
    final month = effectiveDate.month;
    final typeId = reg['schoolTypeId'];
    
    // 2. Normalize grade — extract only the number/raw part
    // classLevel can be: '5', '5. Sınıf', '5.Sınıf', '3 Yaş', '3YAŞ', 'MEZUN'
    final String rawClassLevel = reg['classLevel']?.toString() ?? '';
    
    // Extract just the numeric/core part for key matching
    String gradeCore = rawClassLevel.trim();
    // Remove common suffixes to get the raw value as saved in activeGrades
    gradeCore = gradeCore
        .replaceAll(RegExp(r'[. ]*S[ıi]n[ıi]f', caseSensitive: false), '')
        .replaceAll(RegExp(r'[. ]*YA[Şş]', caseSensitive: false), '')
        .replaceAll(RegExp(r'MEZUN', caseSensitive: false), 'MEZUN')
        .trim();
    // Remove trailing dot: '5.' -> '5'
    if (gradeCore.endsWith('.')) gradeCore = gradeCore.substring(0, gradeCore.length - 1).trim();
    
    final prices = settings['prices'] as Map<String, dynamic>? ?? {};
    final priceTypes = settings['priceTypes'] as List<dynamic>? ?? ['Eğitim', 'Yemek'];
    
    // 3. Find matching prices
    Map<String, dynamic>? foundPrices;
    
    // Build variations including original
    final Set<String> triedVariations = {};
    final List<String> variations = [
      gradeCore,                          // '5' (most common raw format)
      rawClassLevel.trim(),               // exact original: '5. Sınıf'
      rawClassLevel.trim().toUpperCase(), // uppercase: '5. SINIF'
      '${gradeCore} Yaş',                // '3 Yaş' for kindergarten
      '${gradeCore}Yaş',                 // '3Yaş'
      '${gradeCore} YAŞ',               // '3 YAŞ'
    ];

    debugPrint('Price Robot: month=$month, typeId=$typeId, rawClassLevel=$rawClassLevel, gradeCore=$gradeCore');
    debugPrint('Price Robot: available keys=${prices.keys.toList()}');

    for (var v in variations) {
      if (triedVariations.contains(v)) continue;
      triedVariations.add(v);
      final key = '${month}_${typeId}_$v';
      debugPrint('Price Robot: trying key=$key');
      if (prices.containsKey(key)) {
        foundPrices = prices[key] as Map<String, dynamic>;
        debugPrint('Price Robot: ✅ FOUND key=$key -> $foundPrices');
        break;
      }
    }
    
    // Fallback: scan all keys for this month + schoolType, pick first matching grade
    if (foundPrices == null) {
      final prefix = '${month}_${typeId}_';
      for (final k in prices.keys) {
        if (k.startsWith(prefix)) {
          final gradePart = k.substring(prefix.length);
          final gradeCoreClean = gradeCore.replaceAll(' ', '').toLowerCase();
          final gradePartClean = gradePart.replaceAll(' ', '').replaceAll('.', '').toLowerCase()
              .replaceAll('sinif', '').replaceAll('sınıf', '').replaceAll('yaş', '').replaceAll('yas', '').trim();
          debugPrint('Price Robot: fallback comparing "$gradeCoreClean" vs "$gradePartClean" (key=$k)');
          if (gradePartClean == gradeCoreClean || gradePartClean.startsWith(gradeCoreClean)) {
            foundPrices = prices[k] as Map<String, dynamic>;
            debugPrint('Price Robot: ✅ FALLBACK found key=$k -> $foundPrices');
            break;
          }
        }
      }
    }
    
    if (foundPrices == null) {
      debugPrint('Price Robot: ❌ No prices found. Checked month=$month, typeId=$typeId, gradeCore=$gradeCore');
    }
    
    final defaultPrices = foundPrices ?? {};
    
    final Map<String, dynamic> newOffer = {
      'appliedDiscounts': [],
      'discount': 0.0,
      'total': 0.0,
      'autoGenerated': true,
    };
    
    double initialTotal = 0.0;
    for (var type in priceTypes) {
      final value = (defaultPrices[type] ?? 0.0).toDouble();
      newOffer[type] = value;
      initialTotal += value;
    }
    newOffer['total'] = initialTotal;

    // 4. Update local state immediately (Optimistic UI)
    if (mounted) {
      setState(() {
        _lastPricedStudentId = _selectedPreRegId; // Set this here to clear loader
        _selectedPreReg = Map<String, dynamic>.from(_selectedPreReg!);
        _selectedPreReg!['priceOffer'] = newOffer;
      });
    }

    // 5. Save to Firestore in background
    FirebaseFirestore.instance.collection('preRegistrations').doc(_selectedPreRegId).update({
      'priceOffer': newOffer,
      'updatedAt': FieldValue.serverTimestamp(),
    }).then((_) {
      if (mounted) _loadPreRegistrations(); // Refresh list in background
    }).catchError((e) {
      debugPrint('generateAutoOffer background save error: $e');
    });
  }


  Widget _buildTypePaymentChip(String? methodId, String label, String priceType, String? currentMethodId) {
    final isSelected = methodId == currentMethodId;
    return GestureDetector(
      onTap: () {
        final reg = _selectedPreReg!;
        Map<String, dynamic> offer = Map<String, dynamic>.from(reg['priceOffer'] ?? {});
        
        setState(() {
          if (isSelected) {
            _perTypePaymentMethod.remove(priceType);
          } else {
            _perTypePaymentMethod[priceType] = methodId;
          }
          // Save to offer map for persistence and PDF
          offer['perTypePaymentMethods'] = _perTypePaymentMethod;
          _selectedPreReg = Map<String, dynamic>.from(reg);
          _selectedPreReg!['priceOffer'] = offer;
        });

        // Background persistence
        FirebaseFirestore.instance.collection('preRegistrations').doc(_selectedPreRegId).update({
          'priceOffer': offer,
          'updatedAt': FieldValue.serverTimestamp(),
        }).catchError((e) => debugPrint('Payment method save error: $e'));
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.indigo : const Color(0xFFE2E8F0)),
          boxShadow: isSelected ? [BoxShadow(color: Colors.indigo.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 2))] : [],
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildRobotInputRow(String label, String field, double value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 20, color: Colors.indigo),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)))),
            Text(
              NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(value),
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.indigo),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscountBubble(String name, String percentage, bool isSelected, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.indigo.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? Colors.indigo : const Color(0xFFE2E8F0), width: isSelected ? 1.5 : 1),
            boxShadow: isSelected ? [BoxShadow(color: Colors.indigo.withOpacity(0.1), blurRadius: 4)] : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: GoogleFonts.inter(fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? Colors.indigo : const Color(0xFF475569))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: isSelected ? Colors.indigo.withOpacity(0.2) : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                child: Text(percentage, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: isSelected ? Colors.indigo : const Color(0xFF64748B))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Optimistic discount toggle — updates UI instantly, writes to Firestore in background
  void _toggleDiscountOptimistic(
    Map<String, dynamic> currentOffer,
    String discountId,
    bool select, {
    double? manualPercentage,
    required List<dynamic> discounts,
    required List<dynamic> priceTypes,
    List<String>? applyTo,
  }) {
    final offer = Map<String, dynamic>.from(currentOffer);
    final List<dynamic> applied = List<dynamic>.from(offer['appliedDiscounts'] ?? []);
    
    if (select) {
      if (!applied.contains(discountId)) applied.add(discountId);
      if (manualPercentage != null) {
        offer['_manualPerc_$discountId'] = manualPercentage;
      }
    } else {
      applied.remove(discountId);
      offer.remove('_manualPerc_$discountId');
    }
    offer['appliedDiscounts'] = applied;

    // Recalculate totals locally (instant)
    double subtotal = 0.0;
    for (var type in priceTypes) {
      subtotal += (offer[type] ?? 0.0).toDouble();
    }
    double totalDiscount = 0.0;
    for (var d in discounts) {
      if (applied.contains(d['id'])) {
        double perc;
        if (d['id'] == discountId && manualPercentage != null) {
          perc = manualPercentage;
        } else {
          perc = (offer['_manualPerc_${d['id']}'] as num?)?.toDouble() ?? (d['percentage'] as num?)?.toDouble() ?? 0.0;
        }
        final dApplyToRaw = applyTo ?? (d['applyTo'] as List<dynamic>?)?.map((e) => e.toString()).toList();
        
        double base = 0.0;
        if (dApplyToRaw == null || dApplyToRaw.isEmpty) {
          // DEFAULT: Apply to all (Global)
          base = subtotal;
        } else {
          // Try to match applyTo values with priceTypes
          bool anyMatched = false;
          for (var type in priceTypes) {
            final typeNorm = type.toString().toLowerCase()
                .replaceAll('ğ', 'g').replaceAll('ş', 's').replaceAll('ı', 'i')
                .replaceAll('ü', 'u').replaceAll('ö', 'o').replaceAll('ç', 'c');
            for (var a in dApplyToRaw) {
              final aNorm = a.toLowerCase()
                  .replaceAll('ğ', 'g').replaceAll('ş', 's').replaceAll('ı', 'i')
                  .replaceAll('ü', 'u').replaceAll('ö', 'o').replaceAll('ç', 'c');
              if (aNorm == typeNorm || typeNorm.startsWith(aNorm) || aNorm.startsWith(typeNorm)) {
                base += (offer[type.toString()] ?? 0.0).toDouble();
                anyMatched = true;
                break;
              }
            }
          }
          // Fallback if no matching type found for applyTo
          if (!anyMatched) base = subtotal;
        }
        totalDiscount += base * (perc / 100);
      }
    }
    offer['discount'] = totalDiscount;
    offer['total'] = (subtotal - totalDiscount).roundToDouble();
    offer['autoGenerated'] = true;

    // Update local state instantly (no lag)
    setState(() {
      _selectedPreReg = Map<String, dynamic>.from(_selectedPreReg!);
      _selectedPreReg!['priceOffer'] = offer;
    });

    // Write to Firestore in background (non-blocking)
    FirebaseFirestore.instance.collection('preRegistrations').doc(_selectedPreRegId).update({
      'priceOffer': offer,
      'updatedAt': FieldValue.serverTimestamp(),
    }).catchError((e) => debugPrint('Discount save error: $e'));
  }




  void _handleEdit(Map<String, dynamic> reg) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddPreRegistrationScreen(
          institutionId: _institutionId,
          selectedTermId: _selectedTermFilter,
          schoolTypes: _schoolTypes,
          preRegistration: reg,
          preRegistrationId: reg['id'],
        ),
      ),
    );
    if (result == true) _loadPreRegistrations();
  }

  void _handleDelete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Görüşmeyi Sil'),
        content: const Text('Bu görüşme kaydı tamamen silinecek. Emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İPTAL')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('SİL', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance.collection('preRegistrations').doc(id).delete();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓ Görüşme silindi.')));
      _loadPreRegistrations();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Silme hatası: $e')));
    }
  }

  String _getSchoolTypeName(String? id) {
    if (id == null) return '-';
    final type = _schoolTypes.firstWhere((t) => t['id'] == id, orElse: () => {});
    return type['schoolTypeName'] ?? type['typeName'] ?? '-';
  }

  String _formatLevelLabel(String? level) {
    if (level == null) return '-';
    if (level.contains('YAŞ')) return level;
    if (level == 'MEZUN') return level;
    if (RegExp(r'^\d+$').hasMatch(level)) return '$level. Sınıf';
    return level;
  }
}
