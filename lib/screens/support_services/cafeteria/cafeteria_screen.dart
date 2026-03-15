import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:typed_data';
// import 'package:file_saver/file_saver.dart'; // Using file_picker/universal_html approach or just file_saver if preferred for web/desktop.
// Since user is on Windows (desktop), file_saver is good.
import 'package:file_saver/file_saver.dart';

class CafeteriaScreen extends StatefulWidget {
  final String? fixedSchoolTypeId;
  final String? fixedSchoolTypeName;

  const CafeteriaScreen({
    Key? key,
    this.fixedSchoolTypeId,
    this.fixedSchoolTypeName,
  }) : super(key: key);

  @override
  State<CafeteriaScreen> createState() => _CafeteriaScreenState();
}

class _CafeteriaScreenState extends State<CafeteriaScreen> {
  String? _institutionId;
  List<Map<String, dynamic>> _schoolTypes = [];
  List<Map<String, dynamic>> _mealPeriods = [];
  String? _selectedFilterSchoolTypeId;

  @override
  void initState() {
    super.initState();
    if (widget.fixedSchoolTypeId != null) {
      _selectedFilterSchoolTypeId = widget.fixedSchoolTypeId;
    }
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {});
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      _institutionId = userDoc.data()?['institutionId'];

      if (_institutionId == null) {
        if (mounted) setState(() {});
        return;
      }

      await _loadSchoolTypes();
      await _loadMealPeriods();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadSchoolTypes() async {
    final schoolTypesSnap = await FirebaseFirestore.instance
        .collection('schoolTypes')
        .where('institutionId', isEqualTo: _institutionId)
        .get();

    if (schoolTypesSnap.docs.isNotEmpty) {
      _schoolTypes = schoolTypesSnap.docs
          .map(
            (d) => {
              'id': d.id,
              'name':
                  d.data()['schoolTypeName'] ??
                  d.data()['typeName'] ??
                  d.data()['schoolType'] ??
                  'İsimsiz',
              ...d.data(),
            },
          )
          .toList();
      _schoolTypes.sort(
        (a, b) => (a['name'] as String).compareTo(b['name'] as String),
      );
    }
  }

