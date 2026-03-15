import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../services/announcement_service.dart';

class AliciSecimi extends StatefulWidget {
  final List<String> selectedRecipients;
  final Map<String, String> initialRecipientNames; // NEW: Initial names
  final List<String> savedGroups;
  final Function(List<String>)? onRecipientsUpdated;
  final Function(String) onSaveGroup;
  final String? schoolTypeId; // NEW: Optional context
  final Function(Map<String, String>)?
  onRecipientNamesUpdated; // NEW: Return names
  final Function(List<String>, Map<String, String>)?
  onConfirmed; // NEW: Unified callback
  final bool isPage; // NEW: Display as a full page Scaffold

  const AliciSecimi({
    Key? key,
    required this.selectedRecipients,
    this.initialRecipientNames = const {},
    required this.savedGroups,
    this.onRecipientsUpdated,
    required this.onSaveGroup,
    this.schoolTypeId,
    this.onRecipientNamesUpdated,
    this.onConfirmed,
    this.isPage = false,
  }) : super(key: key);

  @override
  State<AliciSecimi> createState() => _AliciSecimiState();
}

class _AliciSecimiState extends State<AliciSecimi> {
  late List<String> _selectedRecipients;
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final AnnouncementService _announcementService = AnnouncementService();

  String _selectedTargetType = '';
  String _selectedSchoolType = '';
  String _selectedClassLevel = '';

  // Firebase'den gelecek veriler
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _schoolTypes = [];
  List<Map<String, dynamic>> _classLevels = [];
  List<Map<String, dynamic>> _groups = [];

  // Displayed users for search filtering
  List<Map<String, dynamic>> _displayedUsers = [];

  final List<String> _recipientTypes = ['Öğrenciler', 'Veliler', 'Öğretmenler'];

  bool _isLoading = false;

  // Map to store display names for recipients (ID -> Name)
  Map<String, String> _recipientNames = {};

