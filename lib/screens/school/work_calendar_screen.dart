import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/term_service.dart';
import 'dart:typed_data';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';

class WorkCalendarScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;
  final bool isTeacher;

  const WorkCalendarScreen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
    this.isTeacher = false,
  }) : super(key: key);

  @override
  State<WorkCalendarScreen> createState() => _WorkCalendarScreenState();
}

class _WorkCalendarScreenState extends State<WorkCalendarScreen>
    with WidgetsBindingObserver {
  String? _selectedPeriodId;
  Map<String, dynamic>? _selectedPeriod;
  String _searchQuery = '';
  final DateFormat _dateFormat = DateFormat('dd.MM.yyyy');
  String? _currentTermId;
  bool _isViewingPastTerm = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTermFilter();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadTermFilter();
    }
  }

  Future<void> _loadTermFilter() async {
    final selectedTermId = await TermService().getSelectedTermId();
    final activeTermId = await TermService().getActiveTermId();
    final effectiveTermId = selectedTermId ?? activeTermId;
    if (mounted) {
      setState(() {
        _currentTermId = effectiveTermId;
        _isViewingPastTerm =
            selectedTermId != null && selectedTermId != activeTermId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.green),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Çalışma Takvimi ve Yıllık Planlar',
              style: TextStyle(
                color: Colors.grey.shade900,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.schoolTypeName,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
      floatingActionButton: _isViewingPastTerm || widget.isTeacher
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showPeriodFormDialog(),
              backgroundColor: Colors.green,
              icon: Icon(Icons.add, color: Colors.white),
              label: Text(
                'Yeni Alt Dönem',
                style: TextStyle(color: Colors.white),
              ),
            ),
      body: Row(
        children: [
          // Sol Panel - Alt Dönemler Listesi
          Container(
            width: isWideScreen ? 350 : MediaQuery.of(context).size.width,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(
                right: BorderSide(color: Colors.grey.shade300, width: 1),
              ),
            ),
            child: Column(
              children: [
                // Arama
                Container(
                  padding: EdgeInsets.all(16),
                  child: TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      hintText: 'Alt dönem ara...',
                      prefixIcon: Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.green, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      constraints: BoxConstraints(maxHeight: 40),
                    ),
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                SizedBox(height: 8),
                // Alt Dönemler Listesi
                Expanded(child: _buildPeriodsList()),
              ],
            ),
          ),
          // Sağ Panel - Detay
          if (isWideScreen)
            Expanded(
              child: _selectedPeriod != null
                  ? _PeriodDetailScreen(
                      periodId: _selectedPeriodId!,
                      periodData: _selectedPeriod!,
                      schoolTypeId: widget.schoolTypeId,
                      schoolTypeName: widget.schoolTypeName,
                      institutionId: widget.institutionId,
                      onPeriodUpdated: () => setState(() {}),
                    )
                  : _buildEmptyState(),
            ),
        ],
      ),
    );
  }

  Widget _buildPeriodsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('workPeriods')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          print('❌ Firestore Error: ${snapshot.error}');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, size: 64, color: Colors.red.shade400),
                SizedBox(height: 16),
                Text(
                  'Veri yüklenirken hata oluştu',
                  style: TextStyle(color: Colors.red),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                SizedBox(height: 16),
                Text(
                  'Henüz alt dönem tanımlanmamış',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                SizedBox(height: 8),
                Text(
                  'Yeni alt dönem eklemek için + butonuna tıklayın',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
          );
        }

        print('📋 Alt dönemler yüklendi: ${snapshot.data!.docs.length} adet');
        print('   schoolTypeId: ${widget.schoolTypeId}');
        print('   institutionId: ${widget.institutionId}');

        var periods = snapshot.data!.docs.toList();

        // Dönem filtresi
        if (_currentTermId != null) {
          periods = periods.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['termId'] == _currentTermId;
          }).toList();
        }

        // Tarihe göre sırala (en yeni en üstte)
        periods.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aDate =
              (aData['startDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
          final bDate =
              (bData['startDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
          return bDate.compareTo(aDate);
        });

        // Arama filtresi
        if (_searchQuery.isNotEmpty) {
          periods = periods.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final name = (data['periodName'] ?? '').toString().toLowerCase();
            return name.contains(_searchQuery.toLowerCase());
          }).toList();
        }

        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: 8),
          itemCount: periods.length,
          itemBuilder: (context, index) {
            final doc = periods[index];
            final data = doc.data() as Map<String, dynamic>;
            final isSelected = _selectedPeriodId == doc.id;

            final startDate = (data['startDate'] as Timestamp?)?.toDate();
            final endDate = (data['endDate'] as Timestamp?)?.toDate();

            return Card(
              margin: EdgeInsets.only(bottom: 8),
              elevation: isSelected ? 3 : 1,
              color: isSelected ? Colors.green.shade50 : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? Colors.green : Colors.transparent,
                  width: 2,
                ),
              ),
              child: InkWell(
                onTap: () {
                  final isWideScreen = MediaQuery.of(context).size.width > 900;
                  if (isWideScreen) {
                    setState(() {
                      _selectedPeriodId = doc.id;
                      _selectedPeriod = {...data, 'id': doc.id};
                    });
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => _PeriodDetailScreen(
                          periodId: doc.id,
                          periodData: {...data, 'id': doc.id},
                          schoolTypeId: widget.schoolTypeId,
                          schoolTypeName: widget.schoolTypeName,
                          institutionId: widget.institutionId,
                          onPeriodUpdated: () => setState(() {}),
                          isTeacher: widget.isTeacher,
                        ),
                      ),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.green.shade100,
                            child: Icon(
                              Icons.calendar_month,
                              color: Colors.green,
                              size: 20,
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              data['periodName'] ?? '',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (!widget.isTeacher)
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert, color: Colors.grey),
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _showPeriodFormDialog(
                                    periodId: doc.id,
                                    existingData: data,
                                  );
                                } else if (value == 'delete') {
                                  _deletePeriod(doc.id, data['periodName']);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Düzenle'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    'Sil',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.date_range, size: 16, color: Colors.grey),
                          SizedBox(width: 8),
                          Text(
                            startDate != null
                                ? _dateFormat.format(startDate)
                                : '-',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          Text(' - ', style: TextStyle(color: Colors.grey)),
                          Text(
                            endDate != null ? _dateFormat.format(endDate) : '-',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_month, size: 80, color: Colors.grey.shade300),
          SizedBox(height: 16),
          Text(
            'Alt dönem seçin',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Sol listeden bir alt dönem seçerek yıllık planları görüntüleyin',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Future<void> _showPeriodFormDialog({
    String? periodId,
    Map<String, dynamic>? existingData,
  }) async {
    final nameController = TextEditingController(
      text: existingData?['periodName'] ?? '',
    );
    DateTime? startDate = existingData?['startDate'] != null
        ? (existingData!['startDate'] as Timestamp).toDate()
        : null;
    DateTime? endDate = existingData?['endDate'] != null
        ? (existingData!['endDate'] as Timestamp).toDate()
        : null;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.calendar_month, color: Colors.green),
              SizedBox(width: 12),
              Text(periodId != null ? 'Alt Dönem Düzenle' : 'Yeni Alt Dönem'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Dönem Adı *',
                    hintText: 'Örn: Yaz Kursu, 1. Dönem',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: Icon(Icons.label),
                  ),
                ),
                SizedBox(height: 16),
                // Başlangıç Tarihi
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: startDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setDialogState(() => startDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Başlangıç Tarihi *',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(
                      startDate != null
                          ? _dateFormat.format(startDate!)
                          : 'Tarih seçin',
                      style: TextStyle(
                        color: startDate != null ? Colors.black : Colors.grey,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                // Bitiş Tarihi
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: endDate ?? (startDate ?? DateTime.now()),
                      firstDate: startDate ?? DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setDialogState(() => endDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Bitiş Tarihi *',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(Icons.event),
                    ),
                    child: Text(
                      endDate != null
                          ? _dateFormat.format(endDate!)
                          : 'Tarih seçin',
                      style: TextStyle(
                        color: endDate != null ? Colors.black : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('İptal'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                if (nameController.text.isEmpty ||
                    startDate == null ||
                    endDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Lütfen tüm alanları doldurun')),
                  );
                  return;
                }

                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);

                // Yeni kayıtlar için aktif dönemi otomatik al
                final activeTermId = await TermService().getActiveTermId();

                final data = {
                  'periodName': nameController.text,
                  'startDate': Timestamp.fromDate(startDate!),
                  'endDate': Timestamp.fromDate(endDate!),
                  'schoolTypeId': widget.schoolTypeId,
                  'schoolTypeName': widget.schoolTypeName,
                  'institutionId': widget.institutionId,
                  'termId': activeTermId,
                  'isActive': true,
                  'updatedAt': FieldValue.serverTimestamp(),
                };

                try {
                  if (periodId != null) {
                    await FirebaseFirestore.instance
                        .collection('workPeriods')
                        .doc(periodId)
                        .update(data);
                  } else {
                    data['createdAt'] = FieldValue.serverTimestamp();
                    await FirebaseFirestore.instance
                        .collection('workPeriods')
                        .add(data);
                  }
                  navigator.pop(true);
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              icon: Icon(Icons.save),
              label: Text(periodId != null ? 'Güncelle' : 'Kaydet'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            periodId != null
                ? 'Alt dönem güncellendi'
                : 'Alt dönem oluşturuldu',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _deletePeriod(String periodId, String periodName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Alt Dönemi Sil'),
        content: Text(
          '$periodName alt dönemini silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('workPeriods')
            .doc(periodId)
            .update({'isActive': false});

        if (_selectedPeriodId == periodId) {
          setState(() {
            _selectedPeriodId = null;
            _selectedPeriod = null;
          });
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Alt dönem silindi'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// Alt Dönem Detay Ekranı
class _PeriodDetailScreen extends StatefulWidget {
  final String periodId;
  final Map<String, dynamic> periodData;
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;
  final VoidCallback onPeriodUpdated;

  final bool isTeacher;

  const _PeriodDetailScreen({
    required this.periodId,
    required this.periodData,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
    required this.onPeriodUpdated,
    this.isTeacher = false,
  });

  @override
  State<_PeriodDetailScreen> createState() => _PeriodDetailScreenState();
}

class _PeriodDetailScreenState extends State<_PeriodDetailScreen> {
  final DateFormat _dateFormat = DateFormat('dd.MM.yyyy');

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 900;
    final startDate = (widget.periodData['startDate'] as Timestamp?)?.toDate();
    final endDate = (widget.periodData['endDate'] as Timestamp?)?.toDate();

    return Scaffold(
      appBar: isWideScreen
          ? null
          : AppBar(
              title: Text(widget.periodData['periodName'] ?? ''),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
      // FAB sadece mobil görünümde göster (geniş ekranda ana ekranın FAB'ı var)
      floatingActionButton: isWideScreen
          ? null
          : FloatingActionButton.extended(
              onPressed: _showCreatePlanWizard,
              backgroundColor: Colors.green,
              icon: Icon(Icons.add, color: Colors.white),
              label: Text(
                'Yıllık Plan Oluştur',
                style: TextStyle(color: Colors.white),
              ),
            ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dönem Bilgileri
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.green.shade100,
                          child: Icon(
                            Icons.calendar_month,
                            color: Colors.green,
                            size: 32,
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.periodData['periodName'] ?? '',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.date_range,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    '${startDate != null ? _dateFormat.format(startDate) : '-'} - ${endDate != null ? _dateFormat.format(endDate) : '-'}',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 24),
            // Yıllık Planlar
            _YearlyPlansCard(
              periodId: widget.periodId,
              schoolTypeId: widget.schoolTypeId,
              institutionId: widget.institutionId,
              onCreatePlan: _showCreatePlanWizard,
              isTeacher: widget.isTeacher,
            ),
          ],
        ),
      ),
    );
  }

  void _showCreatePlanWizard() {
    showDialog(
      context: context,
      builder: (context) => _CreatePlanWizard(
        periodId: widget.periodId,
        periodName: widget.periodData['periodName'] ?? '',
        schoolTypeId: widget.schoolTypeId,
        institutionId: widget.institutionId,
        isTeacher: widget.isTeacher,
        onPlanCreated: () {
          widget.onPeriodUpdated();
          setState(() {});
        },
      ),
    );
  }
}

// Yıllık Planlar Kartı
class _YearlyPlansCard extends StatefulWidget {
  final String periodId;
  final String schoolTypeId;
  final String institutionId;
  final VoidCallback onCreatePlan;
  final bool isTeacher;

  const _YearlyPlansCard({
    required this.periodId,
    required this.schoolTypeId,
    required this.institutionId,
    required this.onCreatePlan,
    this.isTeacher = false,
  });

  @override
  State<_YearlyPlansCard> createState() => _YearlyPlansCardState();
}

class _YearlyPlansCardState extends State<_YearlyPlansCard> {
  final Set<String> _expandedLessons = {};

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.event_note, color: Colors.green),
                SizedBox(width: 12),
                Text(
                  'Ders İşleyiş Planları',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Spacer(),
                TextButton.icon(
                  onPressed: widget.onCreatePlan,
                  icon: Icon(Icons.add, size: 18),
                  label: Text('Yeni Plan'),
                  style: TextButton.styleFrom(foregroundColor: Colors.green),
                ),
              ],
            ),
          ),
          Divider(height: 1),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('yearlyPlans')
                .where('periodId', isEqualTo: widget.periodId)
                .where('isActive', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.event_note,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Henüz yıllık plan oluşturulmamış',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: widget.onCreatePlan,
                          icon: Icon(Icons.add),
                          label: Text('Yıllık Plan Oluştur'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Planları derse göre grupla
              final Map<String, List<QueryDocumentSnapshot>> plansByLesson = {};
              for (var doc in snapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final lessonName = data['lessonName'] ?? 'Bilinmeyen Ders';
                plansByLesson.putIfAbsent(lessonName, () => []);
                plansByLesson[lessonName]!.add(doc);
              }

              // Dersleri alfabetik sırala
              final sortedLessons = plansByLesson.keys.toList()..sort();

              return ListView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: sortedLessons.length,
                itemBuilder: (context, index) {
                  final lessonName = sortedLessons[index];
                  final plans = plansByLesson[lessonName]!;
                  final isExpanded = _expandedLessons.contains(lessonName);
                  final planCount = plans.length;

                  return Column(
                    children: [
                      if (index > 0) Divider(height: 1),
                      // Ders Başlığı (tıklanabilir)
                      InkWell(
                        onTap: () {
                          setState(() {
                            if (isExpanded) {
                              _expandedLessons.remove(lessonName);
                            } else {
                              _expandedLessons.add(lessonName);
                            }
                          });
                        },
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.green.shade100,
                                child: Icon(
                                  Icons.book,
                                  color: Colors.green,
                                  size: 18,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  lessonName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$planCount Plan',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(
                                isExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Genişletilmiş Plan Listesi
                      if (isExpanded)
                        Container(
                          color: Colors.grey.shade50,
                          child: Column(
                            children: plans.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final planTitle =
                                  data['planTitle'] ?? data['lessonName'] ?? '';
                              final classNames =
                                  (data['classNames'] as List<dynamic>?)?.join(
                                    ', ',
                                  ) ??
                                  '';
                              final classCount =
                                  (data['classIds'] as List<dynamic>?)
                                      ?.length ??
                                  0;

                              return Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding: EdgeInsets.only(
                                    left: 56,
                                    right: 16,
                                  ),
                                  leading: Icon(
                                    Icons.description,
                                    color: Colors.green.shade400,
                                    size: 20,
                                  ),
                                  title: Text(
                                    planTitle.isNotEmpty
                                        ? planTitle
                                        : classNames,
                                    style: TextStyle(fontSize: 14),
                                  ),
                                  subtitle:
                                      classNames.isNotEmpty &&
                                          planTitle.isNotEmpty
                                      ? Text(
                                          classNames,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        )
                                      : null,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          '$classCount Şube',
                                          style: TextStyle(
                                            color: Colors.blue.shade700,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      if (!widget.isTeacher) ...[
                                        SizedBox(width: 4),
                                        IconButton(
                                          icon: Icon(
                                            Icons.delete_outline,
                                            color: Colors.red,
                                            size: 18,
                                          ),
                                          onPressed: () => _deletePlan(
                                            doc.id,
                                            planTitle.isNotEmpty
                                                ? planTitle
                                                : lessonName,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: BoxConstraints(
                                            minWidth: 32,
                                            minHeight: 32,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  onTap: () => _openPlanDetail(doc.id, data),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _openPlanDetail(String planId, Map<String, dynamic> planData) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _PlanDetailScreen(
          planId: planId,
          planData: planData,
          periodId: widget.periodId,
          schoolTypeId: widget.schoolTypeId,
          institutionId: widget.institutionId,
        ),
      ),
    );
  }

  Future<void> _deletePlan(String planId, String planName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Planı Sil'),
        content: Text(
          '$planName yıllık planını silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('yearlyPlans')
            .doc(planId)
            .update({'isActive': false});

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Plan silindi'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}

// Yıllık Plan Oluşturma Wizard
class _CreatePlanWizard extends StatefulWidget {
  final String periodId;
  final String periodName;
  final String schoolTypeId;
  final String institutionId;
  final VoidCallback onPlanCreated;
  final bool isTeacher;

  const _CreatePlanWizard({
    required this.periodId,
    required this.periodName,
    required this.schoolTypeId,
    required this.institutionId,
    required this.onPlanCreated,
    this.isTeacher = false,
  });

  @override
  State<_CreatePlanWizard> createState() => _CreatePlanWizardState();
}

class _CreatePlanWizardState extends State<_CreatePlanWizard> {
  int _currentStep = 0;

  // Step 1: Ders Seçimi
  List<Map<String, dynamic>> _lessons = [];
  String? _selectedLessonId;
  Map<String, dynamic>? _selectedLesson;
  int? _selectedClassLevel;
  bool _isLoadingLessons = true;

  // Step 2: Sınıf Seçimi
  List<Map<String, dynamic>> _classes = [];
  Set<String> _selectedClassIds = {};
  bool _isLoadingClasses = false;

  // Step 3: Detay Girişi
  final _planTitleController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLessons();
  }

  Future<void> _loadLessons() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('lessons')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      setState(() {
        _lessons = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
        _lessons.sort(
          (a, b) => (a['lessonName'] ?? '').compareTo(b['lessonName'] ?? ''),
        );
        _isLoadingLessons = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingLessons = false);
    }
  }

  Future<void> _loadClassesForLesson() async {
    if (_selectedLessonId == null) return;

    setState(() => _isLoadingClasses = true);

    try {
      // Bu dersin atandığı sınıfları bul
      final assignmentsSnapshot = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('lessonId', isEqualTo: _selectedLessonId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      final classIds = assignmentsSnapshot.docs
          .map((doc) => doc.data()['classId'] as String)
          .toSet()
          .toList();

      if (classIds.isEmpty) {
        setState(() {
          _classes = [];
          _isLoadingClasses = false;
        });
        return;
      }

      // Sınıf bilgilerini al
      final classesSnapshot = await FirebaseFirestore.instance
          .collection('classes')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      var classes = classesSnapshot.docs
          .where((doc) => classIds.contains(doc.id))
          .map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          })
          .toList();

      // Sınıf seviyesi filtresi
      if (_selectedClassLevel != null) {
        classes = classes
            .where((c) => c['classLevel'] == _selectedClassLevel)
            .toList();
      }

      classes.sort((a, b) {
        final levelCompare = (a['classLevel'] ?? 0).compareTo(
          b['classLevel'] ?? 0,
        );
        if (levelCompare != 0) return levelCompare;
        return (a['className'] ?? '').compareTo(b['className'] ?? '');
      });

      setState(() {
        _classes = classes;
        _isLoadingClasses = false;
      });
    } catch (e) {
      setState(() => _isLoadingClasses = false);
    }
  }

  Set<int> get _availableClassLevels {
    return _classes.map((c) => c['classLevel'] as int? ?? 0).toSet();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        height: 600,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_note, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Yıllık Plan Oluştur',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.periodName,
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Stepper
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStepIndicator(0, 'Ders Seç'),
                  _buildStepConnector(0),
                  _buildStepIndicator(1, 'Sınıf Seç'),
                  _buildStepConnector(1),
                  _buildStepIndicator(2, 'Detaylar'),
                ],
              ),
            ),
            Divider(height: 1),
            // Content
            Expanded(child: _buildStepContent()),
            // Actions
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentStep > 0)
                    TextButton.icon(
                      onPressed: () => setState(() => _currentStep--),
                      icon: Icon(Icons.arrow_back),
                      label: Text('Geri'),
                    )
                  else
                    SizedBox(),
                  if (_currentStep < 2)
                    ElevatedButton.icon(
                      onPressed: _canProceed() ? _nextStep : null,
                      icon: Icon(Icons.arrow_forward),
                      label: Text('İleri'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: _canProceed() ? _savePlan : null,
                      icon: Icon(Icons.save),
                      label: Text('Planı Kaydet'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label) {
    final isActive = _currentStep >= step;
    return Column(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: isActive ? Colors.green : Colors.grey.shade300,
          child: Text(
            '${step + 1}',
            style: TextStyle(
              color: isActive ? Colors.white : Colors.grey.shade600,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? Colors.green : Colors.grey,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildStepConnector(int step) {
    final isActive = _currentStep > step;
    return Container(
      width: 60,
      height: 2,
      margin: EdgeInsets.only(bottom: 20),
      color: isActive ? Colors.green : Colors.grey.shade300,
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildLessonSelection();
      case 1:
        return _buildClassSelection();
      case 2:
        return _buildDetailsForm();
      default:
        return SizedBox();
    }
  }

  Widget _buildLessonSelection() {
    if (_isLoadingLessons) {
      return Center(child: CircularProgressIndicator());
    }

    if (_lessons.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.book_outlined, size: 64, color: Colors.grey.shade400),
            SizedBox(height: 16),
            Text('Henüz ders tanımlanmamış'),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Yıllık plan oluşturmak istediğiniz dersi seçin:',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _lessons.length,
              itemBuilder: (context, index) {
                final lesson = _lessons[index];
                final isSelected = _selectedLessonId == lesson['id'];

                return Card(
                  margin: EdgeInsets.only(bottom: 8),
                  color: isSelected ? Colors.green.shade50 : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected ? Colors.green : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected
                          ? Colors.green
                          : Colors.grey.shade300,
                      child: Icon(
                        Icons.book,
                        color: isSelected ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                    title: Text(
                      lesson['lessonName'] ?? '',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      lesson['branchName'] ?? '',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedLessonId = lesson['id'];
                        _selectedLesson = lesson;
                        _selectedClassIds.clear();
                      });
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassSelection() {
    if (_isLoadingClasses) {
      return Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_selectedLesson?['lessonName']} dersinin verildiği sınıfları seçin:',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          SizedBox(height: 12),
          // Sınıf Seviyesi Filtresi
          if (_availableClassLevels.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: Text('Tümü'),
                  selected: _selectedClassLevel == null,
                  onSelected: (selected) {
                    setState(() => _selectedClassLevel = null);
                    _loadClassesForLesson();
                  },
                  selectedColor: Colors.green.shade100,
                ),
                ...(_availableClassLevels.toList()..sort()).map(
                  (level) => FilterChip(
                    label: Text('$level. Sınıf'),
                    selected: _selectedClassLevel == level,
                    onSelected: (selected) {
                      setState(
                        () => _selectedClassLevel = selected ? level : null,
                      );
                      _loadClassesForLesson();
                    },
                    selectedColor: Colors.green.shade100,
                  ),
                ),
              ],
            ),
          SizedBox(height: 12),
          Row(
            children: [
              Text(
                '${_classes.length} sınıf bulundu',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_selectedClassIds.length == _classes.length) {
                      _selectedClassIds.clear();
                    } else {
                      _selectedClassIds = _classes
                          .map((c) => c['id'] as String)
                          .toSet();
                    }
                  });
                },
                child: Text(
                  _selectedClassIds.length == _classes.length
                      ? 'Hiçbirini Seçme'
                      : 'Tümünü Seç',
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          if (_classes.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.class_outlined,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    SizedBox(height: 16),
                    Text('Bu ders henüz hiçbir sınıfa atanmamış'),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _classes.length,
                itemBuilder: (context, index) {
                  final classData = _classes[index];
                  final isSelected = _selectedClassIds.contains(
                    classData['id'],
                  );

                  return Card(
                    margin: EdgeInsets.only(bottom: 8),
                    color: isSelected ? Colors.green.shade50 : null,
                    child: CheckboxListTile(
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedClassIds.add(classData['id']);
                          } else {
                            _selectedClassIds.remove(classData['id']);
                          }
                        });
                      },
                      title: Text(
                        classData['className'] ?? '',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        '${classData['classLevel']}. Sınıf • ${classData['classTypeName'] ?? ''}',
                        style: TextStyle(fontSize: 12),
                      ),
                      secondary: CircleAvatar(
                        backgroundColor: isSelected
                            ? Colors.green
                            : Colors.grey.shade300,
                        child: Text(
                          '${classData['classLevel']}',
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : Colors.grey.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.trailing,
                    ),
                  );
                },
              ),
            ),
          if (_selectedClassIds.isNotEmpty)
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Text(
                    '${_selectedClassIds.length} sınıf seçildi',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailsForm() {
    final selectedClassNames = _classes
        .where((c) => _selectedClassIds.contains(c['id']))
        .map((c) => c['className'] as String)
        .toList();

    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Plan detaylarını girin:',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          SizedBox(height: 16),
          // Özet
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.book, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Ders: ${_selectedLesson?['lessonName']}',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.class_, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sınıflar: ${selectedClassNames.join(', ')}',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 24),
          TextField(
            controller: _planTitleController,
            decoration: InputDecoration(
              labelText: 'Plan Başlığı (Opsiyonel)',
              hintText: 'Örn: 2024-2025 Matematik Yıllık Planı',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: Icon(Icons.title),
            ),
          ),
          SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Açıklama (Opsiyonel)',
              hintText: 'Plan hakkında notlar...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: Icon(Icons.description),
            ),
          ),
        ],
      ),
    );
  }

  bool _canProceed() {
    switch (_currentStep) {
      case 0:
        return _selectedLessonId != null;
      case 1:
        return _selectedClassIds.isNotEmpty;
      case 2:
        return true;
      default:
        return false;
    }
  }

  void _nextStep() {
    if (_currentStep == 0) {
      _loadClassesForLesson();
    }
    setState(() => _currentStep++);
  }

  Future<void> _savePlan() async {
    try {
      final selectedClassNames = _classes
          .where((c) => _selectedClassIds.contains(c['id']))
          .map((c) => c['className'] as String)
          .toList();

      // Yeni kayıtlar için aktif dönemi otomatik al
      final activeTermId = await TermService().getActiveTermId();

      await FirebaseFirestore.instance.collection('yearlyPlans').add({
        'periodId': widget.periodId,
        'periodName': widget.periodName,
        'lessonId': _selectedLessonId,
        'lessonName': _selectedLesson?['lessonName'],
        'classIds': _selectedClassIds.toList(),
        'classNames': selectedClassNames,
        'planTitle': _planTitleController.text.isNotEmpty
            ? _planTitleController.text
            : '${_selectedLesson?['lessonName']} Yıllık Planı',
        'description': _descriptionController.text,
        'schoolTypeId': widget.schoolTypeId,
        'institutionId': widget.institutionId,
        'termId': activeTermId,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      widget.onPlanCreated();
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Yıllık plan oluşturuldu'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

// Plan Detay Ekranı
class _PlanDetailScreen extends StatefulWidget {
  final String planId;
  final Map<String, dynamic> planData;
  final String periodId;
  final String schoolTypeId;
  final String institutionId;

  const _PlanDetailScreen({
    required this.planId,
    required this.planData,
    required this.periodId,
    required this.schoolTypeId,
    required this.institutionId,
  });

  @override
  State<_PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends State<_PlanDetailScreen> {
  final DateFormat _dateFormat = DateFormat('dd.MM.yyyy');

  late TextEditingController _titleController;
  List<Map<String, dynamic>> _weeklyPlans = [];
  bool _isLoading = true;
  bool _isSaving = false;

  DateTime? _periodStartDate;
  DateTime? _periodEndDate;
  int _totalWeeks = 0;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.planData['planTitle'] ?? '',
    );
    _loadPeriodAndWeeks();
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (var week in _weeklyPlans) {
      (week['unitController'] as TextEditingController?)?.dispose();
      (week['topicController'] as TextEditingController?)?.dispose();
      (week['outcomeController'] as TextEditingController?)?.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPeriodAndWeeks() async {
    print('📅 Plan detay yükleniyor... periodId: ${widget.periodId}');

    try {
      // Alt dönem bilgilerini yükle
      final periodDoc = await FirebaseFirestore.instance
          .collection('workPeriods')
          .doc(widget.periodId)
          .get();

      if (!periodDoc.exists) {
        print('❌ Period bulunamadı!');
        // Period bulunamadıysa planData'dan tarihleri almayı dene
        _createWeeksFromPlanData();
        return;
      }

      final periodData = periodDoc.data()!;
      _periodStartDate = (periodData['startDate'] as Timestamp?)?.toDate();
      _periodEndDate = (periodData['endDate'] as Timestamp?)?.toDate();

      print('📅 Dönem tarihleri: $_periodStartDate - $_periodEndDate');

      if (_periodStartDate == null || _periodEndDate == null) {
        print('❌ Tarihler null! planData\'dan almayı dene');
        _createWeeksFromPlanData();
        return;
      }

      await _createWeeksFromDates();
    } catch (e, stackTrace) {
      print('❌ Haftalık plan yükleme hatası: $e');
      print('Stack trace: $stackTrace');
      _createWeeksFromPlanData();
    }
  }

  Future<void> _createWeeksFromDates() async {
    // Hafta sayısını hesapla
    final daysDiff = _periodEndDate!.difference(_periodStartDate!).inDays;
    _totalWeeks = (daysDiff / 7).ceil();
    if (_totalWeeks < 1) _totalWeeks = 1;

    print('📅 Gün farkı: $daysDiff, Toplam hafta: $_totalWeeks');

    // Mevcut haftalık planları yükle
    Map<int, Map<String, dynamic>> existingPlans = {};
    try {
      final weeklyPlansSnapshot = await FirebaseFirestore.instance
          .collection('yearlyPlans')
          .doc(widget.planId)
          .collection('weeklyPlans')
          .get();

      print(
        '📅 Mevcut haftalık plan sayısı: ${weeklyPlansSnapshot.docs.length}',
      );

      for (var doc in weeklyPlansSnapshot.docs) {
        final data = doc.data();
        final weekNum = data['weekNumber'];
        if (weekNum != null && weekNum is int) {
          existingPlans[weekNum] = {'id': doc.id, ...data};
        }
      }
    } catch (e) {
      print('⚠️ Mevcut planlar yüklenemedi: $e');
    }

    // Haftalık planları oluştur
    _weeklyPlans = [];
    for (int i = 1; i <= _totalWeeks; i++) {
      final weekStart = _periodStartDate!.add(Duration(days: (i - 1) * 7));
      final weekEnd = weekStart.add(Duration(days: 6));
      final existing = existingPlans[i];

      _weeklyPlans.add({
        'weekNumber': i,
        'weekStart': weekStart,
        'weekEnd': weekEnd.isAfter(_periodEndDate!) ? _periodEndDate : weekEnd,
        'id': existing?['id'],
        'unitController': TextEditingController(text: existing?['unit'] ?? ''),
        'topicController': TextEditingController(
          text: existing?['topic'] ?? '',
        ),
        'outcomeController': TextEditingController(
          text: existing?['outcome'] ?? '',
        ),
      });
    }

    print('✅ Haftalık planlar oluşturuldu: ${_weeklyPlans.length} adet');

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _createWeeksFromPlanData() {
    print('📅 PlanData\'dan hafta oluşturuluyor...');

    // Varsayılan olarak 9 hafta oluştur (görüntüde 9 hafta yazıyor)
    _totalWeeks = 9;
    _periodStartDate = DateTime.now();
    _periodEndDate = DateTime.now().add(Duration(days: 63)); // 9 hafta

    _weeklyPlans = [];
    for (int i = 1; i <= _totalWeeks; i++) {
      final weekStart = _periodStartDate!.add(Duration(days: (i - 1) * 7));
      final weekEnd = weekStart.add(Duration(days: 6));

      _weeklyPlans.add({
        'weekNumber': i,
        'weekStart': weekStart,
        'weekEnd': weekEnd,
        'id': null,
        'unitController': TextEditingController(),
        'topicController': TextEditingController(),
        'outcomeController': TextEditingController(),
      });
    }

    print(
      '✅ Varsayılan haftalık planlar oluşturuldu: ${_weeklyPlans.length} adet',
    );

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _savePlan() async {
    setState(() => _isSaving = true);

    try {
      // Ana plan bilgilerini güncelle
      await FirebaseFirestore.instance
          .collection('yearlyPlans')
          .doc(widget.planId)
          .update({
            'planTitle': _titleController.text,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      // Haftalık planları kaydet
      final batch = FirebaseFirestore.instance.batch();
      final weeklyPlansRef = FirebaseFirestore.instance
          .collection('yearlyPlans')
          .doc(widget.planId)
          .collection('weeklyPlans');

      for (var week in _weeklyPlans) {
        final data = {
          'weekNumber': week['weekNumber'],
          'weekStart': Timestamp.fromDate(week['weekStart']),
          'weekEnd': Timestamp.fromDate(week['weekEnd']),
          'unit': (week['unitController'] as TextEditingController).text,
          'topic': (week['topicController'] as TextEditingController).text,
          'outcome': (week['outcomeController'] as TextEditingController).text,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (week['id'] != null) {
          batch.update(weeklyPlansRef.doc(week['id']), data);
        } else {
          batch.set(weeklyPlansRef.doc(), data);
        }
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Plan kaydedildi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _printPlan() {
    // TODO: Yazdırma fonksiyonu
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Yazdırma özelliği yakında eklenecek'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  // Excel şablonu indir
  Future<void> _downloadTemplate() async {
    try {
      var excel = Excel.createExcel();
      // Varsayılan sayfayı al
      Sheet sheetObject = excel['Sayfa1'];

      // İlk satırı (Header) ekle
      sheetObject.appendRow([
        TextCellValue('Hafta No'),
        TextCellValue('Başlangıç'),
        TextCellValue('Bitiş'),
        TextCellValue('Ünite / Tema'),
        TextCellValue('Konu (İçerik Çerçevesi)'),
        TextCellValue('Öğrenme Çıktıları'),
      ]);

      // Mevcut haftaları ekle
      for (var week in _weeklyPlans) {
        int weekNum = week['weekNumber'];
        String start = _dateFormat.format(week['weekStart']);
        String end = _dateFormat.format(week['weekEnd']);

        String unit = (week['unitController'] as TextEditingController).text;
        String topic = (week['topicController'] as TextEditingController).text;
        String outcome =
            (week['outcomeController'] as TextEditingController).text;

        sheetObject.appendRow([
          IntCellValue(weekNum),
          TextCellValue(start),
          TextCellValue(end),
          TextCellValue(unit),
          TextCellValue(topic),
          TextCellValue(outcome),
        ]);

        // Sütun genişliklerini ayarla (opsiyonel, hata verirse kaldırılabilir)
        // sheetObject.setColWidth(0, 10);
      }

      // Gereksiz sayfayı sil
      if (excel.sheets.containsKey('Sheet1') && excel.sheets.length > 1) {
        excel.delete('Sheet1');
      }

      var fileBytes = excel.save();
      if (fileBytes != null) {
        await FileSaver.instance.saveFile(
          name: 'Yillik_Plan_Sablonu',
          bytes: Uint8List.fromList(fileBytes),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Excel şablonu indirildi'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Excel yükle ve ayrıştır
  Future<void> _importExcel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result != null) {
        var bytes = result.files.single.bytes;
        if (bytes != null) {
          var excel = Excel.decodeBytes(bytes);
          if (excel.tables.isEmpty) return;

          var table = excel.tables[excel.tables.keys.first];
          if (table == null) return;

          int updatedCount = 0;
          bool headerSkipped = false;

          for (var row in table.rows) {
            // Başlık satırını atla
            if (!headerSkipped) {
              headerSkipped = true;
              continue;
            }

            if (row.isEmpty) continue;

            // Hafta Numarasını al (0. Sütun)
            var weekNumCell = row.length > 0 ? row[0] : null;
            if (weekNumCell == null || weekNumCell.value == null) continue;

            int? weekNum;
            var val = weekNumCell.value;
            if (val != null) {
              if (val is IntCellValue) {
                weekNum = val.value;
              } else if (val is DoubleCellValue) {
                weekNum = val.value.toInt();
              } else if (val is TextCellValue) {
                weekNum = int.tryParse(val.value.text ?? '');
              }
            }

            if (weekNum != null) {
              // İlgili haftayı bul
              var weekPlan = _weeklyPlans.firstWhere(
                (w) => w['weekNumber'] == weekNum,
                orElse: () => {},
              );

              if (weekPlan.isNotEmpty) {
                // 3, 4, 5. sütunları al
                String unit = '';
                String topic = '';
                String outcome = '';

                if (row.length > 3) unit = _getStringFromCell(row[3]?.value);
                if (row.length > 4) topic = _getStringFromCell(row[4]?.value);
                if (row.length > 5) outcome = _getStringFromCell(row[5]?.value);

                (weekPlan['unitController'] as TextEditingController).text =
                    unit;
                (weekPlan['topicController'] as TextEditingController).text =
                    topic;
                (weekPlan['outcomeController'] as TextEditingController).text =
                    outcome;

                updatedCount++;
              }
            }
          }

          if (updatedCount > 0) {
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '$updatedCount hafta güncellendi. Kaydetmeyi unutmayın!',
                ),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Eşleşen hafta bulunamadı'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Excel Import Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Excel hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getStringFromCell(CellValue? cell) {
    if (cell == null) return '';
    if (cell is TextCellValue) return cell.value.text ?? '';
    if (cell is IntCellValue) return cell.value.toString();
    if (cell is DoubleCellValue) return cell.value.toString();
    return cell.toString();
  }

  @override
  Widget build(BuildContext context) {
    final periodName = widget.planData['periodName'] ?? '';
    final lessonName = widget.planData['lessonName'] ?? '';
    final classNames =
        (widget.planData['classNames'] as List<dynamic>?)?.join(', ') ?? '';

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.green),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Yıllık Plan Detayı',
              style: TextStyle(
                color: Colors.grey.shade900,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '$lessonName - $periodName',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
        actions: [
          // Excel İşlemleri
          PopupMenuButton<String>(
            icon: Icon(Icons.table_view, color: Colors.green),
            tooltip: 'Excel İşlemleri',
            onSelected: (value) {
              if (value == 'download') {
                _downloadTemplate();
              } else if (value == 'upload') {
                _importExcel();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(Icons.download, size: 20, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Şablon İndir'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'upload',
                child: Row(
                  children: [
                    Icon(Icons.upload, size: 20, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Excel Yükle'),
                  ],
                ),
              ),
            ],
          ),
          if (!_isLoading)
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: ElevatedButton.icon(
                onPressed: _printPlan,
                icon: Icon(Icons.print, size: 18),
                label: Text('Yazdır'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: !_isLoading
          ? FloatingActionButton.extended(
              onPressed: _isSaving ? null : _savePlan,
              backgroundColor: _isSaving ? Colors.grey : Colors.green,
              icon: _isSaving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(Icons.save, color: Colors.white),
              label: Text(
                _isSaving ? 'Kaydediliyor...' : 'Kaydet',
                style: TextStyle(color: Colors.white),
              ),
            )
          : null,
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 900),
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Plan Bilgileri Kartı
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.green),
                                  SizedBox(width: 12),
                                  Text(
                                    'Plan Bilgileri',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 20),
                              TextField(
                                controller: _titleController,
                                cursorColor: Colors.green,
                                decoration: InputDecoration(
                                  labelText: 'Plan Başlığı',
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 20,
                                    horizontal: 16,
                                  ),
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.green.shade300,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.green.shade300,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.green.shade700,
                                      width: 2,
                                    ),
                                  ),
                                  prefixIcon: Icon(
                                    Icons.title,
                                    color: Colors.green,
                                  ),
                                  labelStyle: TextStyle(
                                    color: Colors.green.shade700,
                                  ),
                                  floatingLabelStyle: TextStyle(
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              SizedBox(height: 16),
                              // Özet bilgiler
                              Container(
                                padding: EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    _buildInfoRow(
                                      Icons.book,
                                      'Ders',
                                      lessonName,
                                    ),
                                    SizedBox(height: 8),
                                    _buildInfoRow(
                                      Icons.class_,
                                      'Sınıflar',
                                      classNames,
                                    ),
                                    SizedBox(height: 8),
                                    _buildInfoRow(
                                      Icons.date_range,
                                      'Dönem',
                                      _periodStartDate != null &&
                                              _periodEndDate != null
                                          ? '${_dateFormat.format(_periodStartDate!)} - ${_dateFormat.format(_periodEndDate!)}'
                                          : '-',
                                    ),
                                    SizedBox(height: 8),
                                    _buildInfoRow(
                                      Icons.calendar_view_week,
                                      'Toplam Hafta',
                                      '$_totalWeeks hafta',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 24),
                      // Haftalık Planlar
                      Row(
                        children: [
                          Icon(Icons.view_week, color: Colors.green),
                          SizedBox(width: 12),
                          Text(
                            'Haftalık Plan İçerikleri',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacer(),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_weeklyPlans.length} hafta',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      if (_weeklyPlans.isEmpty)
                        Card(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.warning_amber,
                                    size: 48,
                                    color: Colors.orange,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'Haftalık plan oluşturulamadı',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Alt dönem tarihleri kontrol edilmeli',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        ..._weeklyPlans.map((week) => _buildWeekCard(week)),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.green),
        SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildWeekCard(Map<String, dynamic> week) {
    final weekNumber = week['weekNumber'] as int;
    final weekStart = week['weekStart'] as DateTime;
    final weekEnd = week['weekEnd'] as DateTime;
    final unitController = week['unitController'] as TextEditingController;
    final topicController = week['topicController'] as TextEditingController;
    final outcomeController =
        week['outcomeController'] as TextEditingController;

    // Yeşil tema için InputDecoration
    InputDecoration greenInputDecoration(
      String label,
      String hint,
      IconData icon, {
      bool alignHint = false,
    }) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        contentPadding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.green.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.green.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.green.shade700, width: 2),
        ),
        prefixIcon: Icon(icon, color: Colors.green),
        labelStyle: TextStyle(color: Colors.green.shade700),
        floatingLabelStyle: TextStyle(
          color: Colors.green.shade700,
          fontWeight: FontWeight.w500,
        ),
        alignLabelWithHint: alignHint,
      );
    }

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          colorScheme: Theme.of(
            context,
          ).colorScheme.copyWith(primary: Colors.green),
        ),
        child: ExpansionTile(
          tilePadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: Colors.green.shade100,
            child: Text(
              '$weekNumber',
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          title: Text(
            '$weekNumber. Hafta',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: Text(
            '${_dateFormat.format(weekStart)} - ${_dateFormat.format(weekEnd)}',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          iconColor: Colors.green,
          collapsedIconColor: Colors.grey,
          children: [
            // Ünite/Tema
            TextField(
              controller: unitController,
              cursorColor: Colors.green,
              decoration: greenInputDecoration(
                'Ünite / Tema',
                'Örn: 1. Ünite - Sayılar ve İşlemler',
                Icons.folder_outlined,
              ),
            ),
            SizedBox(height: 16),
            // Konu
            TextField(
              controller: topicController,
              maxLines: 2,
              cursorColor: Colors.green,
              decoration: greenInputDecoration(
                'Konu (İçerik Çerçevesi)',
                'Bu haftanın konularını yazın...',
                Icons.subject,
                alignHint: true,
              ),
            ),
            SizedBox(height: 16),
            // Öğrenme Çıktıları
            TextField(
              controller: outcomeController,
              maxLines: 3,
              cursorColor: Colors.green,
              decoration: greenInputDecoration(
                'Öğrenme Çıktıları',
                'Bu haftanın öğrenme çıktılarını yazın...',
                Icons.check_circle_outline,
                alignHint: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