  Future<String?> _getSchoolDocId() async {
    final snap = await FirebaseFirestore.instance
        .collection('schools')
        .where('institutionId', isEqualTo: _institutionId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first.id;
  }

  Future<void> _loadMealPeriods() async {
    final schoolId = await _getSchoolDocId();
    if (schoolId == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('mealPeriods')
        .orderBy('createdAt', descending: false)
        .get();

    _mealPeriods = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> _addMealPeriod() async {
    final nameCtrl = TextEditingController();
    final startCtrl = TextEditingController();
    final endCtrl = TextEditingController();
    List<String> selectedTypeIds = widget.fixedSchoolTypeId != null
        ? [widget.fixedSchoolTypeId!]
        : [];

    Future<void> pickTime(TextEditingController ctrl) async {
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (t != null) {
        ctrl.text =
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      }
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Yeni Öğün Ekle'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Öğün Adı (Sabah vb.)',
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startCtrl,
                          decoration: InputDecoration(
                            labelText: 'Başlangıç',
                            suffixIcon: Icon(Icons.access_time),
                          ),
                          readOnly: true,
                          onTap: () => pickTime(startCtrl),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: endCtrl,
                          decoration: InputDecoration(
                            labelText: 'Bitiş',
                            suffixIcon: Icon(Icons.access_time),
                          ),
                          readOnly: true,
                          onTap: () => pickTime(endCtrl),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  if (widget.fixedSchoolTypeId == null) ...[
                    Text(
                      'Geçerli Okul Türleri',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Divider(),
                    ..._schoolTypes.map((t) {
                      final isSelected = selectedTypeIds.contains(t['id']);
                      return CheckboxListTile(
                        title: Text(t['name']),
                        value: isSelected,
                        onChanged: (v) {
                          setState(() {
                            if (v == true)
                              selectedTypeIds.add(t['id']);
                            else
                              selectedTypeIds.remove(t['id']);
                          });
                        },
                        dense: true,
                      );
                    }),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('İptal'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.isEmpty) return;
                  final schoolId = await _getSchoolDocId();
                  if (schoolId != null) {
                    await FirebaseFirestore.instance
                        .collection('schools')
                        .doc(schoolId)
                        .collection('mealPeriods')
                        .add({
                          'name': nameCtrl.text.trim(),
                          'startTime': startCtrl.text,
                          'endTime': endCtrl.text,
                          'schoolTypeIds': selectedTypeIds,
                          'createdAt': FieldValue.serverTimestamp(),
                          'isActive': true,
                        });
                  }
                  Navigator.pop(ctx);
                  _loadMealPeriods();
                },
                child: Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteMealPeriod(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sil: $name'),
        content: Text('Bu öğünü silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final schoolId = await _getSchoolDocId();
      if (schoolId != null) {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('mealPeriods')
            .doc(id)
            .delete();
        _loadMealPeriods();
      }
    }
  }

  void _openMenuManagement(Map<String, dynamic> period) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MenuManagementScreen(
          institutionId: _institutionId!,
          periodId: period['id'],
          periodName: period['name'],
          schoolTypes: _schoolTypes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Yemekhane İşlemleri'),
        elevation: 1,
        actions: [
          IconButton(
            icon: Icon(Icons.bar_chart, color: Colors.orange),
            tooltip: 'İstatistikler',
            onPressed: () {
              if (_institutionId != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _CafeteriaStatisticsScreen(
                      institutionId: _institutionId!,
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHorizontalFilterTabs(),
          Expanded(child: _buildMealPeriodsContent()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMealPeriod,
        icon: Icon(Icons.add),
        label: Text('Öğün Ekle'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildHorizontalFilterTabs() {
    if (widget.fixedSchoolTypeId != null) return SizedBox.shrink();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 2,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            _buildTabItem(
              label: 'Tümü',
              id: null,
              isSelected: _selectedFilterSchoolTypeId == null,
            ),
            ..._schoolTypes.map((t) {
              final id = t['id'] ?? t['name'];
              final isSelected = _selectedFilterSchoolTypeId == id;
              return _buildTabItem(
                label: t['name'] ?? '',
                id: id,
                isSelected: isSelected,
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem({
    required String label,
    required String? id,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilterSchoolTypeId = id;
        });
      },
      child: Container(
        margin: EdgeInsets.only(right: 8),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.orange : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade700,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildMealPeriodsContent() {
    final filteredPeriods = _selectedFilterSchoolTypeId == null
        ? _mealPeriods
        : _mealPeriods.where((p) {
            final typeIds = List<String>.from(p['schoolTypeIds'] ?? []);
            return typeIds.isEmpty ||
                typeIds.contains(_selectedFilterSchoolTypeId);
          }).toList();

    if (filteredPeriods.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.restaurant_menu, size: 64, color: Colors.grey.shade400),
            SizedBox(height: 16),
            Text(
              'Henüz öğün tanımlanmamış',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: filteredPeriods.length,
      itemBuilder: (context, index) {
        final period = filteredPeriods[index];
        return Card(
          margin: EdgeInsets.only(bottom: 12),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: Colors.orange.shade100,
              child: Icon(Icons.restaurant, color: Colors.orange.shade800),
            ),
            title: Text(
              period['name'] ?? '',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Builder(
              builder: (context) {
                final typeIds = List<String>.from(
                  period['schoolTypeIds'] ?? [],
                );
                final typeNames = _schoolTypes
                    .where((t) => typeIds.contains(t['id'] ?? t['name']))
                    .map((t) => t['name'] as String)
                    .join(', ');

                return Text(
                  typeIds.isEmpty ? 'Tüm Okul Türleri' : typeNames,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                  onPressed: () =>
                      _deleteMealPeriod(period['id'], period['name']),
                ),
                Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
              ],
            ),
            onTap: () => _openMenuManagement(period),
          ),
        );
      },
    );
  }
}

class _MenuManagementScreen extends StatefulWidget {
  final String institutionId;
  final String periodId;
  final String periodName;
  final List<Map<String, dynamic>> schoolTypes;

  const _MenuManagementScreen({
    required this.institutionId,
    required this.periodId,
    required this.periodName,
    required this.schoolTypes,
  });

  @override
  State<_MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<_MenuManagementScreen> {
  List<Map<String, dynamic>> _menus = [];
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadMenus();
  }

  Future<String> _getSchoolDocId() async {
    final snap = await FirebaseFirestore.instance
        .collection('schools')
        .where('institutionId', isEqualTo: widget.institutionId)
        .limit(1)
        .get();
    return snap.docs.first.id;
  }

  Future<void> _loadMenus() async {
    setState(() => _isLoading = true);
    try {
      final schoolDocId = await _getSchoolDocId();

      final startOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      final endOfDay = startOfDay.add(Duration(days: 1));

      final snap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolDocId)
          .collection('mealPeriods')
          .doc(widget.periodId)
          .collection('menus')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      setState(() {
        _menus = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      });
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

  Future<void> _addMenuManually() async {
    final foodNameCtrl = TextEditingController();
    final calorieCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Yeni Menü Ekle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tarih: ${DateFormat('dd.MM.yyyy').format(_selectedDate)}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 16),

              TextField(
                controller: foodNameCtrl,
                decoration: InputDecoration(
                  labelText: 'Yemek Adı *',
                  prefixIcon: Icon(Icons.fastfood),
                ),
                textCapitalization: TextCapitalization.words,
                autofocus: true,
              ),
              SizedBox(height: 12),

              TextField(
                controller: calorieCtrl,
                decoration: InputDecoration(
                  labelText: 'Kalori (isteğe bağlı)',
                  prefixIcon: Icon(Icons.local_fire_department),
                  hintText: 'Örn: 450',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text('Ekle'),
          ),
        ],
      ),
    );

    if (result != true) return;
    if (foodNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Yemek adı zorunludur!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final schoolDocId = await _getSchoolDocId();
    await FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolDocId)
        .collection('mealPeriods')
        .doc(widget.periodId)
        .collection('menus')
        .add({
          'date': Timestamp.fromDate(_selectedDate),
          'foodName': foodNameCtrl.text.trim(),
          'calories': calorieCtrl.text.trim().isNotEmpty
              ? int.tryParse(calorieCtrl.text.trim())
              : null,
          'schoolTypeIds': [],
          'createdAt': FieldValue.serverTimestamp(),
        });

    _loadMenus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✓ Menü eklendi'), backgroundColor: Colors.green),
    );
  }

  Future<void> _deleteMenu(String id) async {
    final schoolDocId = await _getSchoolDocId();
    await FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolDocId)
        .collection('mealPeriods')
        .doc(widget.periodId)
        .collection('menus')
        .doc(id)
        .delete();

    _loadMenus();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Menü silindi'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _loadMenus();
  }

  Future<void> _downloadTemplate() async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['Sheet1'];

    // Header Row
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue(
      'Tarih (GG.AA.YYYY)',
    );
    sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue(
      'Yemek Adı',
    );
    sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('Kalori');

    // Sample Data
    final tomorrow = DateTime.now().add(Duration(days: 1));
    final dateStr = DateFormat('dd.MM.yyyy').format(tomorrow);

    sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue(dateStr);
    sheet.cell(CellIndex.indexByString('B2')).value = TextCellValue(
      'Mercimek Çorbası',
    );
    sheet.cell(CellIndex.indexByString('C2')).value = IntCellValue(150);

    sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue(dateStr);
    sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue(
      'Izgara Tavuk',
    );
    sheet.cell(CellIndex.indexByString('C3')).value = IntCellValue(300);

    final fileBytes = excel.save();
    if (fileBytes != null) {
      final fileName = 'Menu_Sablonu.xlsx';
      await FileSaver.instance.saveFile(
        name: 'Menu_Sablonu',
        bytes: Uint8List.fromList(fileBytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Şablon indirildi: $fileName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _importFromExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final fileBytes = result.files.first.bytes;
      if (fileBytes == null) return;

      setState(() => _isLoading = true);

      final excel = Excel.decodeBytes(fileBytes);
      final schoolDocId = await _getSchoolDocId();

      int importedCount = 0;
      final batch = FirebaseFirestore.instance.batch();
      final collectionRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolDocId)
          .collection('mealPeriods')
          .doc(widget.periodId)
          .collection('menus');

      for (var table in excel.tables.keys) {
        final sheet = excel.tables[table];
        if (sheet == null) continue;

        // Skip header row
        for (int i = 1; i < sheet.maxRows; i++) {
          final row = sheet.rows[i];
          if (row.isEmpty) continue;

          // A: Date, B: Food Name, C: Calories
          final dateCell = row.elementAtOrNull(0)?.value;
          final foodCell = row.elementAtOrNull(1)?.value;
          final calCell = row.elementAtOrNull(2)?.value;

          if (dateCell == null || foodCell == null) continue;

          DateTime? menuDate;
          String foodName = foodCell.toString().trim();
          int? calories;

          // Parse Date
          if (dateCell is DateCellValue) {
            // Excel date
            final d = dateCell.asDateTimeLocal();
            menuDate = DateTime(d.year, d.month, d.day); // Strip time
          } else if (dateCell is TextCellValue) {
            try {
              // Expecting DD.MM.YYYY
              menuDate = DateFormat(
                'dd.MM.yyyy',
              ).parse(dateCell.value.toString().trim());
            } catch (e) {
              print('Date parse error row $i: $e');
              continue;
            }
          }

          if (menuDate == null || foodName.isEmpty) continue;

          // Parse Calories
          if (calCell != null) {
            if (calCell is IntCellValue)
              calories = calCell.value;
            else if (calCell is TextCellValue)
              calories = int.tryParse(calCell.value.toString().trim());
            else if (calCell is DoubleCellValue)
              calories = calCell.value.toInt();
          }

          final docRef = collectionRef.doc();
          batch.set(docRef, {
            'date': Timestamp.fromDate(menuDate),
            'foodName': foodName,
            'calories': calories,
            'schoolTypeIds': [],
            'createdAt': FieldValue.serverTimestamp(),
          });
          importedCount++;

          // Commit batch every 400 items
          if (importedCount % 400 == 0) {
            await batch.commit();
          }
        }
      }

      // Commit remaining
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$importedCount menü başarıyla yüklendi.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      _loadMenus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Yükleme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.periodName} Menüleri'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'download_template') {
                _downloadTemplate();
              } else if (value == 'import_excel') {
                _importFromExcel();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'download_template',
                child: Row(
                  children: [
                    Icon(Icons.download, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('Şablon İndir'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'import_excel',
                child: Row(
                  children: [
                    Icon(Icons.upload_file, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Excel\'den Yükle'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(vertical: 12),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: () => _changeDate(-1),
                  icon: Icon(Icons.chevron_left),
                  tooltip: 'Önceki Gün',
                ),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                      locale: const Locale('tr', 'TR'),
                    );
                    if (picked != null) {
                      setState(() => _selectedDate = picked);
                      _loadMenus();
                    }
                  },
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 18,
                        color: Colors.orange,
                      ),
                      SizedBox(width: 8),
                      Text(
                        DateFormat(
                          'dd MMMM yyyy',
                          'tr_TR',
                        ).format(_selectedDate),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _changeDate(1),
                  icon: Icon(Icons.chevron_right),
                  tooltip: 'Sonraki Gün',
                ),
              ],
            ),
          ),

          Divider(height: 1),

          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _menus.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.restaurant,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Bu tarihte menü bulunamadı',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: _menus.length,
                    itemBuilder: (context, index) {
                      final menu = _menus[index];
                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.orange.shade50,
                            child: Icon(Icons.fastfood, color: Colors.orange),
                          ),
                          title: Text(menu['foodName'] ?? ''),
                          subtitle: menu['calories'] != null
                              ? Text(
                                  '${menu['calories']} kcal',
                                  style: TextStyle(color: Colors.grey),
                                )
                              : null,
                          trailing: IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              color: Colors.red.shade300,
                            ),
                            onPressed: () => _deleteMenu(menu['id']),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addMenuManually,
        child: Icon(Icons.add),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
    );
  }
}

class _CafeteriaStatisticsScreen extends StatefulWidget {
  final String institutionId;
  const _CafeteriaStatisticsScreen({required this.institutionId});

  @override
  State<_CafeteriaStatisticsScreen> createState() =>
      _CafeteriaStatisticsScreenState();
}

class _CafeteriaStatisticsScreenState
    extends State<_CafeteriaStatisticsScreen> {
  bool _isLoading = true;
  Map<String, int> _foodCounts = {};
  int _totalMenus = 0;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    try {
      final schoolSnap = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', isEqualTo: widget.institutionId)
          .limit(1)
          .get();

      if (schoolSnap.docs.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final schoolId = schoolSnap.docs.first.id;

      final periodsSnap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('mealPeriods')
          .get();

      Map<String, int> counts = {};
      int total = 0;

      for (var period in periodsSnap.docs) {
        final menusSnap = await period.reference
            .collection('menus')
            .limit(500)
            .get();

        for (var doc in menusSnap.docs) {
          final name = (doc.data()['foodName'] as String?)?.trim() ?? '';
          if (name.isNotEmpty) {
            counts[name] = (counts[name] ?? 0) + 1;
            total++;
          }
        }
      }

      final sortedEntries = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      Map<String, int> sortedCounts = Map.fromEntries(sortedEntries);

      if (mounted) {
        setState(() {
          _foodCounts = sortedCounts;
          _totalMenus = total;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İstatistik yüklenirken hata: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final topFoods = _foodCounts.entries.take(20).toList();

    return Scaffold(
      appBar: AppBar(title: Text('En Çok Çıkan Yemekler')),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _totalMenus == 0
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bar_chart, size: 64, color: Colors.grey.shade300),
                  SizedBox(height: 16),
                  Text('Henüz veri yok.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: topFoods.length,
              itemBuilder: (ctx, index) {
                final entry = topFoods[index];
                return Card(
                  margin: EdgeInsets.only(bottom: 8),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange.shade50,
                      radius: 18,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    title: Text(
                      entry.key,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: Text(
                      '${entry.value} kez',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
