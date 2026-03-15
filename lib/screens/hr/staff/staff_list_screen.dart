import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'staff_detail_screen.dart';
import 'staff_form_screen.dart';

class StaffListScreen extends StatefulWidget {
  static const routeName = '/hr/staff';
  final String? fixedSchoolTypeId;
  final String? fixedSchoolTypeName;
  
  const StaffListScreen({
    super.key,
    this.fixedSchoolTypeId,
    this.fixedSchoolTypeName,
  });

  @override
  State<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends State<StaffListScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _search = TextEditingController();
  String _statusFilter = 'active';
  String? _departmentFilter;
  String? _titleFilter;
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _filteredStaff = [];
  Map<String, dynamic>? _selectedStaff;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadStaff();
    _search.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final email = user.email ?? '';
      if (!email.contains('@')) {
        setState(() {
          _isLoading = false;
        });
        return;
      }
      final domain = email.split('@')[1];
      if (!domain.contains('.')) {
        setState(() {
          _isLoading = false;
        });
        return;
      }
      final institutionId = domain.split('.')[0].toUpperCase();

      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: institutionId)
          .where('type', isEqualTo: 'staff')
          .get();

      final items = query.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      setState(() {
        _staff = items;
        _applyFilters();
        if (_filteredStaff.isNotEmpty) {
          _selectedStaff = _filteredStaff.first;
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    final query = _search.text.toLowerCase();
    setState(() {
      _filteredStaff = _staff.where((s) {
        final fullName = (s['fullName'] ?? '').toString().toLowerCase();
        final username = (s['username'] ?? '').toString().toLowerCase();
        final isActive = s['isActive'] ?? true;
        final department = (s['department'] ?? '').toString();
        final title = (s['title'] ?? '').toString();

        final matchesSearch =
            query.isEmpty ||
            fullName.contains(query) ||
            username.contains(query);

        final matchesStatus =
            _statusFilter == 'all' ||
            (_statusFilter == 'active' && isActive) ||
            (_statusFilter == 'inactive' && !isActive);

        final matchesDepartment =
            _departmentFilter == null ||
            _departmentFilter == 'Tümü' ||
            department == _departmentFilter;

        final matchesTitle =
            _titleFilter == null ||
            _titleFilter == 'Tümü' ||
            _formatTitleForFilter(title) == _titleFilter;

        // Okul türü filtresi (eğer sabitlendiyse)
        // workLocations array'inde schoolTypeName'i ara
        bool matchesSchoolType = widget.fixedSchoolTypeId == null;
        if (!matchesSchoolType && widget.fixedSchoolTypeName != null) {
          // workLocations array'inde schoolTypeName var mı kontrol et
          if (s['workLocations'] != null && s['workLocations'] is List) {
            final locations = List<String>.from(s['workLocations']);
            matchesSchoolType = locations.contains(widget.fixedSchoolTypeName);
          }
          // Eski format için workLocation string kontrolü
          else if (s['workLocation'] != null) {
            matchesSchoolType = s['workLocation'].toString() == widget.fixedSchoolTypeName;
          }
          // workLocations boşsa, personeli göster (henüz atanmamış olabilir)
          else {
            matchesSchoolType = true;
          }
        }

        return matchesSearch &&
            matchesStatus &&
            matchesDepartment &&
            matchesTitle &&
            matchesSchoolType;
      }).toList();
      
      // Branşa göre sırala, sonra isme göre
      _filteredStaff.sort((a, b) {
        final branchA = (a['branch'] ?? '').toString();
        final branchB = (b['branch'] ?? '').toString();
        
        // Branş karşılaştırması (boş olanlar sona)
        if (branchA.isEmpty && branchB.isNotEmpty) return 1;
        if (branchA.isNotEmpty && branchB.isEmpty) return -1;
        
        final branchCompare = branchA.compareTo(branchB);
        if (branchCompare != 0) return branchCompare;
        
        // Aynı branşsa isme göre sırala
        final nameA = (a['fullName'] ?? '').toString();
        final nameB = (b['fullName'] ?? '').toString();
        return nameA.compareTo(nameB);
      });
    });
  }

  List<String> _getUniqueValues(String key) {
    final values = _staff
        .map((e) => (e[key] ?? '').toString())
        .where((e) => e.isNotEmpty)
        .map((e) => key == 'title' ? _formatTitleForFilter(e) : e) // Ünvan için formatla
        .toSet()
        .toList();
    values.sort();
    return ['Tümü', ...values];
  }

  String _formatTitleForFilter(String title) {
    switch (title.toLowerCase()) {
      case 'ogretmen':
        return 'Öğretmen';
      case 'mudur':
        return 'Müdür';
      case 'mudur_yardimcisi':
        return 'Müdür Yardımcısı';
      case 'personel':
        return 'Personel';
      case 'hr':
        return 'İnsan Kaynakları';
      case 'muhasebe':
        return 'Muhasebe';
      case 'satin_alma':
        return 'Satın Alma';
      case 'depo':
        return 'Depo Sorumlusu';
      case 'destek_hizmetleri':
        return 'Destek Hizmetleri';
      case 'uzman':
        return 'Uzman';
      default:
        return title;
    }
  }

  int _getCount(String status) {
    if (status == 'all') return _staff.length;
    final isActive = status == 'active';
    return _staff.where((s) => (s['isActive'] ?? true) == isActive).length;
  }

  String _formatRole(String? role) {
    if (role == null) return 'Ünvan Girilmedi';
    switch (role.toUpperCase()) {
      case 'OGRETMEN':
      case 'TEACHER':
        return 'ÖĞRETMEN';
      case 'MUDUR':
      case 'MANAGER':
        return 'MÜDÜR';
      case 'MUDUR_YARDIMCISI':
        return 'MÜDÜR YARDIMCISI';
      case 'PERSONEL':
      case 'STAFF':
        return 'PERSONEL';
      case 'OGRENCI':
      case 'STUDENT':
        return 'ÖĞRENCİ';
      case 'VELI':
      case 'PARENT':
        return 'VELİ';
      default:
        return role.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;

    final left = Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.indigo,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.groups, color: Colors.white),
                  const SizedBox(width: 8),
                  const Text(
                    'Personel',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_filteredStaff.length}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Personel ara',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _search.clear();
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _statusChip('active', 'Aktif', Icons.check_circle),
                  const SizedBox(width: 6),
                  _statusChip('inactive', 'Pasif', Icons.pause_circle),
                  const SizedBox(width: 6),
                  _statusChip('all', 'Tümü', Icons.all_inclusive),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildFilterDropdown(
                      label: 'Departman',
                      key: 'department',
                      currentValue: _departmentFilter,
                      onSelect: (val) {
                        setState(() {
                          _departmentFilter = val;
                          _applyFilters();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildFilterDropdown(
                      label: 'Ünvan',
                      key: 'title',
                      currentValue: _titleFilter,
                      onSelect: (val) {
                        setState(() {
                          _titleFilter = val;
                          _applyFilters();
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _filteredStaff.length,
                  itemBuilder: (_, i) {
                    final staff = _filteredStaff[i];
                    final isSelected =
                        _selectedStaff != null &&
                        _selectedStaff!['id'] == staff['id'];
                    return Card(
                      elevation: isWide && isSelected ? 2 : 0.5,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isSelected
                              ? Colors.indigo
                              : Colors.grey.shade300,
                        ),
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? Colors.indigo
                              : Colors.indigo.shade100,
                          child: const Icon(Icons.person, color: Colors.white),
                        ),
                        title: Text(staff['fullName'] ?? 'Ad Soyad'),
                        subtitle: Text(
                          _formatRole(staff['title']) + 
                          (staff['branch'] != null && staff['branch'].toString().isNotEmpty 
                              ? ' - ${staff['branch']}' 
                              : ''),
                        ),

                        selected: isSelected,
                        onTap: () {
                          setState(() {
                            _selectedStaff = staff;
                          });
                          if (!isWide) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(
                                    title: const Text('Personel Detayı'),
                                  ),
                                  body: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: StaffDetailScreen(staff: staff),
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );

    final right = StaffDetailScreen(staff: _selectedStaff);

    return Scaffold(
      appBar: AppBar(
        title: widget.fixedSchoolTypeName != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.fixedSchoolTypeName!,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Personel Listesi',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                  ),
                ],
              )
            : const Text('Personel Bilgi Yönetimi'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => StaffFormScreen(
                fixedSchoolTypeName: widget.fixedSchoolTypeName,
              ),
            ),
          );
          // Personel eklendiyse listeyi yenile
          if (result == true && mounted) {
            await _loadStaff();
          }
        },
        icon: const Icon(Icons.person_add),
        label: const Text('Yeni Personel'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: isWide
            ? Row(
                children: [
                  SizedBox(width: 380, child: left),
                  const VerticalDivider(width: 20),
                  Expanded(child: StaffDetailScreen(staff: _selectedStaff)),
                ],
              )
            : left,
      ),
    );
  }

  Widget _statusChip(String value, String label, IconData icon) {
    final isSelected = _statusFilter == value;
    final count = _getCount(value);

    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _statusFilter = value;
          _applyFilters();
        }),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.white24,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.indigo : Colors.white,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '$label ($count)',
                  style: TextStyle(
                    color: isSelected ? Colors.indigo : Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String key,
    required String? currentValue,
    required Function(String?) onSelect,
  }) {
    final items = _getUniqueValues(key);
    final isActive = currentValue != null;

    return PopupMenuButton<String>(
      tooltip: '$label Seç',
      itemBuilder: (context) => items.map((item) {
        final isSelected =
            item == currentValue || (item == 'Tümü' && currentValue == null);
        return PopupMenuItem<String>(
          value: item,
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: isSelected ? Colors.indigo : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                item,
                style: TextStyle(
                  color: isSelected ? Colors.indigo : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onSelected: (value) {
        onSelect(value == 'Tümü' ? null : value);
      },
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: isActive ? Colors.indigo.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? Colors.indigo : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.filter_list,
              size: 16,
              color: isActive ? Colors.indigo : Colors.grey,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                currentValue ?? label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.indigo : Colors.black87,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: isActive ? Colors.indigo : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
