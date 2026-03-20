import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../services/user_permission_service.dart';
import 'add_pre_registration_screen.dart';
import 'pre_registration_settings_screen.dart';
import '../../../services/pdf_service.dart';
import 'package:printing/printing.dart';

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

  // Filters
  String _statusFilter = 'pending';
  String? _selectedTermFilter;
  String? _schoolTypeFilter;
  String? _gradeLevelFilter;
  List<Map<String, dynamic>> _terms = [];
  List<Map<String, dynamic>> _schoolTypes = [];

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

      print('🏢 Institution ID: $_institutionId');

      try {
        final termsQuery = await FirebaseFirestore.instance
            .collection('terms')
            .where('institutionId', isEqualTo: _institutionId)
            .get();
        _terms = termsQuery.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
        print('✅ Terms loaded: ${_terms.length}');
      } catch (e) {
        print('❌ Error loading terms: $e');
      }
      
      try {
        final schoolTypesQuery = await FirebaseFirestore.instance
            .collection('schoolTypes')
            .where('institutionId', isEqualTo: _institutionId)
            .get();
        _schoolTypes = schoolTypesQuery.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
        print('✅ School types loaded: ${_schoolTypes.length}');
      } catch (e) {
        print('❌ Error loading schoolTypes: $e');
      }

      if (_terms.isNotEmpty) {
        _selectedTermFilter = _terms.firstWhere((t) => t['isActive'] == true, orElse: () => _terms.first)['id'];
      }

      await _loadPreRegistrations();
    } catch (e) {
      print('Error loading initial data: $e');
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
    });
  }

  void _filterPreRegistrations() {
    final query = _searchController.text.toLowerCase();
    setState(() {
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
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isWideScreen = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ön Kayıt ve Görüşme Yönetimi'),
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
            icon: const Icon(Icons.add_task),
            onPressed: () async {
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
            },
            tooltip: 'Yeni Ön Kayıt / Görüşme',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: isWideScreen
            ? Row(
                children: [
                  SizedBox(width: 380, child: _buildPreRegList()),
                  const VerticalDivider(width: 20),
          Expanded(
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
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.contact_phone_outlined, size: 80, color: Colors.indigo.shade300),
            ),
            const SizedBox(height: 24),
            const Text(
              'Henüz Ön Kayıt Bulunmuyor',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo),
            ),
            const SizedBox(height: 12),
            Text(
              'Okula gelen aday velilerle yaptığınız görüşmeleri\nburadan kaydederek takip edebilirsiniz.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _handleAddNew(),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('İLK ÖN KAYDI OLUŞTUR', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.indigo,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                onChanged: (_) => _filterPreRegistrations(),
                decoration: InputDecoration(
                  hintText: 'İsim veya telefon ara',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _schoolTypeFilter,
                          hint: const Text('Tüm Türler', style: TextStyle(fontSize: 13)),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Tüm Türler', style: TextStyle(fontSize: 13))),
                            ..._schoolTypes.map((t) => DropdownMenuItem(value: t['id'], child: Text(t['schoolTypeName'] ?? t['typeName'] ?? '', style: const TextStyle(fontSize: 13)))),
                          ],
                          onChanged: (v) {
                            setState(() => _schoolTypeFilter = v);
                            _filterPreRegistrations();
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _gradeLevelFilter,
                          hint: const Text('Tüm Sınıflar', style: TextStyle(fontSize: 13)),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Tüm Sınıflar', style: TextStyle(fontSize: 13))),
                            ...['3 YAŞ', '4 YAŞ', '5 YAŞ', '1. SINIF', '2. SINIF', '3. SINIF', '4. SINIF', '5. SINIF', '6. SINIF', '7. SINIF', '8. SINIF', '9. SINIF', '10. SINIF', '11. SINIF', '12. SINIF', 'MEZUN']
                                .where((l) => _preRegistrations.any((r) => r['classLevel'] == l))
                                .map((l) => DropdownMenuItem(value: l, child: Text(_formatLevelLabel(l), style: const TextStyle(fontSize: 13)))),
                          ],
                          onChanged: (v) {
                            setState(() => _gradeLevelFilter = v);
                            _filterPreRegistrations();
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildStatusChip('pending', 'Bekleyen', Icons.hourglass_empty),
                  const SizedBox(width: 4),
                  _buildStatusChip('converted', 'Kaydolmuş', Icons.check_circle),
                  const SizedBox(width: 4),
                  _buildStatusChip('negative', 'Olumsuz', Icons.thumb_down_alt_outlined),
                  const SizedBox(width: 4),
                  _buildStatusChip('all', 'Hepsi', Icons.list),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _filteredPreRegistrations.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  itemCount: _filteredPreRegistrations.length,
                  itemBuilder: (context, index) {
                    final reg = _filteredPreRegistrations[index];
                    final isSelected = reg['id'] == _selectedPreRegId;
                    return Card(
                      color: isSelected ? Colors.indigo.shade50 : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: isSelected ? Colors.indigo : Colors.grey.shade200),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: reg['isConverted'] == true ? Colors.green.shade100 : Colors.orange.shade100,
                          child: Icon(
                            reg['isConverted'] == true ? Icons.person : Icons.person_outline,
                            color: reg['isConverted'] == true ? Colors.green : Colors.orange,
                          ),
                        ),
                        title: Text(reg['fullName'] ?? 'İsimsiz', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${_getSchoolTypeName(reg['schoolTypeId'])} - ${_formatLevelLabel(reg['classLevel'])}', style: TextStyle(color: Colors.indigo.shade700, fontSize: 13, fontWeight: FontWeight.w500)),
                        trailing: PopupMenuButton<String>(
                          onSelected: (val) {
                            if (val == 'edit') {
                              _handleEdit(reg);
                            } else if (val == 'delete') {
                              _handleDelete(reg['id']);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit, color: Colors.indigo), title: Text('Düzenle'), dense: true)),
                            const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, color: Colors.red), title: Text('Sil'), dense: true)),
                          ],
                        ),
                        onTap: () {
                          setState(() {
                            _selectedPreReg = reg;
                            _selectedPreRegId = reg['id'];
                            _isAdding = false;
                          });
                          if (MediaQuery.of(context).size.width <= 900) {
                            _showMobileDetail(reg);
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
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


  Widget _buildStatusChip(String value, String label, IconData icon) {
    final isSelected = _statusFilter == value;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _statusFilter = value);
          _filterPreRegistrations();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.white24,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isSelected ? Colors.indigo : Colors.white),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: isSelected ? Colors.indigo : Colors.white, fontSize: 11, fontWeight: isSelected ? FontWeight.bold : null)),
            ],
          ),
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
            color: Colors.white,
            child: const TabBar(
              labelColor: Colors.indigo,
              indicatorColor: Colors.indigo,
              tabs: [
                Tab(icon: Icon(Icons.info), text: 'Görüşme Bilgileri'),
                Tab(icon: Icon(Icons.calculate), text: 'Fiyat Robotu / Teklif'),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Aday Bilgileri', Icons.person),
          _buildDetailItem('Ad Soyad', reg['fullName']),
          _buildDetailItem('Cinsiyet', reg['gender'] ?? '-'),
          _buildDetailItem('Sınıf Seviyesi', _formatLevelLabel(reg['classLevel'])),
          _buildDetailItem('Okul Türü', _getSchoolTypeName(reg['schoolTypeId'])),
          _buildDetailItem('Geldiği / Okuduğu Okul', reg['previousSchool'] ?? '-'),
          _buildDetailItem('Telefon', reg['phone']),
          _buildDetailItem('E-posta', reg['email'] ?? '-'),
          
          const Divider(height: 32),
          _buildSectionHeader('Veli Bilgileri', Icons.family_restroom),
          _buildDetailItem('1. Veli', '${reg['guardian1Name'] ?? '-'} (${reg['guardian1Kinship'] ?? '-'})'),
          _buildDetailItem('2. Veli', reg['guardian2Name'] != null && reg['guardian2Name'].toString().isNotEmpty 
              ? '${reg['guardian2Name']} (${reg['guardian2Kinship'] ?? '-'})' 
              : '-'),
          
          const Divider(height: 32),
          _buildSectionHeader('Adres Bilgileri', Icons.location_on),
          _buildDetailItem('Şehir / İlçe', '${addr['city'] ?? '-'} / ${addr['district'] ?? '-'}'),
          _buildDetailItem('Mahalle', addr['neighborhood'] ?? '-'),

          const Divider(height: 32),
          _buildSectionHeader('Görüşme Detayları', Icons.event_note),
          _buildDetailItem('Görüşme Tarihi', dateStr),
          _buildDetailItem('Görüşen Görevli', reg['responsibleName'] ?? '-'),
          const SizedBox(height: 10),
          const Text('Görüşme Notları:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Text(reg['meetingNotes'] ?? 'Not girilmemiş...', style: const TextStyle(fontSize: 14)),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPriceRobotTab() {
    final offer = _selectedPreReg!['priceOffer'] as Map<String, dynamic>? ?? {};
    
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('preRegistrationSettings').doc(_institutionId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final settings = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final discounts = settings['discounts'] as List<dynamic>? ?? [];
        final paymentMethods = settings['paymentMethods'] as List<dynamic>? ?? [];
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Fiyat Teklifi (Robot)', Icons.smart_toy_outlined),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _generateAutoOffer(settings),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Ayarlardan Fiyatları Getir'),
                ),
              ),
              const SizedBox(height: 16),
              _buildRobotPriceInput('Eğitim Bedeli', 'educationFee', (offer['educationFee'] ?? 0.0).toDouble()),
              _buildRobotPriceInput('Yemek Bedeli', 'foodFee', (offer['foodFee'] ?? 0.0).toDouble()),
              _buildRobotPriceInput('Kırtasiye Bedeli', 'stationeryFee', (offer['stationeryFee'] ?? 0.0).toDouble()),
              _buildRobotPriceInput('Servis Bedeli', 'serviceFee', (offer['serviceFee'] ?? 0.0).toDouble()),
              _buildRobotPriceInput('Diğer Giderler', 'otherFee', (offer['otherFee'] ?? 0.0).toDouble()),
              const Divider(height: 32, thickness: 2),
              const Text('Uygulanacak İndirimler:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 12),
              ...discounts.map((d) {
                final isEnabled = d['enabled'] == true;
                if (!isEnabled) return const SizedBox();
                final bool isSelected = (offer['appliedDiscounts'] as List<dynamic>? ?? []).contains(d['id']);
                return CheckboxListTile(
                  title: Text(d['name']),
                  subtitle: Text('% ${d['percentage']}'),
                  value: isSelected,
                  onChanged: (val) => _toggleDiscount(d['id'], val ?? false),
                  dense: true,
                );
              }).toList(),
              const Divider(height: 32),
              _buildPriceItem('İndirim / Burs Toplamı', (offer['discount'] ?? 0.0).toDouble(), isDiscount: true),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.indigo.shade200)),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOPLAM TUTAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)),
                        Text(
                          NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(offer['total'] ?? 0.0),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    ...paymentMethods.map((m) {
                      final disc = (m['discount'] as num?)?.toDouble() ?? 0.0;
                      final total = (offer['total'] as num?)?.toDouble() ?? 0.0;
                      final discountedTotal = total * (1 - disc / 100);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(m['name'], style: const TextStyle(fontSize: 13, color: Colors.black54)),
                            Text(
                              NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(discountedTotal),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _generateOfferPdf(),
                  icon: const Icon(Icons.print),
                  label: const Text('Teklifi Yazdır (PDF)'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                ),
              ),
            ],
          ),
        );
      }
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
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            const Text('Bu aday öğrenci olarak kaydedilmiştir.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(
              onPressed: () {
                // Navigate to student detail
              },
              child: const Text('Öğrenciye Git'),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade200))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _convertToActualRegistration(),
                  icon: const Icon(Icons.how_to_reg),
                  label: const Text('Gerçek Kayda Dönüştür'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _updateStatus('negative'),
                  icon: const Icon(Icons.thumb_down_alt_outlined),
                  label: const Text('Olumsuz'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(String status) async {
    try {
      await FirebaseFirestore.instance.collection('pre_registrations').doc(_selectedPreRegId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _loadPreRegistrations();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Durum güncellendi: $status')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.indigo, size: 20),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text('$label:', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(width: 8),
          Text(value ?? '-', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildPriceItem(String label, dynamic value, {bool isDiscount = false}) {
    final amount = (value as num).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 14)),
          Text(
            (isDiscount ? '- ' : '') + NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(amount),
            style: TextStyle(
              fontWeight: FontWeight.bold, 
              color: isDiscount ? Colors.red : Colors.black87,
              fontSize: 14
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDetailPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.contact_phone_outlined, size: 100, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text('Görüntülemek için listeden bir aday seçin', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  void _showMobileDetail(Map<String, dynamic> reg) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => Scaffold(
      appBar: AppBar(title: Text(reg['fullName'] ?? 'Aday Detayı')),
      body: _buildPreRegDetail(),
    )));
  }

  // --- Modal Dialogs ---



  Future<void> _generateOfferPdf() async {
    try {
      final settingsDoc = await FirebaseFirestore.instance
          .collection('preRegistrationSettings')
          .doc(_institutionId)
          .get();
      
      if (!settingsDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Ayarlar bulunamadı.')));
        return;
      }

      final pdfBytes = await PdfService().generatePreRegistrationOfferPdf(
        _selectedPreReg!,
        settingsDoc.data()!,
      );

      await Printing.layoutPdf(onLayout: (format) async => pdfBytes);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Hata: $e')));
    }
  }

  Future<void> _convertToActualRegistration() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gerçek Kayıt Yapılsın mı?'),
        content: const Text('Bu aday öğrenci listesine aktarılacak. İşleme devam edilsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Evet, Aktar')),
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
      await FirebaseFirestore.instance.collection('pre_registrations').doc(_selectedPreRegId).update({
        'isConverted': true,
        'targetStudentId': studentRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 3. Create payment plan if offer exists
      final offer = _selectedPreReg!['priceOffer'] as Map<String, dynamic>?;
      if (offer != null && (offer['total'] ?? 0.0) > 0) {
        final total = (offer['total'] as num).toDouble();
        
        // Create 10 installments by default (simple logic for now)
        final List<Map<String, dynamic>> installments = [];
        final installmentAmount = (total / 10).roundToDouble();
        final now = DateTime.now();
        
        for (int i = 0; i < 10; i++) {
          final dueDate = DateTime(now.year, now.month + i, 15);
          installments.add({
            'amount': i == 9 ? (total - (installmentAmount * 9)) : installmentAmount,
            'dueDate': DateFormat('dd.MM.yyyy').format(dueDate),
            'status': 'pending',
            'type': 'installment',
          });
        }

        await FirebaseFirestore.instance.collection('payment_plans').add({
          'institutionId': _institutionId,
          'studentId': studentRef.id,
          'studentName': _selectedPreReg!['fullName'],
          'name': 'Eğitim Ödemesi (Ön Kayıttan)',
          'totalAmount': total,
          'paidAmount': 0.0,
          'installments': installments,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'status': 'active',
          'termId': _selectedPreReg!['termId'],
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓ Öğrenci ve Ödeme Planı başarıyla oluşturuldu.'), backgroundColor: Colors.green));
      _loadPreRegistrations();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generateAutoOffer(Map<String, dynamic> settings) async {
    final reg = _selectedPreReg!;
    final month = DateTime.now().month;
    final typeId = reg['schoolTypeId'];
    final grade = reg['classLevel'];
    final key = '${month}_${typeId}_$grade';
    
    final prices = settings['prices'] as Map<String, dynamic>? ?? {};
    final defaultPrice = prices[key] ?? {'education': 0.0, 'food': 0.0};
    
    final newOffer = {
      'educationFee': (defaultPrice['education'] ?? 0.0).toDouble(),
      'foodFee': (defaultPrice['food'] ?? 0.0).toDouble(),
      'stationeryFee': (reg['priceOffer']?['stationeryFee'] ?? 0.0).toDouble(),
      'serviceFee': (reg['priceOffer']?['serviceFee'] ?? 0.0).toDouble(),
      'otherFee': (reg['priceOffer']?['otherFee'] ?? 0.0).toDouble(),
      'appliedDiscounts': [],
      'discount': 0.0,
      'total': (defaultPrice['education'] ?? 0.0).toDouble() + (defaultPrice['food'] ?? 0.0).toDouble(),
    };
    
    await _recalculateOffer(newOffer);
  }

  Widget _buildRobotPriceInput(String label, String field, double currentValue) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          SizedBox(
            width: 120,
            height: 40,
            child: TextFormField(
              initialValue: currentValue == 0 ? '' : currentValue.toString(),
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 14),
              onFieldSubmitted: (val) => _updatePriceField(field, double.tryParse(val) ?? 0.0),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updatePriceField(String field, double value) async {
    final offer = Map<String, dynamic>.from(_selectedPreReg!['priceOffer'] ?? {});
    offer[field] = value;
    await _recalculateOffer(offer);
  }

  Future<void> _toggleDiscount(String discountId, bool selected) async {
    final offer = Map<String, dynamic>.from(_selectedPreReg!['priceOffer'] ?? {});
    final List<dynamic> applied = List<dynamic>.from(offer['appliedDiscounts'] ?? []);
    if (selected) {
      if (!applied.contains(discountId)) applied.add(discountId);
    } else {
      applied.remove(discountId);
    }
    offer['appliedDiscounts'] = applied;
    await _recalculateOffer(offer);
  }

  Future<void> _recalculateOffer(Map<String, dynamic> offer) async {
    final settingsDoc = await FirebaseFirestore.instance.collection('preRegistrationSettings').doc(_institutionId).get();
    final settings = settingsDoc.data() ?? {};
    final discounts = settings['discounts'] as List<dynamic>? ?? [];

    final education = (offer['educationFee'] ?? 0.0).toDouble();
    final food = (offer['foodFee'] ?? 0.0).toDouble();
    final stationery = (offer['stationeryFee'] ?? 0.0).toDouble();
    final service = (offer['serviceFee'] ?? 0.0).toDouble();
    final other = (offer['otherFee'] ?? 0.0).toDouble();
    
    double totalDiscount = 0.0;
    final appliedIds = offer['appliedDiscounts'] as List<dynamic>? ?? [];
    
    for (var d in discounts) {
      if (appliedIds.contains(d['id'])) {
        final perc = (d['percentage'] as num?)?.toDouble() ?? 0.0;
        final applyTo = d['applyTo'] as List<dynamic>? ?? ['education'];
        double discountedBase = 0.0;
        if (applyTo.contains('education')) discountedBase += education;
        if (applyTo.contains('food')) discountedBase += food;
        totalDiscount += discountedBase * (perc / 100);
      }
    }

    final subtotal = education + food + stationery + service + other;
    offer['discount'] = totalDiscount;
    offer['total'] = (subtotal - totalDiscount).roundToDouble();

    try {
      await FirebaseFirestore.instance.collection('preRegistrations').doc(_selectedPreRegId).update({
        'priceOffer': offer,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      setState(() {
        _selectedPreReg!['priceOffer'] = offer;
      });
    } catch (e) {
      print('Calculation update error: $e');
    }
  }
}
