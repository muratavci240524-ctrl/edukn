import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddPreRegistrationScreen extends StatelessWidget {
  final String? institutionId;
  final String? selectedTermId;
  final List<Map<String, dynamic>> schoolTypes;
  final Map<String, dynamic>? preRegistration;
  final String? preRegistrationId;

  const AddPreRegistrationScreen({
    Key? key,
    required this.institutionId,
    required this.selectedTermId,
    required this.schoolTypes,
    this.preRegistration,
    this.preRegistrationId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(preRegistrationId != null ? 'Görüşmeyi Düzenle' : 'Yeni Ön Kayıt / Görüşme'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: PreRegistrationFormWidget(
        institutionId: institutionId,
        selectedTermId: selectedTermId,
        schoolTypes: schoolTypes,
        preRegistration: preRegistration,
        preRegistrationId: preRegistrationId,
        onCancel: () => Navigator.pop(context),
        onSave: () => Navigator.pop(context, true),
      ),
    );
  }
}

class PreRegistrationFormWidget extends StatefulWidget {
  final String? institutionId;
  final String? selectedTermId;
  final List<Map<String, dynamic>> schoolTypes;
  final Map<String, dynamic>? preRegistration;
  final String? preRegistrationId;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const PreRegistrationFormWidget({
    Key? key,
    required this.institutionId,
    required this.selectedTermId,
    required this.schoolTypes,
    this.preRegistration,
    this.preRegistrationId,
    required this.onCancel,
    required this.onSave,
  }) : super(key: key);

  @override
  _PreRegistrationFormWidgetState createState() => _PreRegistrationFormWidgetState();
}

class _PreRegistrationFormWidgetState extends State<PreRegistrationFormWidget> {
  final _formKey = GlobalKey<FormState>();
  
  // Guardian Info
  final TextEditingController _guardian1NameController = TextEditingController();
  final TextEditingController _guardian2NameController = TextEditingController();
  String _guardian1Kinship = 'Anne';
  String? _guardian2Kinship;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  
  // Interviewer Info
  List<Map<String, dynamic>> _adminUsers = [];
  List<String> _selectedInterviewers = [];
  
  // Address Info
  String _selectedCity = 'ANKARA';
  String? _selectedDistrict;
  final TextEditingController _neighborhoodController = TextEditingController();
  
  // Students List
  final List<Map<String, dynamic>> _students = [];
  List<Map<String, String>> _knownSchools = [];

  // Static Data
  final List<String> _kinships = ['Anne', 'Baba', 'Amca', 'Dayı', 'Babaanne', 'Anneanne', 'Dede', 'Vasi', 'Diğer'];
  final List<String> _ankaraDistricts = [
    'Akyurt', 'Altındağ', 'Ayaş', 'Balâ', 'Beypazarı', 'Çamlıdere', 'Çankaya', 
    'Çubuk', 'Elmadağ', 'Etimesgut', 'Evren', 'Gölbaşı', 'Güdül', 'Haymana', 
    'Kahramankazan', 'Kalecik', 'Keçiören', 'Kızılcahamam', 'Mamak', 'Nallıhan', 
    'Polatlı', 'Pursaklar', 'Sincan', 'Şereflikoçhisar', 'Yenimahalle'
  ].sorted((a, b) => a.compareTo(b));

  @override
  void initState() {
    super.initState();
    if (widget.preRegistrationId != null && widget.preRegistration != null) {
      _loadExistingData();
    } else {
      _addStudent();
    }
    _loadAdminUsers();
    _loadKnownSchools();
  }

  Future<void> _loadKnownSchools() async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('institutions').doc(widget.institutionId).collection('schools')
          .get();
      setState(() {
        _knownSchools = query.docs.map((doc) => {
          'id': doc.id,
          'name': doc['name'] as String
        }).toList();
      });
    } catch (e) {
      print('Okul listesi yüklenemedi: $e');
    }
  }

  void _loadExistingData() {
    final reg = widget.preRegistration!;
    _guardian1NameController.text = reg['guardian1Name'] ?? '';
    _guardian2NameController.text = reg['guardian2Name'] ?? '';
    _guardian1Kinship = reg['guardian1Kinship'] ?? 'Anne';
    _guardian2Kinship = reg['guardian2Kinship'];
    _phoneController.text = reg['phone'] ?? '';
    _emailController.text = reg['email'] ?? '';
    
    _selectedCity = reg['address']?['city'] ?? 'ANKARA';
    _selectedDistrict = reg['address']?['district'];
    _neighborhoodController.text = reg['address']?['neighborhood'] ?? '';
    
    if (reg['responsibleId'] != null) {
       _selectedInterviewers = [reg['responsibleId']];
    }

    _students.add({
      'fullName': TextEditingController(text: reg['fullName']),
      'previousSchool': TextEditingController(text: reg['previousSchool']),
      'classLevel': reg['classLevel'],
      'schoolTypeId': reg['schoolTypeId'],
      'gender': reg['gender'] ?? 'Erkek',
    });
  }

  Future<void> _loadAdminUsers() async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();
      
      final admins = query.docs.map((doc) => {'id': doc.id, ...doc.data()}).where((u) {
        final role = u['role']?.toString().toLowerCase();
        return ['genel_mudur', 'mudur', 'mudur_yardimcisi', 'admin', 'hr', 'muhasebe', 'satin_alma', 'depo', 'destek_hizmetleri'].contains(role);
      }).toList();
      
      setState(() => _adminUsers = admins);
    } catch (e) {
      print('Error loading admin users: $e');
    }
  }

  String _formatLevelLabel(String level) {
    if (RegExp(r'^\d+$').hasMatch(level)) {
      return '$level. Sınıf';
    }
    return level;
  }

  List<String> _getAvailableClassLevels() {
    final List<String> available = [];
    
    for (var type in widget.schoolTypes) {
      final grades = type['activeGrades'] as List<dynamic>?;
      if (grades != null) {
        for (var g in grades) {
          final levelStr = g.toString();
          if (!available.contains(levelStr)) {
            available.add(levelStr);
          }
        }
      }
    }
    
    // Custom sort order based on school hierarchy
    final sortOrder = [
      '3 Yaş', '4 Yaş', '5 Yaş',
      '1', '2', '3', '4',
      '5', '6', '7', '8',
      '9', '10', '11', '12', 'Mezun'
    ];
    
    available.sort((a, b) {
      int indexA = sortOrder.indexOf(a);
      int indexB = sortOrder.indexOf(b);
      
      // If found in custom order, use that
      if (indexA != -1 && indexB != -1) return indexA.compareTo(indexB);
      if (indexA != -1) return -1;
      if (indexB != -1) return 1;
      
      // Fallback to natural sort
      final aInt = int.tryParse(a.replaceAll(RegExp(r'\D'), ''));
      final bInt = int.tryParse(b.replaceAll(RegExp(r'\D'), ''));
      if (aInt != null && bInt != null) return aInt.compareTo(bInt);
      return a.compareTo(b);
    });
    
    return available;
  }

  void _onClassLevelChanged(Map<String, dynamic> student, String? value) {
    setState(() {
      student['classLevel'] = value;
      
      // Auto select school type that contains this grade
      if (value != null) {
        final matchedType = widget.schoolTypes.firstWhere(
          (t) {
            final grades = t['activeGrades'] as List<dynamic>?;
            return grades != null && grades.any((g) => g.toString() == value);
          },
          orElse: () => {},
        );
        if (matchedType.isNotEmpty) {
          student['schoolTypeId'] = matchedType['id'];
        }
      }
    });
  }

  void _addStudent() {
    setState(() {
      final availableLevels = _getAvailableClassLevels();
      final defaultLevel = availableLevels.isNotEmpty ? availableLevels[0] : '1';
      
      final student = {
        'fullName': TextEditingController(),
        'previousSchool': TextEditingController(),
        'classLevel': defaultLevel,
        'gender': 'Erkek',
        'schoolTypeId': widget.schoolTypes.isNotEmpty ? widget.schoolTypes[0]['id'] : null,
      };
      
      // Initial auto-select
      _onClassLevelChanged(student, defaultLevel);
      _students.add(student);
    });
  }

  void _removeStudent(int index) {
    if (_students.length > 1) {
      setState(() {
        _students.removeAt(index);
      });
    }
  }

  Future<void> _savePreRegistration() async {
    if (!_formKey.currentState!.validate()) return;
    if (_students.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('En az bir öğrenci eklemelisiniz.')));
       return;
    }

    try {
      final batch = FirebaseFirestore.instance.batch();
      
      if (widget.preRegistrationId != null) {
        // Düzenleme durumu
        final student = _students[0];
        final docRef = FirebaseFirestore.instance.collection('preRegistrations').doc(widget.preRegistrationId);
        batch.update(docRef, {
          'fullName': (student['fullName'] as TextEditingController).text.toUpperCase(),
          'previousSchool': _toTurkishUpper((student['previousSchool'] as TextEditingController).text),
          'classLevel': student['classLevel'],
          'gender': student['gender'],
          'schoolTypeId': student['schoolTypeId'],
          'guardian1Name': _guardian1NameController.text.toUpperCase(),
          'guardian1Kinship': _guardian1Kinship,
          'guardian2Name': _guardian2NameController.text.toUpperCase(),
          'guardian2Kinship': _guardian2Kinship,
          'phone': _phoneController.text,
          'email': _emailController.text.toLowerCase(),
          'responsibleId': _selectedInterviewers.isNotEmpty ? _selectedInterviewers.first : null,
          'responsibleName': _selectedInterviewers.isNotEmpty 
              ? _adminUsers.firstWhere((u) => u['id'] == _selectedInterviewers.first, orElse: () => {'fullName': ''})['fullName'] 
              : null,
          'address': {
            'city': _selectedCity,
            'district': _selectedDistrict,
            'neighborhood': _neighborhoodController.text.toUpperCase(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _checkAndSaveSchool((student['previousSchool'] as TextEditingController).text);
      } else {
        // Yeni kayıt durumu
        final String commonGroupId = DateTime.now().millisecondsSinceEpoch.toString();
        for (var student in _students) {
        final docRef = FirebaseFirestore.instance.collection('preRegistrations').doc();
          batch.set(docRef, {
            'institutionId': widget.institutionId,
            'termId': widget.selectedTermId,
            'groupId': commonGroupId,
            'fullName': (student['fullName'] as TextEditingController).text.toUpperCase(),
            'previousSchool': _toTurkishUpper((student['previousSchool'] as TextEditingController).text),
            'classLevel': student['classLevel'],
            'gender': student['gender'],
            'schoolTypeId': student['schoolTypeId'],
            'guardian1Name': _guardian1NameController.text.toUpperCase(),
            'guardian1Kinship': _guardian1Kinship,
            'guardian2Name': _guardian2NameController.text.toUpperCase(),
            'guardian2Kinship': _guardian2Kinship,
            'phone': _phoneController.text,
            'email': _emailController.text.toLowerCase(),
            'responsibleId': _selectedInterviewers.isNotEmpty ? _selectedInterviewers.first : null,
            'responsibleName': _selectedInterviewers.isNotEmpty 
                ? _adminUsers.firstWhere((u) => u['id'] == _selectedInterviewers.first, orElse: () => {'fullName': ''})['fullName'] 
                : null,
            'interviewers': _selectedInterviewers,
            'city': _selectedCity,
            'district': _selectedDistrict,
            'neighborhood': _neighborhoodController.text.toUpperCase(),
            'status': 'pending',
            'isConverted': false,
            'meetingDate': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
            'priceOffer': {
              'educationFee': 0.0,
              'foodFee': 0.0,
              'stationeryFee': 0.0,
              'serviceFee': 0.0,
              'otherFee': 0.0,
              'discount': 0.0,
              'total': 0.0,
            }
          });
          _checkAndSaveSchool((student['previousSchool'] as TextEditingController).text);
      }
    }

      await batch.commit();
      widget.onSave();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  String _toTurkishUpper(String? val) {
    if (val == null || val.isEmpty) return '';
    return val
        .replaceAll('i', 'İ')
        .replaceAll('ı', 'I')
        .replaceAll('ç', 'Ç')
        .replaceAll('ş', 'Ş')
        .replaceAll('ğ', 'Ğ')
        .replaceAll('ü', 'Ü')
        .replaceAll('ö', 'Ö')
        .toUpperCase();
  }

  Future<void> _checkAndSaveSchool(String schoolName) async {
    final name = _toTurkishUpper(schoolName);
    if (name.isEmpty) return;

    if (!_knownSchools.any((k) => k['name']!.toLowerCase() == name.toLowerCase())) {
      try {
        final docRef = await FirebaseFirestore.instance
            .collection('institutions').doc(widget.institutionId).collection('schools')
            .add({'name': name, 'createdAt': FieldValue.serverTimestamp()});
        setState(() => _knownSchools.add({'id': docRef.id, 'name': name}));
      } catch (e) {
        print('Okul kaydedilemedi: $e');
      }
    }
  }

  Future<void> _deleteSchool(String id) async {
    try {
      await FirebaseFirestore.instance
          .collection('institutions').doc(widget.institutionId).collection('schools')
          .doc(id).delete();
      setState(() {
        _knownSchools.removeWhere((s) => s['id'] == id);
      });
    } catch (e) {
      print('Okul silinemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader('GÖRÜŞME YÖNETİMİ', Icons.admin_panel_settings_outlined),
                  _buildManagementSection(),
                  const SizedBox(height: 24),
                  _buildHeader('ÖĞRENCİ BİLGİLERİ', Icons.people_outline),
                  ..._students.asMap().entries.map((entry) => _buildStudentCard(entry.key, entry.value)).toList(),
                  const SizedBox(height: 8),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: _addStudent,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Başka Bir Öğrenci Ekle (Kardeş)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.indigo,
                        side: const BorderSide(color: Colors.indigo),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildHeader('VELİ BİLGİLERİ', Icons.assignment_ind_outlined),
                  _buildGuardianSection(),
                  const SizedBox(height: 24),
                  _buildHeader('ADRES BİLGİLERİ', Icons.location_on_outlined),
                  _buildAddressSection(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white, 
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))],
          ),
          child: SafeArea(
            child: Row(
              children: [
                if (MediaQuery.of(context).size.width > 900)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onCancel,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('İPTAL'),
                    ),
                  ),
                if (MediaQuery.of(context).size.width > 900) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _savePreRegistration,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('ÖN KAYDI TAMAMLA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.indigo),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo, letterSpacing: 1.2)),
        ],
      ),
    );
  }

  Widget _buildStudentCard(int index, Map<String, dynamic> student) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.indigo.shade50,
                  child: Text('${index + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo)),
                ),
                const SizedBox(width: 8),
                const Text('Öğrenci Bilgileri', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_students.length > 1)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                    onPressed: () => _removeStudent(index),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const Divider(height: 24),
            TextFormField(
              controller: student['fullName'] as TextEditingController,
              decoration: _inputDecoration('Öğrenci Ad Soyad *', Icons.person_outline),
              validator: (v) => v!.isEmpty ? 'Gerekli' : null,
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 16),
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return const Iterable<String>.empty();
                }
                return _knownSchools
                    .where((k) => k['name']!.toLowerCase().contains(textEditingValue.text.toLowerCase()))
                    .map((k) => k['name']!);
              },
              onSelected: (String selection) {
                (student['previousSchool'] as TextEditingController).text = selection;
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 12,
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 400,
                      constraints: const BoxConstraints(maxHeight: 300),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade100, width: 2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: options.length,
                        separatorBuilder: (context, i) => Divider(height: 1, color: Colors.grey.shade100),
                        itemBuilder: (context, i) {
                          final String opt = options.elementAt(i);
                          final schoolMap = _knownSchools.firstWhere((s) => s['name'] == opt, orElse: () => <String, String>{});
                          
                          return ListTile(
                            onTap: () => onSelected(opt),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            contentPadding: const EdgeInsets.only(left: 20, right: 8),
                            title: Text(opt, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.indigo, fontSize: 13)),
                            trailing: schoolMap.isNotEmpty ? IconButton(
                              icon: const Icon(Icons.close, size: 18, color: Colors.red),
                              tooltip: 'Veritabanından kaldır',
                              onPressed: () => _deleteSchool(schoolMap['id']!),
                            ) : const Icon(Icons.north_west, size: 14, color: Colors.grey),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                if (controller.text.isEmpty && (student['previousSchool'] as TextEditingController).text.isNotEmpty) {
                  controller.text = (student['previousSchool'] as TextEditingController).text;
                }
                
                controller.addListener(() {
                  (student['previousSchool'] as TextEditingController).text = controller.text;
                });

                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: _inputDecoration('Geldiği / Okuduğu Okul', Icons.school_outlined),
                  textCapitalization: TextCapitalization.words,
                  onFieldSubmitted: (v) => onFieldSubmitted(),
                );
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: _inputDecoration('Cinsiyet', Icons.wc_outlined),
              value: student['gender'],
              items: ['Erkek', 'Kız'].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
              onChanged: (v) => setState(() => student['gender'] = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              isExpanded: true,
              decoration: _inputDecoration('Sınıf Seviyesi', Icons.grade_outlined),
              value: student['classLevel'],
              items: _getAvailableClassLevels()
                  .map((l) => DropdownMenuItem(value: l, child: Text(_formatLevelLabel(l)))).toList(),
              onChanged: (v) => _onClassLevelChanged(student, v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              isExpanded: true,
              decoration: _inputDecoration('Okul Türü', Icons.school_outlined),
              value: student['schoolTypeId'],
              items: widget.schoolTypes.map((t) => DropdownMenuItem(value: t['id'] as String, child: Text(t['schoolTypeName'] ?? t['typeName'] ?? '', overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => student['schoolTypeId'] = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuardianSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextFormField(
              controller: _guardian1NameController,
              decoration: _inputDecoration('Veli 1 Ad Soyad *', Icons.person),
              validator: (v) => v!.isEmpty ? 'Gerekli' : null,
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: _inputDecoration('Yakınlık Derecesi', Icons.people_outline),
              value: _guardian1Kinship,
              items: _kinships.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
              onChanged: (v) => setState(() => _guardian1Kinship = v!),
            ),
            const Divider(height: 32),
            TextFormField(
              controller: _guardian2NameController,
              decoration: _inputDecoration('Veli 2 Ad Soyad (İsteğe Bağlı)', Icons.person_outline),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: _inputDecoration('Yakınlık Derecesi', Icons.people_outline),
              value: _guardian2Kinship,
              items: _kinships.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
              onChanged: (v) => setState(() => _guardian2Kinship = v),
              hint: const Text('Seçiniz'),
            ),
            const SizedBox(height: 12),
            const Divider(height: 32),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _phoneController,
                    decoration: _inputDecoration('İletişim No *', Icons.phone_android),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [PhoneTextFormatter()],
                    validator: (v) => v!.isEmpty ? 'Gerekli' : v.replaceAll(' ', '').length < 11 ? 'Eksik numara' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _emailController,
                    decoration: _inputDecoration('E-posta', Icons.email_outlined),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManagementSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: _inputDecoration('Görüşmeyi Yapan Yönetici *', Icons.person_search_outlined),
          value: _selectedInterviewers.isNotEmpty ? _selectedInterviewers.first : null,
          items: _adminUsers.map((u) => DropdownMenuItem(value: u['id'] as String, child: Text(u['fullName'] ?? ''))).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() => _selectedInterviewers = [v]);
            }
          },
          validator: (v) => v == null ? 'Gerekli' : null,
        ),
      ),
    );
  }

  Widget _buildAddressSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: _inputDecoration('İl', Icons.map_outlined),
                    value: _selectedCity,
                    items: const [DropdownMenuItem(value: 'ANKARA', child: Text('ANKARA'))],
                    onChanged: (v) => setState(() => _selectedCity = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: _inputDecoration('İlçe', Icons.location_city_outlined),
                    value: _selectedDistrict,
                    items: _ankaraDistricts.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                    onChanged: (v) => setState(() => _selectedDistrict = v),
                    validator: (v) => v == null ? 'Gerekli' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _neighborhoodController,
              decoration: _inputDecoration('Mahalle / Köy', Icons.home_work_outlined),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }
}

extension ListSorting on List<String> {
  List<String> sorted(int Function(String a, String b) compare) {
    final copy = List<String>.from(this);
    copy.sort(compare);
    return copy;
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(text: newValue.text.toUpperCase(), selection: newValue.selection);
  }
}

class PhoneTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.length > 11) text = text.substring(0, 11);
    String res = "";
    for (var i = 0; i < text.length; i++) {
      if (i == 4 || i == 7 || i == 9) res += " ";
      res += text[i];
    }
    return TextEditingValue(text: res, selection: TextSelection.collapsed(offset: res.length));
  }
}