  @override
  void initState() {
    super.initState();
    _selectedRecipients = List.from(widget.selectedRecipients);
    _recipientNames = Map.from(widget.initialRecipientNames);
    // Auto-select school type if provided in context
    if (widget.schoolTypeId != null) {
      _selectedSchoolType = widget.schoolTypeId!;
    }
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // If schoolTypeId is provided, use the school-type-specific method to get students
      List<Map<String, dynamic>> users;
      if (widget.schoolTypeId != null) {
        users = await _announcementService.getUsersBySchoolType(
          widget.schoolTypeId!,
        );
      } else {
        users = await _announcementService.getAllUsers(
          schoolTypeId: widget.schoolTypeId,
        );
      }

      final units = await _announcementService.getAllUnits();
      final schoolTypes = await _announcementService.getSchoolTypes();
      final classLevels = await _announcementService.getClassLevels();
      final groups = await _announcementService.getGroups();

      // Filter school types if context provided
      List<Map<String, dynamic>> filteredSchoolTypes;
      if (widget.schoolTypeId != null) {
        filteredSchoolTypes = schoolTypes
            .where((s) => s['id'] == widget.schoolTypeId)
            .toList();
      } else {
        filteredSchoolTypes = schoolTypes;
      }

      setState(() {
        _allUsers = users;
        _displayedUsers = users;
        _units = units;
        _schoolTypes = filteredSchoolTypes;
        _classLevels = classLevels;
        _groups = groups;
        _isLoading = false;
      });

      // Load branches AFTER schoolTypes have been set
      if (widget.schoolTypeId != null) {
        await _loadBranchesForSchoolType(widget.schoolTypeId!);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veriler yüklenirken hata oluştu: $e')),
        );
      }
    }
  }

  Widget _buildClassSelection() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    List<Map<String, dynamic>> filteredLevels = _classLevels;

    if (_selectedSchoolType.isNotEmpty) {
      filteredLevels = _classLevels
          .where(
            (l) =>
                l['schoolTypeId'] == _selectedSchoolType ||
                l['schoolType'] == _getSchoolTypeName(_selectedSchoolType),
          )
          .toList();
    } else if (widget.schoolTypeId != null) {
      filteredLevels = _classLevels
          .where(
            (l) =>
                l['schoolTypeId'] == widget.schoolTypeId ||
                l['schoolType'] == _getSchoolTypeName(widget.schoolTypeId!),
          )
          .toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.schoolTypeId == null)
          DropdownButtonFormField<String>(
            value: _selectedSchoolType.isEmpty ? null : _selectedSchoolType,
            decoration: const InputDecoration(
              labelText: 'Okul Türüne Göre Filtrele',
              border: OutlineInputBorder(),
            ),
            items: _schoolTypes
                .map(
                  (st) => DropdownMenuItem<String>(
                    value: st['id'] as String,
                    child: Text(st['name'] as String),
                  ),
                )
                .toList(),
            onChanged: (val) {
              setState(() {
                _selectedSchoolType = val ?? '';
                _selectedClassLevel = '';
              });
            },
          ),

        if (widget.schoolTypeId == null) const SizedBox(height: 16),

        DropdownButtonFormField<String>(
          value: _selectedClassLevel.isEmpty ? null : _selectedClassLevel,
          decoration: const InputDecoration(
            labelText: 'Sınıf Seviyesi Seç',
            border: OutlineInputBorder(),
          ),
          items: filteredLevels
              .map(
                (level) => DropdownMenuItem<String>(
                  value: level['id'] as String,
                  child: Text(
                    _selectedSchoolType.isNotEmpty ||
                            widget.schoolTypeId != null
                        ? level['name']
                        : '${level['name']} (${level['schoolType']})',
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            setState(() => _selectedClassLevel = value ?? '');
          },
        ),

        if (_selectedClassLevel.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Alıcı Türü Seç',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._recipientTypes.map((type) {
            final recipientId = 'class:$_selectedClassLevel:$type';
            final className = _getClassName(_selectedClassLevel);
            final displayName = '$className-$type';
            return CheckboxListTile(
              title: Text(type),
              subtitle: Text('$className $type'),
              value: _selectedRecipients.contains(recipientId),
              onChanged: (value) {
                if (value == true) {
                  _addRecipients(
                    [recipientId],
                    names: {recipientId: displayName},
                  );
                } else {
                  _removeRecipient(recipientId);
                }
              },
            );
          }),
        ],
      ],
    );
  }

  String _getClassName(String id) {
    final classLevel = _classLevels.firstWhere(
      (cl) => cl['id'] == id,
      orElse: () => {'name': id, 'schoolType': ''},
    );
    return classLevel['name'];
  }

  Future<void> _showSaveGroupDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Grup Kaydet'),
        content: TextField(
          controller: _groupNameController,
          decoration: const InputDecoration(
            labelText: 'Grup Adı',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () async {
              if (_groupNameController.text.isNotEmpty) {
                try {
                  await _announcementService.saveGroup(
                    _groupNameController.text,
                    _selectedRecipients,
                  );
                  widget.onSaveGroup(_groupNameController.text);
                  _groupNameController.clear();
                  Navigator.pop(context);
                  await _loadData(); // Grupları yeniden yükle
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Grup başarıyla kaydedildi'),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Grup kaydedilemedi: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  void _addRecipients(List<String> recipients, {Map<String, String>? names}) {
    setState(() {
      _selectedRecipients.addAll(recipients);
      _selectedRecipients = _selectedRecipients.toSet().toList();

      if (names != null) {
        _recipientNames.addAll(names);
      }
    });
    widget.onRecipientsUpdated?.call(_selectedRecipients);
    widget.onRecipientNamesUpdated?.call(_recipientNames);
  }

  void _removeRecipient(String recipient) {
    setState(() {
      _selectedRecipients.remove(recipient);
      _recipientNames.remove(recipient);
    });
    widget.onRecipientsUpdated?.call(_selectedRecipients);
    widget.onRecipientNamesUpdated?.call(_recipientNames);
  }

  void _clearAllRecipients() {
    setState(() {
      _selectedRecipients.clear();
      _recipientNames.clear();
    });
    widget.onRecipientsUpdated?.call(_selectedRecipients);
    widget.onRecipientNamesUpdated?.call(_recipientNames);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;
    final showAsPage = widget.isPage || isMobile;

    if (showAsPage) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo.shade600, Colors.purple.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Alıcı Seçimi',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                'Hedef kitlenizi seçin',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.8),
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          leading: IconButton(
            icon: Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            if (_selectedRecipients.isNotEmpty)
              Center(
                child: Container(
                  margin: EdgeInsets.only(right: 16),
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 14),
                      SizedBox(width: 4),
                      Text(
                        '${_selectedRecipients.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          elevation: 0,
        ),
        body: Column(
          children: [
            _buildCategorySelector(),
            Expanded(
              child: Container(
                padding: EdgeInsets.all(16),
                child: _buildTargetSpecificContent(),
              ),
            ),
            _buildBottomActionBar(isMobile: true),
          ],
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: Container(
        width: 650,
        height: 720,
        constraints: BoxConstraints(maxWidth: 650, maxHeight: 720),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 30,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modern Header with Gradient
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.indigo.shade600, Colors.purple.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.people_alt_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Alıcı Seçimi',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Hedef kitlenizi seçin',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedRecipients.isNotEmpty)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 16,
                          ),
                          SizedBox(width: 4),
                          Text(
                            '${_selectedRecipients.length}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            _buildCategorySelector(),

            // Content Area
            Expanded(
              child: Container(
                padding: EdgeInsets.all(16),
                child: _buildTargetSpecificContent(),
              ),
            ),

            _buildBottomActionBar(isMobile: false),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: BouncingScrollPhysics(),
          child: Row(
            children: [
              _buildCategoryChip('person', Icons.person, 'Kişi'),
              SizedBox(width: 8),
              _buildCategoryChip('branch', Icons.class_, 'Şube'),
              SizedBox(width: 8),
              _buildCategoryChip('class', Icons.school, 'Sınıf'),
              SizedBox(width: 8),
              _buildCategoryChip('school', Icons.account_balance, 'Okul'),
              SizedBox(width: 8),
              _buildCategoryChip('unit', Icons.business, 'Birim'),
              SizedBox(width: 8),
              _buildCategoryChip('group', Icons.group, 'Grup'),
              SizedBox(width: 8),
              _buildCategoryChip('selected', Icons.check_circle, 'Seçilenler'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActionBar({required bool isMobile}) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: isMobile
            ? null
            : BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_selectedRecipients.isNotEmpty) ...[
            _buildActionButton(
              icon: Icons.clear_all,
              label: 'Temizle',
              color: Colors.red.shade400,
              onPressed: _clearAllRecipients,
            ),
            _buildActionButton(
              icon: Icons.save,
              label: 'Grup Kaydet',
              color: Colors.green.shade500,
              onPressed: _showSaveGroupDialog,
            ),
          ],
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text('İptal', style: TextStyle(fontSize: 14)),
          ),
          ElevatedButton(
            onPressed: () {
              if (widget.onConfirmed != null) {
                widget.onConfirmed!(_selectedRecipients, _recipientNames);
              } else {
                widget.onRecipientsUpdated?.call(_selectedRecipients);
                widget.onRecipientNamesUpdated?.call(_recipientNames);
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 18),
                SizedBox(width: 8),
                Text(
                  'Tamam',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String value, IconData icon, String label) {
    final isSelected = _selectedTargetType == value;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedTargetType = value;
            _selectedSchoolType = '';
            _selectedClassLevel = '';
            if (value == 'branch') {
              _loadAllBranches();
            }
          });
        },
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.indigo : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? Colors.indigo : Colors.grey.shade300,
              width: 1.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.indigo.withOpacity(0.3),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : Colors.grey.shade600,
              ),
              SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: color),
      label: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w500),
      ),
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildTargetSpecificContent() {
    switch (_selectedTargetType) {
      case 'person':
        return _buildPersonSelection();
      case 'unit':
        return _buildUnitSelection();
      case 'school':
        return _buildSchoolSelection();
      case 'branch':
        return _buildBranchSelection();
      case 'class':
        return _buildClassSelection();
      case 'group':
        return _buildGroupSelection();
      case 'selected':
        return _buildSelectedRecipientsList();
      default:
        return const Center(
          child: Text(
            'Lütfen hedef kitle seçiniz',
            style: TextStyle(color: Colors.grey),
          ),
        );
    }
  }

  Widget _buildBranchSelection() {
    if (_loadingBranches) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.indigo),
            SizedBox(height: 16),
            Text(
              'Şubeler yükleniyor...',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    if (_branches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.class_, size: 64, color: Colors.grey.shade300),
            SizedBox(height: 16),
            Text(
              'Şube bulunamadı',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.class_, color: Colors.green.shade700, size: 20),
              SizedBox(width: 8),
              Text(
                'Şube Seç',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
              Spacer(),
              Text(
                '${_branches.length} şube',
                style: TextStyle(color: Colors.green.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: _branches.length,
            itemBuilder: (context, index) {
              final branch = _branches[index];
              return Container(
                margin: EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.class_,
                        color: Colors.green.shade700,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      branch['name'],
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${branch['classLevel']}. Sınıf',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                    children: _recipientTypes.map((type) {
                      final rId = 'branch:${branch['id']}:$type';
                      final isSelected = _selectedRecipients.contains(rId);
                      final branchName = branch['name'] ?? 'Şube';
                      final displayName = '$branchName-$type';

                      Color typeColor = _getTypeColor(type);

                      return Container(
                        margin: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? typeColor.withOpacity(0.1)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? typeColor
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: CheckboxListTile(
                          title: Text(
                            type,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isSelected
                                  ? typeColor
                                  : Colors.grey.shade700,
                            ),
                          ),
                          value: isSelected,
                          activeColor: typeColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          onChanged: (val) {
                            if (val == true) {
                              _addRecipients([rId], names: {rId: displayName});
                            } else {
                              _removeRecipient(rId);
                            }
                            setState(() {});
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'Öğrenciler':
        return Colors.blue;
      case 'Veliler':
        return Colors.orange;
      case 'Öğretmenler':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Future<void> _loadAllBranches() async {
    setState(() => _loadingBranches = true);
    try {
      List<Map<String, dynamic>> all = [];

      if (widget.schoolTypeId != null) {
        var b = await _announcementService.getBranches(widget.schoolTypeId!);
        all.addAll(b);
      } else {
        for (var st in _schoolTypes) {
          var b = await _announcementService.getBranches(st['id']);
          all.addAll(b);
        }
      }

      setState(() {
        _branches = all;
        _loadingBranches = false;
      });
    } catch (e) {
      setState(() => _loadingBranches = false);
    }
  }

  Future<void> _loadBranchesForSchoolType(String schoolTypeId) async {
    setState(() => _loadingBranches = true);
    try {
      final branches = await _announcementService.getBranches(schoolTypeId);
      setState(() {
        _branches = branches;
        _loadingBranches = false;
      });
    } catch (e) {
      setState(() => _loadingBranches = false);
    }
  }

  String _selectedBranchId = '';
  List<Map<String, dynamic>> _branches = [];
  bool _loadingBranches = false;

  String _buildUserSubtitle(Map<String, dynamic> user) {
    final rawRole = user['role'] ?? 'Kullanıcı';
    final role = _normalizeRole(rawRole);
    final branch = user['branch']?.toString() ?? '';

    if (role == 'Öğrenci' && branch.isNotEmpty) {
      return '$role - $branch';
    } else if (branch.isNotEmpty) {
      return '$role - $branch';
    } else if (user['email'] != null && user['email'].toString().isNotEmpty) {
      return '$role - ${user['email']}';
    } else {
      return role;
    }
  }

  String _normalizeRole(String role) {
    final lowerRole = role.toLowerCase().trim();

    if (lowerRole == 'ogretmen' ||
        lowerRole == 'öğretmen' ||
        lowerRole == 'teacher') {
      return 'Öğretmen';
    } else if (lowerRole == 'ogrenci' ||
        lowerRole == 'öğrenci' ||
        lowerRole == 'student') {
      return 'Öğrenci';
    } else if (lowerRole == 'veli' || lowerRole == 'parent') {
      return 'Veli';
    } else if (lowerRole == 'mudur' ||
        lowerRole == 'müdür' ||
        lowerRole == 'principal') {
      return 'Müdür';
    } else if (lowerRole == 'mudur yardimcisi' ||
        lowerRole == 'müdür yardımcısı') {
      return 'Müdür Yardımcısı';
    } else if (lowerRole == 'rehber' ||
        lowerRole == 'counselor' ||
        lowerRole == 'rehber öğretmen') {
      return 'Rehber Öğretmen';
    } else if (lowerRole == 'idari personel' || lowerRole == 'staff') {
      return 'İdari Personel';
    } else if (lowerRole == 'admin' || lowerRole == 'yönetici') {
      return 'Yönetici';
    }

    if (role.isNotEmpty) {
      return role[0].toUpperCase() + role.substring(1);
    }
    return 'Kullanıcı';
  }

  Widget _buildPersonSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Kullanıcı Ara',
              hintText: 'Ad, soyad veya e-posta yazınız...',
              prefixIcon: Icon(Icons.search, color: Colors.indigo),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _displayedUsers = List.from(_allUsers);
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            onChanged: (val) {
              if (val.length > 2) {
                _performUserSearch(val);
              } else if (val.isEmpty) {
                setState(() {
                  _displayedUsers = List.from(_allUsers);
                });
              }
            },
          ),
        ),
        SizedBox(height: 16),

        if (_displayedUsers.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '${_displayedUsers.length} kullanıcı bulundu',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),

        Expanded(
          child: _isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.indigo),
                      SizedBox(height: 12),
                      Text(
                        'Yükleniyor...',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : _displayedUsers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search, size: 64, color: Colors.grey.shade300),
                      SizedBox(height: 16),
                      Text(
                        'Arama yapınız',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'En az 3 karakter yazınız',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _displayedUsers.length,
                  itemBuilder: (context, index) {
                    final user = _displayedUsers[index];
                    final userId = 'user:${user['id']}';
                    final isSelected = _selectedRecipients.contains(userId);
                    final role = _normalizeRole(user['role'] ?? 'Kullanıcı');

                    Color avatarColor;
                    if (role == 'Öğrenci') {
                      avatarColor = Colors.blue;
                    } else if (role == 'Öğretmen') {
                      avatarColor = Colors.purple;
                    } else if (role == 'Veli') {
                      avatarColor = Colors.orange;
                    } else {
                      avatarColor = Colors.grey;
                    }

                    return Container(
                      margin: EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.indigo.shade50
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? Colors.indigo.shade300
                              : Colors.grey.shade200,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: avatarColor.withOpacity(0.2),
                          child: Text(
                            (user['name'] ?? 'U')[0].toUpperCase(),
                            style: TextStyle(
                              color: avatarColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          user['name'] ?? 'İsimsiz',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          _buildUserSubtitle(user),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        trailing: AnimatedContainer(
                          duration: Duration(milliseconds: 200),
                          padding: EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.green
                                : Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isSelected ? Icons.check : Icons.add,
                            color: isSelected
                                ? Colors.white
                                : Colors.grey.shade600,
                            size: 18,
                          ),
                        ),
                        onTap: () {
                          if (isSelected) {
                            _removeRecipient(userId);
                          } else {
                            final name = user['name'] ?? 'İsimsiz';
                            final branch = user['branch']?.toString() ?? '';
                            final displayName = branch.isNotEmpty
                                ? '$name ($branch)'
                                : name;
                            _addRecipients(
                              [userId],
                              names: {userId: displayName},
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
  }

  Widget _buildUnitSelection() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Birim Seç', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Expanded(
          child: _units.isEmpty
              ? const Center(child: Text('Birim bulunamadı'))
              : ListView.builder(
                  itemCount: _units.length,
                  itemBuilder: (context, index) {
                    final unit = _units[index];
                    final unitId = 'unit:${unit['id']}';
                    final isSelected = _selectedRecipients.contains(unitId);
                    return ListTile(
                      leading: const Icon(Icons.business),
                      title: Text(unit['name']),
                      subtitle: Text('Tüm ${unit['name']} personeli'),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Colors.green)
                          : const Icon(Icons.add),
                      onTap: () {
                        final displayName = unit['name'] ?? 'Birim';
                        if (isSelected) {
                          _removeRecipient(unitId);
                        } else {
                          _addRecipients(
                            [unitId],
                            names: {unitId: displayName},
                          );
                        }
                      },
                      selected: isSelected,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _performUserSearch(String query) async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 100));

    if (query.isEmpty) {
      setState(() {
        _displayedUsers = List.from(_allUsers);
        _isLoading = false;
      });
      return;
    }

    final lowerQuery = query.toLowerCase();
    final results = _allUsers.where((user) {
      final name = (user['name'] ?? '').toString().toLowerCase();
      final email = (user['email'] ?? '').toString().toLowerCase();
      final role = (user['role'] ?? '').toString().toLowerCase();

      return name.contains(lowerQuery) ||
          email.contains(lowerQuery) ||
          role.contains(lowerQuery);
    }).toList();

    setState(() {
      _displayedUsers = results;
      _isLoading = false;
    });
  }

  Widget _buildSchoolSelection() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: _selectedSchoolType.isEmpty ? null : _selectedSchoolType,
            decoration: const InputDecoration(
              labelText: 'Okul Türü Seç',
              border: OutlineInputBorder(),
            ),
            items: _schoolTypes
                .map(
                  (type) => DropdownMenuItem<String>(
                    value: type['id'] as String,
                    child: Text(type['name'] as String),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedSchoolType = value ?? '';
                _selectedBranchId = '';
                _branches = [];
              });
              if (value != null) _loadBranches(value);
            },
          ),

          if (_selectedSchoolType.isNotEmpty) ...[
            const SizedBox(height: 16),

            if (_loadingBranches)
              LinearProgressIndicator()
            else if (_branches.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _selectedBranchId.isEmpty ? null : _selectedBranchId,
                decoration: const InputDecoration(
                  labelText: 'Şube Seç (İsteğe Bağlı)',
                  border: OutlineInputBorder(),
                  helperText: 'Belirli bir şubeye göndermek için seçiniz',
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text('Tüm Şubeler (Seçim Yok)'),
                  ),
                  ..._branches.map(
                    (b) => DropdownMenuItem(
                      value: b['id'] as String,
                      child: Text(b['name']),
                    ),
                  ),
                ],
                onChanged: (val) {
                  setState(() => _selectedBranchId = val ?? '');
                },
              ),

            const SizedBox(height: 16),
            const Text(
              'Alıcı Türü Seç',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            ..._recipientTypes.map((type) {
              final isBranchSelected = _selectedBranchId.isNotEmpty;
              final prefix = isBranchSelected
                  ? 'branch:$_selectedBranchId'
                  : 'school:$_selectedSchoolType';
              final recipientId = '$prefix:$type';

              String displayName;
              if (isBranchSelected) {
                final branch = _branches.firstWhere(
                  (b) => b['id'] == _selectedBranchId,
                  orElse: () => {'name': 'Şube'},
                );
                displayName = '${branch['name']}-$type';
              } else {
                final schoolTypeName = _getSchoolTypeName(_selectedSchoolType);
                displayName = '$schoolTypeName-$type';
              }

              final subtitle = isBranchSelected
                  ? 'Seçili şubedeki $type'
                  : '${_getSchoolTypeName(_selectedSchoolType)} - tüm $type';

              return CheckboxListTile(
                title: Text(type),
                subtitle: Text(subtitle),
                value: _selectedRecipients.contains(recipientId),
                onChanged: (value) {
                  if (value == true) {
                    _addRecipients(
                      [recipientId],
                      names: {recipientId: displayName},
                    );
                  } else {
                    _removeRecipient(recipientId);
                  }
                },
              );
            }),
          ],
        ],
      ),
    );
  }

  Future<void> _loadBranches(String schoolTypeId) async {
    setState(() => _loadingBranches = true);
    final list = await _announcementService.getBranches(schoolTypeId);
    setState(() {
      _branches = list;
      _loadingBranches = false;
    });
  }

  String _getSchoolTypeName(String id) {
    final schoolType = _schoolTypes.firstWhere(
      (st) => st['id'] == id,
      orElse: () => {'name': id},
    );
    return schoolType['name'];
  }

  Widget _buildGroupSelection() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.indigo),
            SizedBox(height: 12),
            Text(
              'Gruplar yükleniyor...',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.group, color: Colors.teal.shade700, size: 20),
              SizedBox(width: 8),
              Text(
                'Kayıtlı Gruplar',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade700,
                ),
              ),
              Spacer(),
              Text(
                '${_groups.length} grup',
                style: TextStyle(color: Colors.teal.shade600, fontSize: 12),
              ),
              SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _showSaveGroupDialog,
                icon: Icon(Icons.add, size: 16),
                label: Text('Yeni Grup'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),
        Expanded(
          child: _groups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.group_off,
                        size: 64,
                        color: Colors.grey.shade300,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Kayıtlı grup bulunmamaktadır',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _showSaveGroupDialog,
                        icon: Icon(Icons.add),
                        label: Text('İlk Grubu Oluştur'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _groups.length,
                  itemBuilder: (context, index) {
                    final group = _groups[index];
                    final groupId = 'group:${group['id']}';
                    final isSelected = _selectedRecipients.contains(groupId);
                    final recipientCount =
                        (group['recipients'] as List?)?.length ?? 0;

                    return Container(
                      margin: EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.teal.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? Colors.teal.shade300
                              : Colors.grey.shade200,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.group,
                            color: Colors.teal.shade700,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          group['name'] ?? 'İsimsiz Grup',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '$recipientCount alıcı',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: Colors.red.shade400,
                                size: 20,
                              ),
                              tooltip: 'Grubu Sil',
                              onPressed: () => _confirmDeleteGroup(group),
                            ),
                            SizedBox(width: 4),
                            AnimatedContainer(
                              duration: Duration(milliseconds: 200),
                              padding: EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.green
                                    : Colors.grey.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isSelected ? Icons.check : Icons.add,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey.shade600,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          final displayName = group['name'] ?? 'Grup';
                          if (isSelected) {
                            _removeRecipient(groupId);
                          } else {
                            _addRecipients(
                              [groupId],
                              names: {groupId: displayName},
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
  }

  void _confirmDeleteGroup(Map<String, dynamic> group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('Grubu Sil'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bu grubu silmek istediğinizden emin misiniz?'),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.group, color: Colors.teal),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group['name'] ?? 'İsimsiz Grup',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${(group['recipients'] as List?)?.length ?? 0} alıcı',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteGroup(group['id']);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Sil'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGroup(String groupId) async {
    try {
      setState(() => _isLoading = true);

      await _announcementService.deleteRecipientGroup(groupId);

      setState(() {
        _groups.removeWhere((g) => g['id'] == groupId);
        _selectedRecipients.removeWhere((r) => r == 'group:$groupId');
        _recipientNames.remove('group:$groupId');
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Grup başarıyla silindi'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 8),
                Text('Grup silinirken hata oluştu: $e'),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildSelectedRecipientsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.indigo.shade50, Colors.purple.shade50],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.indigo.shade700, size: 20),
              SizedBox(width: 8),
              Text(
                'Seçilen Alıcılar',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade700,
                ),
              ),
              Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_selectedRecipients.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade700,
                  ),
                ),
              ),
              if (_selectedRecipients.isNotEmpty) ...[
                SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _clearAllRecipients,
                  icon: Icon(
                    Icons.clear_all,
                    size: 16,
                    color: Colors.red.shade400,
                  ),
                  label: Text(
                    'Temizle',
                    style: TextStyle(color: Colors.red.shade400),
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: 16),
        Expanded(
          child: _selectedRecipients.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 64,
                        color: Colors.grey.shade300,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Henüz alıcı seçilmedi',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Yukarıdaki kategorilerden alıcı ekleyin',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _selectedRecipients.length,
                  itemBuilder: (context, index) {
                    final recipientId = _selectedRecipients[index];
                    final displayName =
                        _recipientNames[recipientId] ?? recipientId;

                    Color cardColor;
                    Color textColor;
                    IconData icon;

                    if (recipientId.startsWith('user:')) {
                      cardColor = Colors.blue.shade50;
                      textColor = Colors.blue.shade700;
                      icon = Icons.person;
                    } else if (recipientId.startsWith('branch:')) {
                      cardColor = Colors.green.shade50;
                      textColor = Colors.green.shade700;
                      icon = Icons.class_;
                    } else if (recipientId.startsWith('class:')) {
                      cardColor = Colors.orange.shade50;
                      textColor = Colors.orange.shade700;
                      icon = Icons.school;
                    } else if (recipientId.startsWith('school:')) {
                      cardColor = Colors.purple.shade50;
                      textColor = Colors.purple.shade700;
                      icon = Icons.account_balance;
                    } else if (recipientId.startsWith('unit:')) {
                      cardColor = Colors.teal.shade50;
                      textColor = Colors.teal.shade700;
                      icon = Icons.business;
                    } else {
                      cardColor = Colors.grey.shade100;
                      textColor = Colors.grey.shade700;
                      icon = Icons.group;
                    }

                    return Container(
                      margin: EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: textColor.withOpacity(0.3)),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: textColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icon, color: textColor, size: 20),
                        ),
                        title: Text(
                          displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        subtitle: Text(
                          _getRecipientTypeLabel(recipientId),
                          style: TextStyle(
                            fontSize: 11,
                            color: textColor.withOpacity(0.7),
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.remove_circle,
                            color: Colors.red.shade400,
                          ),
                          onPressed: () => _removeRecipient(recipientId),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _getRecipientTypeLabel(String id) {
    if (id.startsWith('user:')) return 'Kişi';
    if (id.startsWith('branch:')) return 'Şube';
    if (id.startsWith('class:')) return 'Sınıf Seviyesi';
    if (id.startsWith('school:')) return 'Okul/Kurum';
    if (id.startsWith('unit:')) return 'Birim';
    if (id.startsWith('group:')) return 'Grup';
    return 'Diğer';
  }
}
