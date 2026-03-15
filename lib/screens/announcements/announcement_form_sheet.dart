import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/announcement_service.dart';

class AnnouncementFormSheet extends StatefulWidget {
  final String? announcementId;
  final Map<String, dynamic>? announcementData;
  final String? schoolTypeId;
  final String? schoolTypeName;

  const AnnouncementFormSheet({
    Key? key,
    this.announcementId,
    this.announcementData,
    this.schoolTypeId,
    this.schoolTypeName,
  }) : super(key: key);

  @override
  State<AnnouncementFormSheet> createState() => _AnnouncementFormSheetState();
}

class _AnnouncementFormSheetState extends State<AnnouncementFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _searchController = TextEditingController();
  final AnnouncementService _announcementService = AnnouncementService();

  List<String> _selectedRecipients = [];
  DateTime _publishDate = DateTime.now();
  TimeOfDay _publishTime = TimeOfDay.now();
  final List<TextEditingController> _links = [];
  final List<TextEditingController> _linkNames = [];
  bool _sendSms = false;
  bool _showRecipientSelector = false;
  bool _isAnonymous = false;
  bool _schedulePublish = false;
  List<Map<String, dynamic>> _reminders = [];

  // Firebase'den gelen veriler
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _schoolTypes = [];
  List<Map<String, dynamic>> _classLevels = [];
  List<Map<String, dynamic>> _groups = [];
  bool _isLoadingData = false;
  bool _isSaving = false;

  String _selectedTargetType = '';
  String _selectedSchoolType = '';
  String _selectedClassLevel = '';
  String _selectedBranch = '';

  Set<String> _selectedRecipientTypes = {}; // Öğrenci, Veli, Öğretmen seçimleri
  final List<String> _branches = ['A', 'B', 'C', 'D', 'E', 'F'];

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadExistingData();
  }

  void _loadExistingData() {
    if (widget.announcementData != null) {
      final data = widget.announcementData!;
      _title.text = data['title'] ?? '';
      _content.text = data['content'] ?? '';
      _selectedRecipients = List<String>.from(data['recipients'] ?? []);
      _sendSms = data['sendSms'] ?? false;
      _isAnonymous = data['isAnonymous'] ?? false;
      _schedulePublish = data['schedulePublish'] ?? false;

      // Load publish date/time
      if (data['publishDate'] != null) {
        final publishDate = (data['publishDate'] as Timestamp).toDate();
        _publishDate = publishDate;
      }

      // Load links
      final links = data['links'] as List<dynamic>? ?? [];
      for (var link in links) {
        if (link is Map) {
          _linkNames.add(TextEditingController(text: link['name'] ?? ''));
          _links.add(TextEditingController(text: link['url'] ?? ''));
        } else {
          _linkNames.add(TextEditingController());
          _links.add(TextEditingController(text: link.toString()));
        }
      }

      // Load reminders
      final reminders = data['reminders'] as List<dynamic>? ?? [];
      for (var reminder in reminders) {
        final date = (reminder['date'] as Timestamp).toDate();
        _reminders.add({
          'date': DateTime(date.year, date.month, date.day),
          'time': TimeOfDay(hour: date.hour, minute: date.minute),
          'sent': reminder['sent'] ?? false,
        });
      }
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoadingData = true);
    try {
      List<Map<String, dynamic>> users;
      List<Map<String, dynamic>> schoolTypes;
      List<Map<String, dynamic>> classLevels;

      // Eğer schoolTypeId varsa, sadece o okul türündeki kullanıcıları getir
      if (widget.schoolTypeId != null) {
        users = await _announcementService.getUsersBySchoolType(
          widget.schoolTypeId!,
        );
        // Sadece bu okul türünü göster
        schoolTypes = widget.schoolTypeName != null
            ? [
                {'id': widget.schoolTypeId, 'name': widget.schoolTypeName},
              ]
            : await _announcementService.getSchoolTypes();
        // Sadece bu okul türüne ait sınıf seviyelerini getir
        classLevels = await _announcementService.getClassLevelsBySchoolType(
          widget.schoolTypeId!,
        );
      } else {
        users = await _announcementService.getAllUsers();
        schoolTypes = await _announcementService.getSchoolTypes();
        classLevels = await _announcementService.getClassLevels();
      }

      final units = await _announcementService.getAllUnits();
      final groups = await _announcementService.getGroups();

      setState(() {
        _allUsers = users;
        _units = units;
        _schoolTypes = schoolTypes;
        _classLevels = classLevels;
        _groups = groups;
        _isLoadingData = false;
      });
    } catch (e) {
      setState(() => _isLoadingData = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _searchController.dispose();
    for (var link in _links) {
      link.dispose();
    }
    for (var linkName in _linkNames) {
      linkName.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> _getFilteredUsers() {
    if (_searchController.text.isEmpty) return _allUsers;
    final searchText = _searchController.text.toLowerCase();
    return _allUsers
        .where(
          (user) =>
              user['name'].toString().toLowerCase().contains(searchText) ||
              user['role'].toString().toLowerCase().contains(searchText),
        )
        .toList();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 2),
      initialDate: _publishDate,
    );
    if (picked != null) setState(() => _publishDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _publishTime,
    );
    if (picked != null) setState(() => _publishTime = picked);
  }

  void _addRecipient(String recipientId) {
    if (!_selectedRecipients.contains(recipientId)) {
      setState(() => _selectedRecipients.add(recipientId));
    }
  }

  void _removeRecipient(String recipientId) {
    setState(() => _selectedRecipients.remove(recipientId));
  }

  String _getRecipientDisplayName(String recipientId) {
    if (recipientId.startsWith('user:')) {
      final userId = recipientId.substring(5);
      final user = _allUsers.firstWhere(
        (u) => u['id'] == userId,
        orElse: () => {'name': 'Kullanıcı'},
      );
      return user['name'];
    } else if (recipientId.startsWith('unit:')) {
      final unitId = recipientId.substring(5);
      final unit = _units.firstWhere(
        (u) => u['id'] == unitId,
        orElse: () => {'name': 'Birim'},
      );
      return unit['name'];
    } else if (recipientId.startsWith('school:')) {
      // Format: school:schoolTypeId:type (e.g., school:ABC123:Öğrenciler)
      final parts = recipientId.split(':');
      if (parts.length >= 3) {
        final schoolTypeId = parts[1];
        final type = parts[2];
        // Find the school type name from _schoolTypes
        final schoolType = _schoolTypes.firstWhere(
          (st) => st['id'] == schoolTypeId,
          orElse: () => {'name': 'Okul Türü'},
        );
        return '${schoolType['name']} - $type';
      }
      return recipientId.replaceAll('school:', '').replaceAll(':', ' - ');
    } else if (recipientId.startsWith('class:')) {
      return recipientId.replaceAll('class:', '').replaceAll(':', ' - ');
    } else if (recipientId.startsWith('group:')) {
      final groupId = recipientId.substring(6);
      final group = _groups.firstWhere(
        (g) => g['id'] == groupId,
        orElse: () => {'name': 'Grup'},
      );
      return 'Grup: ${group['name']}';
    }
    return recipientId;
  }

  // Alıcı türü seçim butonları (Öğrenciler, Veliler, Öğretmenler)
  Widget _buildRecipientTypeButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Alıcı Türü:',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildRecipientTypeButton(
                'Öğrenciler',
                Icons.school,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildRecipientTypeButton(
                'Veliler',
                Icons.people,
                Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildRecipientTypeButton(
                'Öğretmenler',
                Icons.person,
                Colors.orange,
              ),
            ),
          ],
        ),
        if (_isLoadingData)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _buildRecipientTypeButton(String label, IconData icon, Color color) {
    final isSelected = _selectedRecipientTypes.contains(label);
    return ElevatedButton(
      onPressed: _isLoadingData ? null : () => _toggleRecipientType(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? color : Colors.grey[200],
        foregroundColor: isSelected ? Colors.white : Colors.grey[800],
        padding: const EdgeInsets.symmetric(vertical: 16),
        elevation: isSelected ? 4 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isSelected ? color : Colors.grey[300]!,
            width: 2,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // Buton tıklandığında direkt ekle/çıkar
  Future<void> _toggleRecipientType(String type) async {
    if (_isLoadingData) return;

    final wasSelected = _selectedRecipientTypes.contains(type);

    setState(() {
      if (wasSelected) {
        _selectedRecipientTypes.remove(type);
      } else {
        _selectedRecipientTypes.add(type);
      }
    });

    if (!wasSelected) {
      // Yeni seçildi, direkt ekle
      await _loadSingleRecipientType(type);
    }
  }

  // Tek bir alıcı türünü yükle
  Future<void> _loadSingleRecipientType(String type) async {
    setState(() => _isLoadingData = true);

    try {
      // Sınıf/şube seçiliyse
      if (_selectedClassLevel.isNotEmpty) {
        final parts = _selectedClassLevel.split('_');
        if (parts.length >= 2) {
          final schoolTypeId = parts[0];
          final className = parts.sublist(1).join('_');

          if (type == 'Öğrenciler') {
            final students = await _announcementService.getStudentsByClass(
              schoolTypeId,
              className,
              _selectedBranch.isEmpty ? null : _selectedBranch,
            );
            for (final student in students) {
              final recipientId = 'user:${student['id']}';
              _addRecipient(recipientId);
            }
          } else if (type == 'Veliler') {
            final students = await _announcementService.getStudentsByClass(
              schoolTypeId,
              className,
              _selectedBranch.isEmpty ? null : _selectedBranch,
            );
            final studentIds = students.map((s) => s['id'] as String).toList();
            if (studentIds.isNotEmpty) {
              final parents = await _announcementService.getParentsByStudents(
                studentIds,
              );
              for (final parent in parents) {
                final recipientId = 'user:${parent['id']}';
                _addRecipient(recipientId);
              }
            }
          } else if (type == 'Öğretmenler') {
            final teachers = await _announcementService.getTeachersByClass(
              schoolTypeId,
              className,
            );
            for (final teacher in teachers) {
              final recipientId = 'user:${teacher['id']}';
              _addRecipient(recipientId);
            }
          }
        }
      }
      // Okul türü seçiliyse
      else if (_selectedSchoolType.isNotEmpty) {
        final recipientId = 'school:$_selectedSchoolType:$type';
        _addRecipient(recipientId);
      }

      setState(() => _isLoadingData = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$type eklendi'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoadingData = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildRecipientSelector() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: _showRecipientSelector
          ? Card(
              elevation: 0,
              color: Colors.grey[50],
              margin: const EdgeInsets.symmetric(vertical: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Alıcı Ekle',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              setState(() => _showRecipientSelector = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.blue[200]!),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      child: DropdownButtonFormField<String>(
                        value: _selectedTargetType.isEmpty
                            ? null
                            : _selectedTargetType,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Hedef Kitle Türü',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          prefixIcon: Icon(
                            Icons.people,
                            color: Colors.blue[700],
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'user',
                            child: Text(
                              '👤 Kişi Ekle',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'unit',
                            child: Text(
                              '🏢 Birim Ekle',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'school',
                            child: Text(
                              '🏫 Okul Türü Ekle',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'class',
                            child: Text(
                              '📚 Sınıf Seviyesi Ekle',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'group',
                            child: Text(
                              '👥 Grup Seç',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedTargetType = value ?? '';
                            _selectedSchoolType = '';
                            _selectedClassLevel = '';
                            _selectedBranch = '';
                            _searchController.clear();
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildTargetTypeContent(),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildTargetTypeContent() {
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (_selectedTargetType) {
      case 'user':
        return _buildUserList();
      case 'unit':
        return _buildUnitList();
      case 'school':
        return _buildSchoolTypeSelector();
      case 'class':
        return _buildClassLevelSelector();
      case 'group':
        return _buildGroupList();
      default:
        return const Center(child: Text('Lütfen hedef kitle türü seçiniz'));
    }
  }

  Widget _buildUserList() {
    final users = _getFilteredUsers();
    final visibleCount = users.isEmpty ? 0 : math.min(users.length, 5);
    final listHeight = visibleCount * 72.0; // yaklaşık bir ListTile yüksekliği

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Kullanıcı ara...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() => _searchController.clear());
                    },
                  )
                : null,
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        if (users.isEmpty)
          const SizedBox(
            height: 60,
            child: Center(child: Text('Kullanıcı bulunamadı')),
          )
        else
          SizedBox(
            height: listHeight,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                final userId = 'user:${user['id']}';
                final isSelected = _selectedRecipients.contains(userId);
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue[100],
                      child: Text(
                        user['name'][0].toUpperCase(),
                        style: TextStyle(color: Colors.blue[700]),
                      ),
                      radius: 20,
                    ),
                    title: Text(
                      user['name'],
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(user['role']),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 28,
                          )
                        : const Icon(Icons.add_circle_outline, size: 28),
                    onTap: () {
                      if (isSelected) {
                        _removeRecipient(userId);
                      } else {
                        _addRecipient(userId);
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

  Widget _buildUnitList() {
    return SizedBox(
      height: 300,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _units.length,
        itemBuilder: (context, index) {
          final unit = _units[index];
          final unitId = 'unit:${unit['id']}';
          final isSelected = _selectedRecipients.contains(unitId);
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              dense: true,
              leading: Icon(
                Icons.business,
                size: 20,
                color: Colors.orange[700],
              ),
              title: Text(unit['name']),
              trailing: isSelected
                  ? const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 28,
                    )
                  : const Icon(Icons.add_circle_outline, size: 28),
              onTap: () {
                if (isSelected) {
                  _removeRecipient(unitId);
                } else {
                  _addRecipient(unitId);
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildSchoolTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.orange[200]!),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: DropdownButtonFormField<String>(
            value: _selectedSchoolType.isEmpty ? null : _selectedSchoolType,
            decoration: InputDecoration(
              labelText: 'Okul Türü Seç',
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              prefixIcon: Icon(Icons.school, color: Colors.orange[700]),
            ),
            items: _schoolTypes
                .map(
                  (type) => DropdownMenuItem<String>(
                    value: type['id'].toString(),
                    child: Text(type['name'].toString()),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedSchoolType = value ?? '';
              });
            },
          ),
        ),
        if (_selectedSchoolType.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildRecipientTypeButtons(),
        ],
      ],
    );
  }

  Widget _buildClassLevelSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.purple[200]!),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: DropdownButtonFormField<String>(
            value: _selectedClassLevel.isEmpty ? null : _selectedClassLevel,
            decoration: InputDecoration(
              labelText: 'Sınıf Seviyesi Seç',
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              prefixIcon: Icon(Icons.class_, color: Colors.purple[700]),
            ),
            items: _classLevels
                .map(
                  (level) => DropdownMenuItem<String>(
                    value: level['id'].toString(),
                    child: Text('${level['name']} (${level['schoolType']})'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedClassLevel = value ?? '';
              });
            },
          ),
        ),
        if (_selectedClassLevel.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.teal[200]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: DropdownButtonFormField<String>(
              value: _selectedBranch.isEmpty ? null : _selectedBranch,
              decoration: InputDecoration(
                labelText: 'Şube Seç (Opsiyonel)',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                prefixIcon: Icon(Icons.menu_book, color: Colors.teal[700]),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('Tüm Şubeler'),
                ),
                ..._branches.map(
                  (branch) => DropdownMenuItem<String>(
                    value: branch,
                    child: Text('$branch Şubesi'),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedBranch = value ?? '';
                  _selectedRecipientTypes.clear();
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildRecipientTypeButtons(),
        ],
      ],
    );
  }

  Widget _buildGroupList() {
    if (_groups.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.group_off, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text('Henüz kaydedilmiş grup yok'),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 300,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _groups.length,
        itemBuilder: (context, index) {
          final group = _groups[index];
          final groupId = 'group:${group['id']}';
          final isSelected = _selectedRecipients.contains(groupId);
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              dense: true,
              leading: Icon(Icons.group, size: 20, color: Colors.purple[700]),
              title: Text(group['name']),
              subtitle: Text('${(group['recipients'] as List).length} alıcı'),
              trailing: isSelected
                  ? const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 28,
                    )
                  : const Icon(Icons.add_circle_outline, size: 28),
              onTap: () {
                if (isSelected) {
                  _removeRecipient(groupId);
                } else {
                  _addRecipient(groupId);
                }
              },
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Form(
            key: _formKey,
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.all(20),
              children: [
                // Header
                Row(
                  children: [
                    const Text(
                      'Yeni Duyuru',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey[100],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Alıcı Seçimi Section
                Card(
                  elevation: 0,
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.people, color: Colors.blue[700]),
                            const SizedBox(width: 8),
                            Text(
                              'Alıcılar (${_selectedRecipients.length})',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.blue[900],
                              ),
                            ),
                            const Spacer(),
                            FilledButton.tonalIcon(
                              onPressed: () => setState(
                                () => _showRecipientSelector =
                                    !_showRecipientSelector,
                              ),
                              icon: Icon(
                                _showRecipientSelector
                                    ? Icons.remove
                                    : Icons.add,
                                size: 18,
                              ),
                              label: Text(
                                _showRecipientSelector ? 'Gizle' : 'Alıcı Ekle',
                              ),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_selectedRecipients.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _selectedRecipients.map((recipientId) {
                              return Chip(
                                avatar: CircleAvatar(
                                  backgroundColor: Colors.blue[200],
                                  child: const Icon(
                                    Icons.person,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                                label: Text(
                                  _getRecipientDisplayName(recipientId),
                                ),
                                deleteIcon: const Icon(Icons.close, size: 16),
                                onDeleted: () => _removeRecipient(recipientId),
                                backgroundColor: Colors.white,
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Inline Recipient Selector
                _buildRecipientSelector(),

                const SizedBox(height: 16),

                // Başlık
                TextFormField(
                  controller: _title,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Zorunlu' : null,
                  decoration: InputDecoration(
                    labelText: 'Duyuru Başlığı *',
                    hintText: 'Örn: Veli Toplantısı Duyurusu',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.title),
                  ),
                ),
                const SizedBox(height: 16),

                // İçerik
                TextFormField(
                  controller: _content,
                  maxLines: 6,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Zorunlu' : null,
                  decoration: InputDecoration(
                    labelText: 'Duyuru İçeriği *',
                    hintText:
                        'Duyurunuzun detaylı açıklamasını buraya yazın...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignLabelWithHint: true,
                  ),
                ),

                const SizedBox(height: 16),

                // Anonim Paylaşım
                Card(
                  elevation: 0,
                  color: Colors.blue[50],
                  child: SwitchListTile(
                    value: _isAnonymous,
                    onChanged: (value) => setState(() => _isAnonymous = value),
                    title: Row(
                      children: [
                        Icon(
                          Icons.visibility_off,
                          color: Colors.blue[700],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Anonim Paylaşım',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    subtitle: _isAnonymous
                        ? const Text('Duyuru kurum adıyla paylaşılacak')
                        : const Text('Duyuru adınızla paylaşılacak'),
                    activeColor: Colors.blue[700],
                  ),
                ),

                const SizedBox(height: 16),

                // Yayın Zamanı Planla
                Card(
                  elevation: 0,
                  color: Colors.purple[50],
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _schedulePublish,
                        onChanged: (value) =>
                            setState(() => _schedulePublish = value),
                        title: Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              color: Colors.purple[700],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Yayını Planla',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        subtitle: _schedulePublish
                            ? const Text(
                                'Belirlenen tarih ve saatte yayınlanacak',
                              )
                            : const Text('Hemen yayınlanacak'),
                        activeColor: Colors.purple[700],
                      ),
                      if (_schedulePublish) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: _pickDate,
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: 'Tarih',
                                      border: const OutlineInputBorder(),
                                      filled: true,
                                      fillColor: Colors.white,
                                      suffixIcon: Icon(
                                        Icons.calendar_month,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    child: Text(
                                      '${_publishDate.day}/${_publishDate.month}/${_publishDate.year}',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InkWell(
                                  onTap: _pickTime,
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: 'Saat',
                                      border: const OutlineInputBorder(),
                                      filled: true,
                                      fillColor: Colors.white,
                                      suffixIcon: Icon(
                                        Icons.access_time,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    child: Text(_publishTime.format(context)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Hatırlatmalar
                Card(
                  elevation: 0,
                  color: Colors.amber[50],
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.notifications_active,
                                  color: Colors.amber[700],
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Hatırlatma Zamanları',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber[900],
                                  ),
                                ),
                                const Spacer(),
                                Builder(
                                  builder: (context) {
                                    final isMobile =
                                        MediaQuery.of(context).size.width < 600;

                                    Future<void> onAddReminder() async {
                                      final date = await showDatePicker(
                                        context: context,
                                        firstDate: DateTime.now(),
                                        lastDate: DateTime(
                                          DateTime.now().year + 2,
                                        ),
                                        initialDate: DateTime.now().add(
                                          const Duration(days: 1),
                                        ),
                                      );
                                      if (date == null || !mounted) return;

                                      final time = await showTimePicker(
                                        context: context,
                                        initialTime: TimeOfDay.now(),
                                      );
                                      if (time == null || !mounted) return;

                                      setState(() {
                                        _reminders.add({
                                          'date': date,
                                          'time': time,
                                        });
                                      });
                                    }

                                    if (isMobile) {
                                      return OutlinedButton(
                                        onPressed: onAddReminder,
                                        style: OutlinedButton.styleFrom(
                                          shape: const CircleBorder(),
                                          padding: const EdgeInsets.all(10),
                                          minimumSize: const Size(36, 36),
                                          side: BorderSide(
                                            color: Colors.amber[300]!,
                                          ),
                                          foregroundColor: Colors.amber[700],
                                        ),
                                        child: const Icon(
                                          Icons.add_alarm,
                                          size: 20,
                                        ),
                                      );
                                    }

                                    return OutlinedButton.icon(
                                      onPressed: onAddReminder,
                                      icon: const Icon(
                                        Icons.add_alarm,
                                        size: 18,
                                      ),
                                      label: const Text('Hatırlatma Ekle'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.amber[700],
                                        side: BorderSide(
                                          color: Colors.amber[300]!,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            if (_reminders.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              ..._reminders.asMap().entries.map((entry) {
                                final index = entry.key;
                                final reminder = entry.value;
                                final date = reminder['date'] as DateTime;
                                final time = reminder['time'] as TimeOfDay;
                                return Card(
                                  color: Colors.white,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: Icon(
                                      Icons.alarm,
                                      color: Colors.amber[700],
                                    ),
                                    title: Text(
                                      '${date.day}/${date.month}/${date.year} - ${time.format(context)}',
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, size: 20),
                                      onPressed: () => setState(
                                        () => _reminders.removeAt(index),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // SMS ve Dosyalar
                Card(
                  elevation: 0,
                  color: Colors.green[50],
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _sendSms,
                        onChanged: (value) => setState(() => _sendSms = value),
                        title: Row(
                          children: [
                            Icon(Icons.sms, color: Colors.green[700], size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'SMS Gönderimi',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        subtitle: _sendSms
                            ? const Text('SMS alıcılara gönderilecek')
                            : null,
                        activeColor: Colors.green[700],
                      ),
                      if (_sendSms)
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.green[800],
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Hedef kitlenin kayıtlı telefonlarına SMS gönderilecektir.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green[900],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Bağlantı ve Dosyalar
                Card(
                  elevation: 0,
                  color: Colors.orange[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.attachment,
                              color: Colors.orange[700],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Ekler ve Bağlantılar',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[900],
                              ),
                            ),
                            const Spacer(),
                            IconButton.outlined(
                              onPressed: () => setState(() {
                                _links.add(TextEditingController());
                                _linkNames.add(TextEditingController());
                              }),
                              icon: const Icon(Icons.add_link, size: 20),
                              tooltip: 'Bağlantı Ekle',
                              color: Colors.orange[700],
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 8),
                            IconButton.outlined(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Dosya yükleme yakında eklenecek',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.upload_file, size: 20),
                              tooltip: 'Dosya Ekle',
                              color: Colors.orange[700],
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_links.isNotEmpty) ...[
                          ..._links.asMap().entries.map(
                            (e) => Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  children: [
                                    TextFormField(
                                      controller: _linkNames.length > e.key
                                          ? _linkNames[e.key]
                                          : null,
                                      decoration: const InputDecoration(
                                        labelText: 'Bağlantı Adı',
                                        hintText: 'Örn: Ders Programı',
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.label, size: 20),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      controller: e.value,
                                      decoration: InputDecoration(
                                        labelText: 'URL',
                                        hintText: 'https://ornek.com',
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: const OutlineInputBorder(),
                                        prefixIcon: const Icon(
                                          Icons.link,
                                          size: 20,
                                        ),
                                        suffixIcon: IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          onPressed: () => setState(() {
                                            _links.removeAt(e.key);
                                            if (_linkNames.length > e.key) {
                                              _linkNames[e.key].dispose();
                                              _linkNames.removeAt(e.key);
                                            }
                                          }),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _isSaving
                            ? null
                            : () async {
                                if (_formKey.currentState?.validate() != true)
                                  return;
                                if (_selectedRecipients.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Lütfen en az bir alıcı ekleyin',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                try {
                                  setState(() => _isSaving = true);

                                  final links = List.generate(_links.length, (
                                    i,
                                  ) {
                                    final url = _links[i].text.trim();
                                    final name = _linkNames.length > i
                                        ? _linkNames[i].text.trim()
                                        : '';
                                    if (url.isEmpty) return null;
                                    return {
                                      'name': name.isEmpty
                                          ? 'Bağlantı ${i + 1}'
                                          : name,
                                      'url': url,
                                    };
                                  }).where((l) => l != null).toList();

                                  final publishTimeStr =
                                      '${_publishTime.hour.toString().padLeft(2, '0')}:${_publishTime.minute.toString().padLeft(2, '0')}';

                                  // Ana duyuru normal başlıkla kaydedilir
                                  // Hatırlatma ön eki sadece hatırlatma duyurularına otomatik eklenir
                                  final finalTitle = _title.text.trim();

                                  if (widget.announcementId != null) {
                                    // Düzenleme modu
                                    final remindersList = _reminders.map((r) {
                                      final date = r['date'] as DateTime;
                                      final time = r['time'] as TimeOfDay;
                                      return {
                                        'date': Timestamp.fromDate(
                                          DateTime(
                                            date.year,
                                            date.month,
                                            date.day,
                                            time.hour,
                                            time.minute,
                                          ),
                                        ),
                                        'sent': r['sent'] ?? false,
                                      };
                                    }).toList();

                                    await _announcementService.updateAnnouncement(
                                      widget.announcementId!,
                                      {
                                        'title': finalTitle,
                                        'content': _content.text.trim(),
                                        'recipients': _selectedRecipients,
                                        'publishDate': Timestamp.fromDate(
                                          DateTime(
                                            _publishDate.year,
                                            _publishDate.month,
                                            _publishDate.day,
                                            _publishTime.hour,
                                            _publishTime.minute,
                                          ),
                                        ),
                                        'publishTime': publishTimeStr,
                                        'sendSms': _sendSms,
                                        'links': links,
                                        'isAnonymous': _isAnonymous,
                                        'schedulePublish': _schedulePublish,
                                        'status': _schedulePublish
                                            ? 'scheduled'
                                            : 'published',
                                        'reminders': remindersList,
                                        'isReminder':
                                            false, // Ana duyuru hatırlatma değil
                                      },
                                    );
                                  } else {
                                    // Yeni duyuru
                                    await _announcementService.saveAnnouncement(
                                      title: finalTitle,
                                      content: _content.text.trim(),
                                      recipients: _selectedRecipients,
                                      publishDate: DateTime(
                                        _publishDate.year,
                                        _publishDate.month,
                                        _publishDate.day,
                                        _publishTime.hour,
                                        _publishTime.minute,
                                      ),
                                      publishTime: publishTimeStr,
                                      sendSms: _sendSms,
                                      links: links,
                                      isAnonymous: _isAnonymous,
                                      schedulePublish: _schedulePublish,
                                      reminders: _reminders,
                                      schoolTypeId: widget.schoolTypeId,
                                    );
                                  }

                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        widget.announcementId != null
                                            ? 'Duyuru güncellendi'
                                            : 'Duyuru başarıyla kaydedildi',
                                      ),
                                      backgroundColor: Colors.green,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                  // Sadece düzenleme modunda sayfayı kapat
                                  if (widget.announcementId != null) {
                                    Navigator.pop(context);
                                  } else {
                                    // Yeni duyuru eklendiyse formu temizle
                                    _title.clear();
                                    _content.clear();
                                    setState(() {
                                      _selectedRecipients.clear();
                                      _publishDate = DateTime.now();
                                      _publishTime = TimeOfDay.now();
                                      _sendSms = false;
                                      _isAnonymous = false;
                                      _schedulePublish = false;
                                      _reminders.clear();
                                      for (var link in _links) {
                                        link.dispose();
                                      }
                                      for (var linkName in _linkNames) {
                                        linkName.dispose();
                                      }
                                      _links.clear();
                                      _linkNames.clear();
                                      _selectedRecipientTypes.clear();
                                      _selectedTargetType = '';
                                      _selectedSchoolType = '';
                                      _selectedClassLevel = '';
                                      _selectedBranch = '';
                                    });
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Kaydetme hatası: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                } finally {
                                  if (mounted)
                                    setState(() => _isSaving = false);
                                }
                              },
                        icon: const Icon(Icons.send),
                        label: Text(
                          _isSaving ? 'Kaydediliyor...' : 'Kaydet ve Gönder',
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          if (_formKey.currentState?.validate() != true) return;
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.drafts),
                        label: const Text('Taslak'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}
