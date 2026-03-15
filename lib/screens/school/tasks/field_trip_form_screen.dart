import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../../models/field_trip_model.dart';
import '../../../../services/field_trip_service.dart';

class FieldTripFormScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;

  const FieldTripFormScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
  }) : super(key: key);

  @override
  State<FieldTripFormScreen> createState() => _FieldTripFormScreenState();
}

class _FieldTripFormScreenState extends State<FieldTripFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = FieldTripService();

  int _currentStep = 1;
  final int _totalSteps = 3;

  // Step 1: Trip Details
  final _nameController = TextEditingController();
  final _purposeController = TextEditingController();
  DateTime? _departureDate;
  TimeOfDay? _departureTime;
  DateTime? _returnDate;
  TimeOfDay? _returnTime;

  // Step 2: Target Selection
  Set<String> _selectedClassLevels = {};
  List<Map<String, dynamic>> _availableBranches = [];
  List<String> _selectedBranchIds = [];
  bool _isLoadingBranches = false;

  List<Map<String, dynamic>> _availableStudents =
      []; // Students from selected branches
  List<String> _selectedStudentIds = []; // Final list of selected student IDs
  Map<String, Map<String, dynamic>> _selectedStudentMap =
      {}; // ID -> Data for list display
  bool _isLoadingStudents = false;
  bool _selectAllStudents = true;

  // Step 3: Survey & Payment
  bool _createSurvey = true;
  DateTime? _surveyPublishDate;
  TimeOfDay? _surveyPublishTime;
  bool _isPaid = false;
  final _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBranches();

    _departureDate = DateTime.now().add(const Duration(days: 7));
    _departureTime = const TimeOfDay(hour: 09, minute: 00);
    _returnDate = DateTime.now().add(const Duration(days: 7));
    _returnTime = const TimeOfDay(hour: 16, minute: 00);

    _surveyPublishDate = DateTime.now();
    _surveyPublishTime = TimeOfDay.now();
  }

  Future<void> _loadBranches() async {
    setState(() => _isLoadingBranches = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .get();

      setState(() {
        _availableBranches = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'name': (data['className'] ?? data['name'] ?? 'İsimsiz').toString(),
            'classLevel': (data['classLevel'] ?? '0').toString(),
          };
        }).toList();
        _availableBranches.sort((a, b) => a['name'].compareTo(b['name']));
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      setState(() => _isLoadingBranches = false);
    }
  }

  // Load students based on selected branches
  Future<void> _loadStudentsFromBranches() async {
    if (_selectedBranchIds.isEmpty) {
      setState(() {
        _availableStudents = [];
        // Do NOT clear _selectedStudentIds as they might have been added manually
      });
      return;
    }

    setState(() => _isLoadingStudents = true);
    try {
      List<Map<String, dynamic>> studentsFound = [];

      // To avoid too many queries, we accept we might iterate
      // But firestore "IN" limit is 10.
      for (var branchId in _selectedBranchIds) {
        final snapshot = await FirebaseFirestore.instance
            .collection('students')
            .where('classId', isEqualTo: branchId)
            .where('isActive', isEqualTo: true)
            .get();

        for (var doc in snapshot.docs) {
          final data = doc.data();
          final sData = {
            'id': doc.id,
            'fullName':
                data['fullName'] ?? '${data['name']} ${data['surname']}',
            'classId': branchId,
            'className': data['className'] ?? '',
          };
          studentsFound.add(sData);

          // Add to local map if selected
          if (_selectedStudentIds.contains(doc.id)) {
            _selectedStudentMap[doc.id] = sData;
          }
        }
      }

      setState(() {
        _availableStudents = studentsFound;

        // If "Select All" is active, auto-select new students from these branches
        if (_selectAllStudents) {
          for (var s in studentsFound) {
            if (!_selectedStudentIds.contains(s['id'])) {
              _selectedStudentIds.add(s['id']);
              _selectedStudentMap[s['id']] = s;
            }
          }
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      setState(() => _isLoadingStudents = false);
    }
  }

  Future<void> _searchAndAddStudent(String query) async {
    if (query.length < 3) return;

    // Simple search by name (manual implementation for firestore prefix search)
    final strFrontCode = query.substring(0, query.length - 1);
    final strEndCode = query.substring(query.length - 1, query.length);
    final limit =
        strFrontCode + String.fromCharCode(strEndCode.codeUnitAt(0) + 1);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('fullName', isGreaterThanOrEqualTo: query)
          .where('fullName', isLessThan: limit)
          .limit(5)
          .get();

      if (snapshot.docs.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Öğrenci bulunamadı')));
        return;
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Öğrenci Seç'),
          content: Container(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: snapshot.docs.length,
              itemBuilder: (context, index) {
                final doc = snapshot.docs[index];
                final data = doc.data();
                final name = data['fullName'] ?? '';
                return ListTile(
                  title: Text(name),
                  subtitle: Text(data['className'] ?? ''),
                  trailing: const Icon(Icons.add),
                  onTap: () {
                    setState(() {
                      if (!_selectedStudentIds.contains(doc.id)) {
                        _selectedStudentIds.add(doc.id);
                        _selectedStudentMap[doc.id] = {
                          'id': doc.id,
                          'fullName': name,
                          'className': data['className'],
                        };
                      }
                    });
                    Navigator.pop(context);
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('$name eklendi')));
                  },
                );
              },
            ),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Arama hatası: $e')));
    }
  }

  // --- UI COMPONENTS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: Colors.black87),
        title: Text(
          'Gezi Planla (${_currentStep}/$_totalSteps)',
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),

        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: _currentStep / _totalSteps,
            backgroundColor: Colors.grey[100],
            valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(key: _formKey, child: _buildCurrentStep()),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2();
      case 3:
        return _buildStep3();
      default:
        return Container();
    }
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Gezi Detayları',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.indigo,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Gezinin temel bilgilerini giriniz.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),

        _buildLabel('Gezi Adı'),
        TextFormField(
          controller: _nameController,
          decoration: _inputDecoration('Örn: Anıtkabir Gezisi'),
          validator: (v) => v!.isEmpty ? 'Gerekli' : null,
        ),
        const SizedBox(height: 24),

        _buildLabel('Amaç / Açıklama'),
        TextFormField(
          controller: _purposeController,
          maxLines: 3,
          decoration: _inputDecoration('Gezinin amacı nedir?'),
          validator: (v) => v!.isEmpty ? 'Gerekli' : null,
        ),
        const SizedBox(height: 24),

        Row(
          children: [
            Expanded(
              child: _buildDateTimePicker(
                'Hareket',
                _departureDate,
                _departureTime,
                (d, t) {
                  setState(() {
                    _departureDate = d;
                    _departureTime = t;
                  });
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDateTimePicker('Dönüş', _returnDate, _returnTime, (
                d,
                t,
              ) {
                setState(() {
                  _returnDate = d;
                  _returnTime = t;
                });
              }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep2() {
    final levels =
        _availableBranches
            .map((b) => b['classLevel'] as String)
            .toSet()
            .toList()
          ..sort(
            (a, b) => int.tryParse(a)?.compareTo(int.tryParse(b) ?? 0) ?? 0,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Katılımcı Seçimi',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.indigo,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Kimler katılacak? Sınıf/Şube filtreleyebilir veya doğrudan öğrenci arayabilirsiniz.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),

        // 1. CLASS LEVEL MULTI-SELECT
        _buildLabel('Sınıf Seviyeleri'),
        if (_isLoadingBranches)
          const LinearProgressIndicator()
        else
          Wrap(
            spacing: 8,
            children: levels.map((l) {
              final isSelected = _selectedClassLevels.contains(l);
              return FilterChip(
                label: Text('$l. Sınıflar'),
                selected: isSelected,
                selectedColor: Colors.indigo.shade100,
                checkmarkColor: Colors.indigo,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.indigo.shade900 : Colors.black87,
                ),
                onSelected: (selected) {
                  setState(() {
                    if (selected)
                      _selectedClassLevels.add(l);
                    else
                      _selectedClassLevels.remove(l);
                  });
                },
              );
            }).toList(),
          ),

        const SizedBox(height: 24),

        // 2. BRANCH MULTI-SELECT
        if (_selectedClassLevels.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildLabel('Şubeler'),
              TextButton(
                onPressed: () {
                  final visibleBranches = _availableBranches
                      .where(
                        (b) => _selectedClassLevels.contains(b['classLevel']),
                      )
                      .map((b) => b['id'] as String)
                      .toList();
                  setState(() => _selectedBranchIds = visibleBranches);
                  _loadStudentsFromBranches();
                },
                child: const Text('Tümünü Seç'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: _availableBranches
                .where((b) => _selectedClassLevels.contains(b['classLevel']))
                .map((b) {
                  final isSelected = _selectedBranchIds.contains(b['id']);
                  return FilterChip(
                    label: Text(b['name']),
                    selected: isSelected,
                    selectedColor: Colors.blue.shade100,
                    checkmarkColor: Colors.blue.shade900,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.blue.shade900 : Colors.black,
                    ),
                    onSelected: (selected) {
                      setState(() {
                        if (selected)
                          _selectedBranchIds.add(b['id']);
                        else
                          _selectedBranchIds.remove(b['id']);
                      });
                      _loadStudentsFromBranches();
                    },
                  );
                })
                .toList(),
          ),
        ],

        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),

        // 3. STUDENT LIST & SEARCH
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildLabel('Seçili Öğrenciler: ${_selectedStudentIds.length}'),

            // "Add Student by Name" Button (Manual Search)
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text('Öğrenci Ara'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (c) {
                    String q = '';
                    return AlertDialog(
                      title: const Text('Öğrenci Ara'),
                      content: TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Ad Soyad (En az 3 harf)...',
                        ),
                        onChanged: (v) => q = v,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('İptal'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(c);
                            _searchAndAddStudent(q);
                          },
                          child: const Text('Ara Ekle'),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),

        // Batch Actions
        if (_availableStudents.isNotEmpty)
          Row(
            children: [
              TextButton(
                onPressed: () {
                  setState(() {
                    for (var s in _availableStudents) {
                      if (!_selectedStudentIds.contains(s['id'])) {
                        _selectedStudentIds.add(s['id']);
                        _selectedStudentMap[s['id']] = s;
                      }
                    }
                  });
                },
                child: const Text('Listedekileri Ekle'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    for (var s in _availableStudents) {
                      _selectedStudentIds.remove(s['id']);
                      _selectedStudentMap.remove(s['id']);
                    }
                  });
                },
                child: const Text(
                  'Listedekileri Çıkar',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),

        // Display List
        if (_isLoadingStudents)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_availableStudents.isNotEmpty) ...[
          Container(
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[200]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.separated(
              itemCount: _availableStudents.length,
              separatorBuilder: (c, i) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final student = _availableStudents[index];
                final isSelected = _selectedStudentIds.contains(student['id']);
                return CheckboxListTile(
                  title: Text(student['fullName']),
                  subtitle: Text(student['className']),
                  value: isSelected,
                  activeColor: Colors.indigo,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedStudentIds.add(student['id']);
                        _selectedStudentMap[student['id']] = student;
                      } else {
                        _selectedStudentIds.remove(student['id']);
                        _selectedStudentMap.remove(student['id']);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ],

        // Show count of manually added students that are NOT in the current branch list
        Builder(
          builder: (context) {
            final visibleIds = _availableStudents.map((s) => s['id']).toSet();
            // Manually added students are ones in _selectedStudentIds but not in visibleIds
            final manuallyAddedCount = _selectedStudentIds
                .where((id) => !visibleIds.contains(id))
                .length;

            if (manuallyAddedCount > 0) {
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.yellow.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Listedekiler dışında $manuallyAddedCount öğrenci daha seçili.',
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ],
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Son Ayarlar',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.indigo,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Anket ve ödeme detaylarını belirleyin.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.purple.shade100),
          ),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text(
                  'Katılım Anketi',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'Velilere/Öğrencilere onay anketi gönderilsin mi?',
                ),
                value: _createSurvey,
                activeColor: Colors.purple,
                onChanged: (v) => setState(() => _createSurvey = v),
              ),
              if (_createSurvey) ...[
                const Divider(),
                const SizedBox(height: 8),
                _buildDateTimePicker(
                  'Anket Yayınlanma Zamanı',
                  _surveyPublishDate,
                  _surveyPublishTime,
                  (d, t) {
                    setState(() {
                      _surveyPublishDate = d;
                      _surveyPublishTime = t;
                    });
                  },
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.shade100),
          ),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text(
                  'Gezi Ücreti',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('Bu gezi için ücret toplanacak mı?'),
                value: _isPaid,
                activeColor: Colors.orange,
                onChanged: (v) => setState(() => _isPaid = v),
              ),
              if (_isPaid) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration(
                    'Tutar (TL)',
                    icon: Icons.attach_money,
                  ),
                  validator: (v) =>
                      _isPaid && v!.isEmpty ? 'Tutar gerekli' : null,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 1)
            TextButton(
              onPressed: () => setState(() => _currentStep--),
              child: const Text('Geri', style: TextStyle(color: Colors.grey)),
            ),
          const Spacer(),
          ElevatedButton(
            onPressed: () {
              if (_currentStep < _totalSteps) {
                if (_currentStep == 1 && !_formKey.currentState!.validate())
                  return;
                setState(() => _currentStep++);
              } else {
                _submit();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              _currentStep == _totalSteps ? 'Planı Oluştur' : 'Devam Et',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      fillColor: Colors.grey[50],
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      prefixIcon: icon != null ? Icon(icon, color: Colors.grey) : null,
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildDateTimePicker(
    String label,
    DateTime? date,
    TimeOfDay? time,
    Function(DateTime, TimeOfDay) onChange,
  ) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (d != null) {
          final t = await showTimePicker(
            context: context,
            initialTime: time ?? TimeOfDay.now(),
          );
          if (t != null) onChange(d, t);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.indigo),
                const SizedBox(width: 8),
                Text(
                  '${DateFormat('dd.MM').format(date!)} ${time!.format(context)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_selectedStudentIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Lütfen öğrenci seçiniz')));
      return;
    }

    final departure = DateTime(
      _departureDate!.year,
      _departureDate!.month,
      _departureDate!.day,
      _departureTime!.hour,
      _departureTime!.minute,
    );
    final ret = DateTime(
      _returnDate!.year,
      _returnDate!.month,
      _returnDate!.day,
      _returnTime!.hour,
      _returnTime!.minute,
    );
    final surveyPublish = _createSurvey
        ? DateTime(
            _surveyPublishDate!.year,
            _surveyPublishDate!.month,
            _surveyPublishDate!.day,
            _surveyPublishTime!.hour,
            _surveyPublishTime!.minute,
          )
        : null;

    final trip = FieldTrip(
      id: '',
      institutionId: widget.institutionId,
      schoolTypeId: widget.schoolTypeId,
      schoolTypeName: widget.schoolTypeName,
      name: _nameController.text,
      purpose: _purposeController.text,
      departureTime: departure,
      returnTime: ret,
      classLevel: _selectedClassLevels.join(','), // Join selected levels
      targetBranchIds: _selectedBranchIds,
      targetStudentIds: _selectedStudentIds,
      totalStudents: _selectedStudentIds.length,
      isPaid: _isPaid,
      amount: _isPaid ? (double.tryParse(_amountController.text) ?? 0) : 0,
      paymentStatus: {},
      authorId: FirebaseAuth.instance.currentUser?.uid ?? '',
      createdAt: DateTime.now(),
    );

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(child: CircularProgressIndicator()),
      );

      final tripId = await _service.createFieldTrip(trip);

      if (_createSurvey && surveyPublish != null) {
        final tripWithId = FieldTrip.fromMap(trip.toMap(), tripId);
        await _service.createParticipationSurvey(tripWithId, surveyPublish);
      }

      Navigator.pop(context); // Close dialog
      Navigator.pop(context); // Close form
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gezi planı başarıyla oluşturuldu!')),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }
}
