import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/term_service.dart';
import '../../services/class_schedule_sync_service.dart';
import '../../services/auto_schedule_service.dart';
import 'class_schedule_guide_page.dart';
import 'schedule_settings_panel.dart';
import '../../services/pdf_service.dart';
import '../../services/excel_service.dart';

class ClassScheduleScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const ClassScheduleScreen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<ClassScheduleScreen> createState() => _ClassScheduleScreenState();
}

class _ClassScheduleScreenState extends State<ClassScheduleScreen> {
  String? _selectedPeriodId;
  Map<String, dynamic>? _selectedPeriod;
  String? _currentTermId;
  bool _isViewingPastTerm = false;
  final DateFormat _dateFormat = DateFormat('dd.MM.yyyy');

  @override
  void initState() {
    super.initState();
    _loadTermFilter();
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

  void _showShareOptions(String periodId, String periodName) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Programı Paylaş',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(periodName, style: TextStyle(color: Colors.grey.shade600)),
            SizedBox(height: 16),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue.shade100,
                child: Icon(Icons.person, color: Colors.blue),
              ),
              title: Text('Öğretmene Paylaş'),
              subtitle: Text('Öğretmen kendi programını görebilir'),
              onTap: () {
                Navigator.pop(context);
                _showTeacherShareSelector(periodId);
              },
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.green.shade100,
                child: Icon(Icons.groups, color: Colors.green),
              ),
              title: Text('Herkese Paylaş'),
              subtitle: Text('Öğrenci ve veliler sınıf programını görebilir'),
              onTap: () {
                Navigator.pop(context);
                _publishSchedule(periodId);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTeacherShareSelector(String periodId) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Öğretmen seçici yakında eklenecek')),
    );
  }

  Future<void> _publishSchedule(String periodId) async {
    try {
      await FirebaseFirestore.instance
          .collection('workPeriods')
          .doc(periodId)
          .update({'schedulePublished': true});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Program yayınlandı!'),
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

  Future<void> _unpublishSchedule(String periodId) async {
    try {
      await FirebaseFirestore.instance
          .collection('workPeriods')
          .doc(periodId)
          .update({'schedulePublished': false});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Program yayından kaldırıldı'),
            backgroundColor: Colors.orange,
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

  @override
  Widget build(BuildContext context) {
    // Eğer dönem seçilmişse program ekranını göster
    if (_selectedPeriodId != null && _selectedPeriod != null) {
      return _ScheduleEditorScreen(
        periodId: _selectedPeriodId!,
        periodData: _selectedPeriod!,
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        institutionId: widget.institutionId,
        isViewingPastTerm: _isViewingPastTerm,
        onBack: () {
          setState(() {
            _selectedPeriodId = null;
            _selectedPeriod = null;
          });
        },
      );
    }

    // Dönem seçici ekran
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.purple),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ders Programı',
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
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline_rounded, color: Colors.purple),
            tooltip: 'Program Hazırlama Rehberi',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ClassScheduleGuidePage()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              // Başlık
              Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.calendar_view_week,
                      size: 64,
                      color: Colors.purple.shade300,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Ders Programı Oluştur',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Program oluşturmak için bir alt dönem seçin',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              // Alt Dönemler Listesi
              Expanded(child: _buildPeriodsList()),
            ],
          ),
        ),
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
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  'Önce Çalışma Takvimi\'nden dönem ekleyin',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
          );
        }

        var periods = snapshot.data!.docs.toList();

        // Dönem filtresi
        if (_currentTermId != null) {
          periods = periods.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['termId'] == _currentTermId;
          }).toList();
        }

        // Tarihe göre sırala
        periods.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aDate =
              (aData['startDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
          final bDate =
              (bData['startDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
          return aDate.compareTo(bDate);
        });

        if (periods.isEmpty) {
          return Center(
            child: Text(
              'Bu dönemde alt dönem bulunamadı',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: periods.length,
          itemBuilder: (context, index) {
            final doc = periods[index];
            final data = doc.data() as Map<String, dynamic>;

            final startDate = (data['startDate'] as Timestamp?)?.toDate();
            final endDate = (data['endDate'] as Timestamp?)?.toDate();
            final periodName = data['periodName'] ?? 'İsimsiz Dönem';

            final isPublished = data['schedulePublished'] == true;

            return Card(
              margin: EdgeInsets.only(bottom: 12),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        _selectedPeriodId = doc.id;
                        _selectedPeriod = {...data, 'id': doc.id};
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: Colors.purple.shade100,
                            child: Icon(
                              Icons.date_range,
                              color: Colors.purple,
                              size: 28,
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  periodName,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                if (startDate != null && endDate != null)
                                  Text(
                                    '${_dateFormat.format(startDate)} - ${_dateFormat.format(endDate)}',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // Yayında badge (paylaş butonunun yanında)
                          if (isPublished)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 14,
                                    color: Colors.green.shade700,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Yayında',
                                    style: TextStyle(
                                      color: Colors.green.shade700,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          SizedBox(width: 4),
                          // Paylaş butonu
                          IconButton(
                            icon: Icon(Icons.share, color: Colors.blue),
                            onPressed: () =>
                                _showShareOptions(doc.id, periodName),
                            tooltip: 'Paylaş',
                          ),
                          // 3 nokta menüsü
                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert, color: Colors.grey),
                            onSelected: (value) {
                              if (value == 'unpublish') {
                                _unpublishSchedule(doc.id);
                              }
                            },
                            itemBuilder: (context) => [
                              if (isPublished)
                                PopupMenuItem(
                                  value: 'unpublish',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.visibility_off,
                                        color: Colors.orange,
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Yayından Kaldır'),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ==================== PROGRAM DÜZENLEME EKRANI ====================
class _ScheduleEditorScreen extends StatefulWidget {
  final String periodId;
  final Map<String, dynamic> periodData;
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;
  final bool isViewingPastTerm;
  final VoidCallback onBack;

  const _ScheduleEditorScreen({
    required this.periodId,
    required this.periodData,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
    required this.isViewingPastTerm,
    required this.onBack,
  });

  @override
  State<_ScheduleEditorScreen> createState() => _ScheduleEditorScreenState();
}

class _ScheduleEditorScreenState extends State<_ScheduleEditorScreen> {
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _allClasses = []; // Filtrelenmemiş tüm sınıflar
  List<Map<String, dynamic>> _lessonHours = [];
  Map<String, List<Map<String, dynamic>>> _dayLessonTimes =
      {}; // Günlere göre ders saatleri
  Map<String, Map<String, dynamic>> _scheduleData =
      {}; // key: "classId_day_hour"
  Map<String, List<Map<String, dynamic>>> _classLessons =
      {}; // Şubeye atanmış dersler
  Map<String, int> _remainingHours = {}; // Kalan ders saatleri
  Map<String, int> _dailyLessonCounts = {}; // Her gün için ders sayısı
  Map<String, String> _lessonShortNames = {}; // lessonId -> shortName
  bool _isLoading = true;

  // Dağıtım Ayarları (Kalıcı Firestore kaydedilen)
  Map<String, List<int>> _lessonBlockPatterns = {};
  Map<String, bool> _lessonAllowSplit = {};
  Map<String, bool> _lessonAvoidFirstHour = {};
  Map<String, bool> _lessonAvoidLastHour = {};
  List<Map<String, dynamic>> _lessonClassMerges = [];
  Map<String, Set<String>> _closedSlots = {};
  Map<String, int> _teacherMaxDailyHours = {};

  // Görünüm Modu ve Yerleşemeyen Ders Seçimi State
  List<Map<String, dynamic>> _teachers = [];
  bool _isTeacherView = false;
  Map<String, dynamic>? _selectedUnassignedLesson;

  // Filtre değişkenleri
  int? _selectedClassLevel;
  String? _selectedClassType;
  Set<int> _availableClassLevels = {};
  Set<String> _availableClassTypes = {};

  List<String> _days = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma'];
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      print('🔍 Ders Programı veri yükleniyor...');
      print('   schoolTypeId: ${widget.schoolTypeId}');
      print('   institutionId: ${widget.institutionId}');
      print('   periodId: ${widget.periodId}');

      // Dağıtım Ayarlarını Firestore'dan Yükle
      try {
        final periodDoc = await FirebaseFirestore.instance
            .collection('workPeriods')
            .doc(widget.periodId)
            .get();
        if (periodDoc.exists && periodDoc.data()?['scheduleSettings'] != null) {
          final settings =
              periodDoc.data()!['scheduleSettings'] as Map<String, dynamic>;
          _lessonBlockPatterns =
              (settings['lessonBlockPatterns'] as Map<String, dynamic>?)
                      ?.map((k, v) => MapEntry(k, List<int>.from(v))) ??
                  {};
          _lessonAllowSplit =
              (settings['lessonAllowSplit'] as Map<String, dynamic>?)
                      ?.map((k, v) => MapEntry(k, v as bool)) ??
                  {};
          _lessonAvoidFirstHour =
              (settings['lessonAvoidFirstHour'] as Map<String, dynamic>?)
                      ?.map((k, v) => MapEntry(k, v as bool)) ??
                  {};
          _lessonAvoidLastHour =
              (settings['lessonAvoidLastHour'] as Map<String, dynamic>?)
                      ?.map((k, v) => MapEntry(k, v as bool)) ??
                  {};
          _lessonClassMerges = (settings['lessonClassMerges'] as List?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [];
          _closedSlots = (settings['closedSlots'] as Map<String, dynamic>?)
                  ?.map((k, v) => MapEntry(k, Set<String>.from(v as List))) ??
              {};
          _teacherMaxDailyHours =
              (settings['teacherMaxDailyHours'] as Map<String, dynamic>?)
                      ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
                  {};
        }
      } catch (e) {
        print('⚠️ Dağıtım ayarları yüklenemedi: $e');
      }

      // Şubeleri yükle
      final classesSnapshot = await FirebaseFirestore.instance
          .collection('classes')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('termId', isEqualTo: widget.periodData['termId'])
          .where('isActive', isEqualTo: true)
          .get();

      print('📚 Bulunan şube sayısı: ${classesSnapshot.docs.length}');

      // Base dersleri yükle (kısa isimler için)
      final lessonsSnapshot = await FirebaseFirestore.instance
          .collection('lessons')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('termId', isEqualTo: widget.periodData['termId'])
          .get();

      final Map<String, String> lessonShortNames = {};
      for (var doc in lessonsSnapshot.docs) {
        final data = doc.data();
        lessonShortNames[doc.id] = data['shortName'] ?? '';
      }

      final classes = classesSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // Sınıf seviyesine göre sırala
      classes.sort((a, b) {
        final levelA = (a['classLevel'] ?? 0) is int
            ? a['classLevel']
            : int.tryParse(a['classLevel'].toString()) ?? 0;
        final levelB = (b['classLevel'] ?? 0) is int
            ? b['classLevel']
            : int.tryParse(b['classLevel'].toString()) ?? 0;
        final levelCompare = levelA.compareTo(levelB);
        if (levelCompare != 0) return levelCompare;
        return (a['className'] ?? '').toString().compareTo(
          (b['className'] ?? '').toString(),
        );
      });

      // Ders saatlerini yükle (workPeriods koleksiyonundan lessonHours alanı)
      List<Map<String, dynamic>> hours = [];
      List<String> selectedDays = [];
      Map<String, dynamic> dailyCounts = {};
      try {
        print('🔍 periodId: ${widget.periodId}');
        final periodDoc = await FirebaseFirestore.instance
            .collection('workPeriods')
            .doc(widget.periodId)
            .get();

        print('📄 Dönem dokümanı var mı: ${periodDoc.exists}');

        if (periodDoc.exists) {
          final periodData = periodDoc.data()!;
          print('📋 Dönem verileri: ${periodData.keys.toList()}');

          final lessonHoursData =
              periodData['lessonHours'] as Map<String, dynamic>?;
          print('⏰ lessonHours alanı: $lessonHoursData');

          if (lessonHoursData != null) {
            // Seçili günler
            selectedDays = List<String>.from(
              lessonHoursData['selectedDays'] ?? [],
            );
            print('📅 Seçili günler: $selectedDays');

            // Günlük ders sayıları
            if (lessonHoursData['dailyLessonCounts'] != null) {
              dailyCounts = Map<String, dynamic>.from(
                lessonHoursData['dailyLessonCounts'],
              );
            }
            print('📊 Günlük ders sayıları: $dailyCounts');

            // Ders saatleri - Map veya List olabilir
            final lessonTimesRaw = lessonHoursData['lessonTimes'];
            print('🕐 lessonTimes type: ${lessonTimesRaw.runtimeType}');
            print('🕐 lessonTimes data: $lessonTimesRaw');

            // Günlere göre ders saatlerini parse et
            Map<String, List<Map<String, dynamic>>> dayTimes = {};

            if (lessonTimesRaw != null) {
              // Map ise
              if (lessonTimesRaw is Map) {
                final lessonTimesMap = Map<String, dynamic>.from(
                  lessonTimesRaw,
                );

                // Key'lerin sayı mı yoksa gün ismi mi olduğunu kontrol et
                final firstKey = lessonTimesMap.keys.first;
                final isNumericKey = int.tryParse(firstKey) != null;

                if (isNumericKey) {
                  // Key'ler sayı ise (0, 1, 2, ...) - tüm günler için aynı saatler
                  final sortedKeys = lessonTimesMap.keys.toList()
                    ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

                  hours = sortedKeys.map((key) {
                    final time = Map<String, dynamic>.from(lessonTimesMap[key]);
                    final startHour = time['startHour'] ?? 0;
                    final startMinute = time['startMinute'] ?? 0;
                    final endHour = time['endHour'] ?? 0;
                    final endMinute = time['endMinute'] ?? 0;
                    return {
                      'hourNumber': int.parse(key) + 1,
                      'startTime':
                          '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}',
                      'endTime':
                          '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}',
                    };
                  }).toList();

                  // Tüm günler için aynı saatleri kullan
                  for (var day in selectedDays) {
                    dayTimes[day] = List.from(hours);
                  }
                } else {
                  // Key'ler gün isimleri ise - her gün için ayrı saatler
                  for (var day in selectedDays) {
                    final dayData = lessonTimesMap[day];
                    if (dayData != null && dayData is List) {
                      dayTimes[day] = dayData.asMap().entries.map((entry) {
                        final time = Map<String, dynamic>.from(entry.value);
                        final startHour = time['startHour'] ?? 0;
                        final startMinute = time['startMinute'] ?? 0;
                        final endHour = time['endHour'] ?? 0;
                        final endMinute = time['endMinute'] ?? 0;
                        return {
                          'hourNumber': entry.key + 1,
                          'startTime':
                              '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}',
                          'endTime':
                              '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}',
                        };
                      }).toList();
                    } else {
                      // Bu gün için saat yoksa varsayılan oluştur
                      final dayCount = dailyCounts[day] is int
                          ? dailyCounts[day]
                          : int.tryParse(dailyCounts[day]?.toString() ?? '8') ??
                                8;
                      dayTimes[day] = List.generate(
                        dayCount,
                        (i) => {
                          'hourNumber': i + 1,
                          'startTime':
                              '${(9 + i).toString().padLeft(2, '0')}:00',
                          'endTime': '${(9 + i).toString().padLeft(2, '0')}:40',
                        },
                      );
                    }
                  }
                  // hours'ı en çok ders saati olan günden al
                  if (dayTimes.isNotEmpty) {
                    hours = dayTimes.values.reduce(
                      (a, b) => a.length > b.length ? a : b,
                    );
                  }
                  print('✅ Gün bazlı lessonTimes yapısı kullanılıyor');
                }
              }
              // List ise
              else if (lessonTimesRaw is List) {
                hours = lessonTimesRaw.asMap().entries.map((entry) {
                  final time = Map<String, dynamic>.from(entry.value);
                  final startHour = time['startHour'] ?? 0;
                  final startMinute = time['startMinute'] ?? 0;
                  final endHour = time['endHour'] ?? 0;
                  final endMinute = time['endMinute'] ?? 0;
                  return {
                    'hourNumber': entry.key + 1,
                    'startTime':
                        '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}',
                    'endTime':
                        '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}',
                  };
                }).toList();

                // Tüm günler için aynı saatleri kullan
                for (var day in selectedDays) {
                  dayTimes[day] = List.from(hours);
                }
              }
              print('✅ Ders saatleri yüklendi: ${hours.length} adet');
            } else {
              print('⚠️ lessonTimes boş veya null');
            }

            // dayTimes'ı kaydet
            _dayLessonTimes = dayTimes;
          } else {
            print('⚠️ Bu dönem için lessonHours alanı yok');
          }
        } else {
          print('⚠️ Dönem dokümanı bulunamadı');
        }
      } catch (e) {
        print('❌ Ders saatleri yüklenemedi: $e');
      }

      // Her şube için atanmış dersleri yükle
      final Map<String, List<Map<String, dynamic>>> classLessons = {};
      final Map<String, int> remainingHours = {};

      for (var classData in classes) {
        final classId = classData['id'] as String;

        try {
          // Bu şubeye atanmış dersleri bul
          final assignmentsSnapshot = await FirebaseFirestore.instance
              .collection('lessonAssignments')
              .where('classId', isEqualTo: classId)
              .where('institutionId', isEqualTo: widget.institutionId)
              .where('isActive', isEqualTo: true)
              .get();

          final lessons = assignmentsSnapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();

          classLessons[classId] = lessons;

          // Her ders için kalan saatleri hesapla
          for (var lesson in lessons) {
            final lessonKey = '${classId}_${lesson['lessonId']}';
            remainingHours[lessonKey] = (lesson['weeklyHours'] ?? 0) as int;
          }
        } catch (e) {
          print('⚠️ Şube dersleri yüklenemedi ($classId): $e');
          classLessons[classId] = [];
        }
      }

      // Mevcut programı yükle
      final Map<String, Map<String, dynamic>> scheduleData = {};
      try {
        final scheduleSnapshot = await FirebaseFirestore.instance
            .collection('classSchedules')
            .where('periodId', isEqualTo: widget.periodId)
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('isActive', isEqualTo: true)
            .get();

        for (var doc in scheduleSnapshot.docs) {
          final data = doc.data();
          final key = '${data['classId']}_${data['day']}_${data['hourIndex']}';
          scheduleData[key] = {...data, 'id': doc.id};

          // Atanmış derslerin kalan saatlerini düşür
          final lessonKey = '${data['classId']}_${data['lessonId']}';
          if (remainingHours.containsKey(lessonKey)) {
            remainingHours[lessonKey] = (remainingHours[lessonKey] ?? 1) - 1;
          }
        }
      } catch (e) {
        print('⚠️ Mevcut program yüklenemedi: $e');
      }

      // Filtre için mevcut sınıf seviyelerini ve tiplerini topla
      final Set<int> classLevels = {};
      final Set<String> classTypes = {};
      for (var c in classes) {
        final level = c['classLevel'];
        if (level != null) {
          classLevels.add(
            level is int ? level : int.tryParse(level.toString()) ?? 0,
          );
        }
        final type = c['classTypeName'] as String?;
        if (type != null && type.isNotEmpty) {
          classTypes.add(type);
        }
      }

      // Öğretmen listesini topla
      final Map<String, Map<String, dynamic>> teacherMap = {};
      for (var lessonList in classLessons.values) {
        for (var l in lessonList) {
          final tIds = (l['teacherIds'] as List?)?.map((e) => e.toString()).toList();
          final tNames = (l['teacherNames'] as List?)?.map((e) => e.toString()).toList();
          if (tIds != null && tNames != null) {
            for (int i = 0; i < tIds.length; i++) {
              final id = tIds[i];
              final name = i < tNames.length ? tNames[i] : 'Öğretmen';
              if (!teacherMap.containsKey(id) && id.isNotEmpty) {
                teacherMap[id] = {'id': id, 'name': name};
              }
            }
          } else if (l['teacherId'] != null) {
            final id = l['teacherId'].toString();
            final name = (l['teacherName'] ?? 'Öğretmen').toString();
            if (!teacherMap.containsKey(id) && id.isNotEmpty) {
              teacherMap[id] = {'id': id, 'name': name};
            }
          }
        }
      }
      final teachersList = teacherMap.values.toList()
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      setState(() {
        _allClasses = classes;
        _classes = classes;
        _teachers = teachersList;
        _lessonHours = hours;
        _classLessons = classLessons;
        _remainingHours = remainingHours;
        _lessonShortNames = lessonShortNames;
        _scheduleData = scheduleData;
        _availableClassLevels = classLevels;
        _availableClassTypes = classTypes;
        // Seçili günleri güncelle
        if (selectedDays.isNotEmpty) {
          _days = selectedDays;
        }
        // Günlük ders sayılarını set et (int'e çevir)
        _dailyLessonCounts = dailyCounts.map(
          (k, v) => MapEntry(k, v is int ? v : int.tryParse(v.toString()) ?? 0),
        );
        _isLoading = false;
      });
    } catch (e) {
      print('Veri yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    setState(() {
      _classes = _allClasses.where((c) {
        // Sınıf seviyesi filtresi
        if (_selectedClassLevel != null) {
          final level = c['classLevel'];
          final classLevel = level is int
              ? level
              : int.tryParse(level.toString()) ?? 0;
          if (classLevel != _selectedClassLevel) return false;
        }
        // Sınıf tipi filtresi
        if (_selectedClassType != null) {
          final type = c['classTypeName'] as String?;
          if (type != _selectedClassType) return false;
        }
        return true;
      }).toList();
    });
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Icon(Icons.filter_list_rounded, color: Colors.purple.shade700),
              SizedBox(width: 12),
              Text('Filtrele', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Container(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFilterHeader('Sınıf Seviyesi'),
                SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildFilterChip(
                      label: 'Tümü',
                      selected: _selectedClassLevel == null,
                      onSelected: (selected) => setDialogState(() => _selectedClassLevel = null),
                    ),
                    ...(_availableClassLevels.toList()..sort()).map(
                      (level) => _buildFilterChip(
                        label: '$level. Sınıf',
                        selected: _selectedClassLevel == level,
                        onSelected: (selected) => setDialogState(() => _selectedClassLevel = selected ? level : null),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24),
                _buildFilterHeader('Sınıf Tipi'),
                SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildFilterChip(
                      label: 'Tümü',
                      selected: _selectedClassType == null,
                      onSelected: (selected) => setDialogState(() => _selectedClassType = null),
                    ),
                    ..._availableClassTypes.map(
                      (type) => _buildFilterChip(
                        label: type,
                        selected: _selectedClassType == type,
                        onSelected: (selected) => setDialogState(() => _selectedClassType = selected ? type : null),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actionsPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedClassLevel = null;
                  _selectedClassType = null;
                });
                _applyFilter();
                Navigator.pop(context);
              },
              child: Text('Temizle', style: TextStyle(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: () {
                _applyFilter();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                elevation: 0,
              ),
              child: Text('Uygula', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Colors.grey.shade800,
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required Function(bool) onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      selectedColor: Colors.purple.shade100,
      labelStyle: TextStyle(
        color: selected ? Colors.purple.shade900 : Colors.grey.shade700,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        fontSize: 13,
      ),
      backgroundColor: Colors.grey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? Colors.purple.shade200 : Colors.transparent,
        ),
      ),
      elevation: 0,
      pressElevation: 0,
      padding: EdgeInsets.symmetric(horizontal: 4),
    );
  }

  void _showPrintDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      backgroundColor: Colors.white,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.print_rounded, color: Colors.purple.shade700),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Yazdır / Dışa Aktar', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade900)),
                        Text(widget.periodData['periodName'] ?? '', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 32),
              _buildPrintOption(
                icon: Icons.class_rounded,
                color: Colors.blue,
                title: 'Tekli Sınıf Programı',
                subtitle: 'Sınıf seçerek PDF/Excel çıktısı alın',
                onPdf: () => _handlePrint('class_single', 'pdf'),
                onExcel: () => _handlePrint('class_single', 'excel'),
              ),
              _buildPrintOption(
                icon: Icons.person_rounded,
                color: Colors.orange,
                title: 'Tekli Öğretmen Programı',
                subtitle: 'Öğretmen seçerek PDF/Excel çıktısı alın',
                onPdf: () => _handlePrint('teacher_single', 'pdf'),
                onExcel: () => _handlePrint('teacher_single', 'excel'),
              ),
              _buildPrintOption(
                icon: Icons.grid_view_rounded,
                color: Colors.purple,
                title: 'Sınıf Çarşaf Listesi',
                subtitle: 'Tüm sınıfları toplu tablo olarak indir',
                onPdf: () => _handlePrint('class_master', 'pdf'),
                onExcel: () => _handlePrint('class_master', 'excel'),
              ),
              _buildPrintOption(
                icon: Icons.person_search_rounded,
                color: Colors.green,
                title: 'Öğretmen Çarşaf Listesi',
                subtitle: 'Tüm öğretmenleri toplu tablo olarak indir',
                onPdf: () => _handlePrint('teacher_master', 'pdf'),
                onExcel: () => _handlePrint('teacher_master', 'excel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrintOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onPdf,
    required VoidCallback onExcel,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 24),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey.shade900)),
                Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          _buildTinyPrintButton('PDF', Colors.red, onPdf),
          SizedBox(width: 8),
          _buildTinyPrintButton('EXCEL', Colors.green.shade700, onExcel),
        ],
      ),
    );
  }

  Widget _buildTinyPrintButton(String label, Color color, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      ),
    );
  }

  Future<void> _handlePrint(String type, String format) async {
    Navigator.pop(context);
    
    // Kurum bilgilerini sor ve kaydet
    final info = await _showInstitutionInfoDialog();
    if (info == null) return;

    try {
      final pdfService = PdfService();
      final excelService = ExcelService();

      if (type == 'class_single') {
        // Sınıf seçtir (Çoklu Seçim)
        final List<String> classNames = _classes.map((c) => c['className'] as String? ?? '').where((s) => s.isNotEmpty).toList();
        final selectedClassNames = await _showMultiSelectionDialog('Yazdırılacak Sınıfları Seçin', classNames, Icons.class_outlined);
        if (selectedClassNames == null || selectedClassNames.isEmpty) return;

        _showLoadingIndicator();

        // Her seçilen sınıf için veri hazırla
        List<Map<String, dynamic>> multiClassData = [];

        for (var className in selectedClassNames) {
          final targetClass = _classes.firstWhere((c) => c['className'] == className);
          final classId = targetClass['id'];

          Map<String, dynamic> scheduleData = {};
          Map<String, int> lessonCounts = {};
          Map<String, String> lessonTeachers = {};
          Map<String, String> lessonNameToShort = {};

          _scheduleData.forEach((key, data) {
            if (data['classId'] == classId) {
              final scheduleKey = '${data['day']}_${data['hourIndex']}';
              scheduleData[scheduleKey] = {
                'lessonName': data['lessonName'],
                'shortName': _lessonShortNames[data['lessonId']] ?? '',
                'teacherName': data['teacherName'],
              };
              lessonNameToShort[data['lessonName'] ?? ''] = _lessonShortNames[data['lessonId']] ?? '';
              final lessonName = data['lessonName'] as String?;
              if (lessonName != null) {
                lessonCounts[lessonName] = (lessonCounts[lessonName] ?? 0) + 1;
                lessonTeachers[lessonName] = data['teacherName'] ?? '';
              }
            }
          });

          final lessonStats = lessonCounts.entries.map((e) => {
            'lessonName': e.key,
            'shortName': lessonNameToShort[e.key] ?? '',
            'count': e.value,
            'teacherName': lessonTeachers[e.key],
          }).toList();

          multiClassData.add({
            'className': className,
            'scheduleData': scheduleData,
            'lessonStats': lessonStats,
          });
        }

        if (format == 'pdf') {
          final bytes = await pdfService.generateClassSchedulePdf(
            multiClassData: multiClassData,
            days: _days,
            lessonHours: _lessonHours,
            institutionInfo: info,
          );
          await Printing.sharePdf(bytes: bytes, filename: 'Sinif_Programlari.pdf');
        } else {
          // Excel için (Çoklu sayfalı excel servisi henüz yoksa ilkini atalım veya geliştirelim)
          await excelService.exportScheduleToExcel(
            title: '${selectedClassNames.first} Haftalık Ders Programı',
            days: _days,
            lessonHours: _lessonHours,
            scheduleData: multiClassData.first['scheduleData'],
            institutionInfo: info,
            fileName: 'Sinif_Programi',
          );
        }
      } else if (type == 'teacher_single') {
        // Öğretmen seçtir (Çoklu Seçim)
        final teachers = _scheduleData.values
            .map((e) => e['teacherName'] as String?)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
        
        if (teachers.isEmpty) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Henüz programda öğretmen atanmamış.')));
           return;
        }

        final selectedTeacherNames = await _showMultiSelectionDialog('Yazdırılacak Öğretmenleri Seçin', teachers, Icons.person_outline);
        if (selectedTeacherNames == null || selectedTeacherNames.isEmpty) return;

        _showLoadingIndicator();

        List<Map<String, dynamic>> multiTeacherData = [];

        for (var teacherName in selectedTeacherNames) {
          Map<String, dynamic> scheduleData = {};
          // İstatistikler için Key: "Ders Adı | Sınıf Adı"
          Map<String, int> lessonCounts = {};
          Map<String, String> lessonNameToShort = {};

          final Set<String> processedTeacherSlots = {};

          _scheduleData.forEach((key, data) {
            final tName = data['teacherName']?.toString();
            final tNames = (data['teacherIds'] as List?)?.map((e) => e.toString()).toList();
            if (tName == teacherName || (tNames != null && tNames.contains(teacherName))) {
              final scheduleKey = '${data['day']}_${data['hourIndex']}';
              final resolvedClassName = _resolveClassName(data);
              scheduleData[scheduleKey] = {
                'lessonName': data['lessonName'],
                'shortName': _lessonShortNames[data['lessonId']] ?? '',
                'className': resolvedClassName,
              };
              
              if (!processedTeacherSlots.contains(scheduleKey)) {
                processedTeacherSlots.add(scheduleKey);
                final lessonName = data['lessonName'] as String?;
                final className = resolvedClassName;
                if (lessonName != null) {
                  final statsKey = '$lessonName|$className';
                  lessonCounts[statsKey] = (lessonCounts[statsKey] ?? 0) + 1;
                  lessonNameToShort[lessonName] = _lessonShortNames[data['lessonId']] ?? '';
                }
              }
            }
          });

          final lessonStats = lessonCounts.entries.map((e) {
            final parts = e.key.split('|');
            final lName = parts[0];
            final cName = parts[1];
            return {
              'lessonName': lName,
              'shortName': lessonNameToShort[lName] ?? '',
              'count': e.value,
              'className': cName,
            };
          }).toList();

          multiTeacherData.add({
            'teacherName': teacherName,
            'scheduleData': scheduleData,
            'lessonStats': lessonStats,
          });
        }

        if (format == 'pdf') {
          final bytes = await pdfService.generateTeacherSchedulePdf(
            multiTeacherData: multiTeacherData,
            days: _days,
            lessonHours: _lessonHours,
            institutionInfo: info,
          );
          await Printing.sharePdf(bytes: bytes, filename: 'Ogretmen_Programlari.pdf');
        } else {
          // Excel için master yapısını kullanalım
          List<Map<String, dynamic>> rows = multiTeacherData.map((e) => {
            'name': e['teacherName'],
            'scheduleData': e['scheduleData'],
          }).toList();

          await excelService.exportMasterScheduleToExcel(
            days: _days,
            lessonHours: _lessonHours,
            rows: rows,
            institutionInfo: info,
            typeLabel: 'Öğretmen Programı',
            fileName: 'Ogretmen_Programi',
          );
        }
      } else if (type == 'class_master' || type == 'teacher_master') {
        _showLoadingIndicator();
        List<Map<String, dynamic>> masterRows = [];

        if (type == 'class_master') {
          for (var cls in _classes) {
            final classId = cls['id'];
            Map<String, dynamic> rowSchedule = {};
            
            _scheduleData.forEach((key, data) {
              if (data != null && data['classId'] == classId) {
                final scheduleKey = '${data['day']}_${data['hourIndex']}';
                rowSchedule[scheduleKey] = {
                  'lessonName': data['lessonName'],
                  'shortName': _lessonShortNames[data['lessonId']] ?? '',
                  'teacherName': data['teacherName'],
                };
              }
            });

            masterRows.add({
              'name': cls['className'] ?? 'Sınıf',
              'scheduleData': rowSchedule,
            });
          }
        } else {
          // Öğretmen bazlı gruplandırma
          Map<String, Map<String, dynamic>> teacherSchedules = {};
          _scheduleData.forEach((key, data) {
            if (data == null) return;
            final teacherName = data['teacherName'] ?? 'Bilinmeyen';
            final scheduleKey = '${data['day']}_${data['hourIndex']}';
            
            if (!teacherSchedules.containsKey(teacherName)) {
              teacherSchedules[teacherName] = {};
            }
            teacherSchedules[teacherName]![scheduleKey] = {
              'lessonName': data['lessonName'],
              'shortName': _lessonShortNames[data['lessonId']] ?? '',
              'className': _resolveClassName(data),
            };
          });

          teacherSchedules.forEach((name, schedule) {
            masterRows.add({'name': name, 'scheduleData': schedule});
          });
        }

        if (format == 'pdf') {
          final bytes = await pdfService.generateMasterSchedulePdf(
            days: _days,
            lessonHours: _lessonHours,
            rows: masterRows,
            institutionInfo: info,
            typeLabel: type == 'class_master' ? 'Sınıflar' : 'Öğretmenler',
          );
          await Printing.sharePdf(bytes: bytes, filename: 'Carsaf_Liste.pdf');
        } else {
          await excelService.exportMasterScheduleToExcel(
            days: _days,
            lessonHours: _lessonHours,
            rows: masterRows,
            institutionInfo: info,
            typeLabel: type == 'class_master' ? 'Sınıflar' : 'Öğretmenler',
            fileName: 'Carsaf_Liste',
          );
        }
      }

      if (mounted && Navigator.canPop(context)) Navigator.pop(context); // Yükleniyor'u kapat
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  void _showLoadingIndicator() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }

  Future<List<String>?> _showMultiSelectionDialog(
      String title, List<String> items, IconData icon) async {
    
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return Navigator.push<List<String>>(
        context,
        MaterialPageRoute(
          builder: (context) => FullSelectionPage(title: title, items: items, icon: icon),
          fullscreenDialog: true,
        ),
      );
    }

    return showDialog<List<String>>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: _MultiSelectionContent(
          title: title,
          items: items,
          icon: icon,
          isDialog: true,
        ),
      ),
    );
  }

  Future<Map<String, String>?> _showInstitutionInfoDialog() async {
    final schoolTypeDoc = await FirebaseFirestore.instance.collection('schoolTypes').doc(widget.schoolTypeId).get();
    final savedInfo = Map<String, dynamic>.from(schoolTypeDoc.data()?['institutionalInfo'] ?? {});

    final cityCtrl = TextEditingController(text: savedInfo['city'] ?? 'Ankara');
    final districtCtrl = TextEditingController(text: savedInfo['district'] ?? 'Etimesgut');
    final schoolCtrl = TextEditingController(text: savedInfo['schoolName'] ?? 'ABC Ortaokulu');
    final principalCtrl = TextEditingController(text: savedInfo['principalName'] ?? 'Zafer Yaz');

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.business_rounded, color: Colors.blue),
            SizedBox(width: 12),
            Text('Yazdırma Bilgileri', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModernField(cityCtrl, 'İl', Icons.location_city),
              SizedBox(height: 16),
              _buildModernField(districtCtrl, 'İlçe', Icons.map),
              SizedBox(height: 16),
              _buildModernField(schoolCtrl, 'Okul Adı', Icons.school),
              SizedBox(height: 16),
              _buildModernField(principalCtrl, 'Okul Müdürü', Icons.person),
              SizedBox(height: 20),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bu bilgiler her okul türü için kaydedilir.', 
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade800)
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actionsPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('İptal', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, {
              'city': cityCtrl.text,
              'district': districtCtrl.text,
              'schoolName': schoolCtrl.text,
              'principalName': principalCtrl.text,
            }),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text('Kaydet ve Devam Et', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result != null) {
      // Bilgileri Firestore'a kaydet
      await FirebaseFirestore.instance
          .collection('schoolTypes')
          .doc(widget.schoolTypeId)
          .set({'institutionalInfo': result}, SetOptions(merge: true));
    }
    
    return result;
  }

  Widget _buildModernField(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: Colors.grey.shade600),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.blue, width: 2)),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  void _showCopyToAnotherPeriodDialog() async {
    // Diğer dönemleri yükle (aynı akademik döneme ait alt dönemler)
    final periodsSnapshot = await FirebaseFirestore.instance
        .collection('workPeriods')
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('termId', isEqualTo: widget.periodData['termId'])
        .where('isActive', isEqualTo: true)
        .get();

    final periods = periodsSnapshot.docs
        .where((doc) => doc.id != widget.periodId)
        .toList();

    if (periods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kopyalanacak başka dönem bulunamadı')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.copy, color: Colors.blue),
            SizedBox(width: 12),
            Text('Programı Kopyala'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ders programını hangi döneme kopyalamak istiyorsunuz?',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              SizedBox(height: 16),
              ...periods.map((doc) {
                final data = doc.data();
                return ListTile(
                  leading: Icon(Icons.calendar_today, color: Colors.purple),
                  title: Text(data['periodName'] ?? 'İsimsiz Dönem'),
                  onTap: () {
                    Navigator.pop(context);
                    _copyScheduleToPeriod(
                      doc.id,
                      data['periodName'] ?? 'Dönem',
                    );
                  },
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyScheduleToPeriod(
    String targetPeriodId,
    String targetPeriodName,
  ) async {
    try {
      // Mevcut programı al
      final currentSchedule = _scheduleData.values.toList();

      if (currentSchedule.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kopyalanacak program bulunamadı')),
        );
        return;
      }

      // Hedef dönemdeki mevcut programı sil
      final existingSchedule = await FirebaseFirestore.instance
          .collection('classSchedules')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('periodId', isEqualTo: targetPeriodId)
          .get();

      final batch = FirebaseFirestore.instance.batch();

      for (var doc in existingSchedule.docs) {
        batch.delete(doc.reference);
      }

      // Yeni programı ekle
      for (var schedule in currentSchedule) {
        final newDocRef = FirebaseFirestore.instance
            .collection('classSchedules')
            .doc();
        batch.set(newDocRef, {
          'classId': schedule['classId'],
          'day': schedule['day'],
          'hourIndex': schedule['hourIndex'],
          'lessonId': schedule['lessonId'],
          'lessonName': schedule['lessonName'],
          'className': schedule['className'],
          'teacherId': schedule['teacherId'],
          'teacherName': schedule['teacherName'],
          'periodId': targetPeriodId,
          'schoolTypeId': widget.schoolTypeId,
          'institutionId': widget.institutionId,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Program "$targetPeriodName" dönemine kopyalandı'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kopyalama hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showLessonPicker(String classId, String day, int hourIndex) {
    final lessons = _classLessons[classId] ?? [];
    final key = '${classId}_${day}_$hourIndex';
    final currentAssignment = _scheduleData[key];

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 300,
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.book, color: Colors.purple),
                  SizedBox(width: 8),
                  Text(
                    'Ders Seç',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Divider(),
              if (lessons.isEmpty)
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'Bu şubeye atanmış ders yok',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ...lessons.map((lesson) {
                  final lessonKey = '${classId}_${lesson['lessonId']}';
                  final remaining = _remainingHours[lessonKey] ?? 0;
                  final lessonName = lesson['lessonName'] ?? '';
                  final isSelected =
                      currentAssignment != null &&
                      currentAssignment['lessonId'] == lesson['lessonId'];

                  return ListTile(
                    dense: true,
                    selected: isSelected,
                    selectedTileColor: Colors.purple.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: remaining > 0
                          ? Colors.purple.shade100
                          : Colors.grey.shade200,
                      child: Text(
                        lessonName.isNotEmpty
                            ? lessonName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: remaining > 0 ? Colors.purple : Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    title: Text(
                      lessonName,
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    trailing: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: remaining > 0
                            ? Colors.green.shade100
                            : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '($remaining)',
                        style: TextStyle(
                          color: remaining > 0
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    onTap: remaining > 0 || isSelected
                        ? () => _assignLesson(
                            classId,
                            day,
                            hourIndex,
                            lesson,
                            _classes.firstWhere(
                              (c) => c['id'] == classId,
                              orElse: () => {'className': 'Sınıf'},
                            )['className'],
                            closePicker: true,
                          )
                        : null,
                  );
                }),
              SizedBox(height: 8),
              if (currentAssignment != null)
                TextButton.icon(
                  onPressed: () => _removeAssignment(classId, day, hourIndex),
                  icon: Icon(Icons.delete_outline, color: Colors.red),
                  label: Text(
                    'Dersi Kaldır',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _assignLesson(
    String classId,
    String day,
    int hourIndex,
    Map<String, dynamic> lesson,
    String className, {
    bool closePicker = false,
  }) async {
    final lessonName = (lesson['lessonName'] ?? '').toString().trim();
    final teacherIds = lesson['teacherIds'] as List<dynamic>?;
    final teacherNames = lesson['teacherNames'] as List<dynamic>?;
    final teacherId = (teacherIds != null && teacherIds.isNotEmpty)
        ? teacherIds.first?.toString()
        : null;
    final teacherName = (teacherNames != null && teacherNames.isNotEmpty)
        ? teacherNames.first?.toString() ?? 'Öğretmen'
        : 'Öğretmen';

    final slotKey = '${day}_$hourIndex';

    // KAPALI SAAT KONTROLÜ - Şube ve Öğretmen Kapalı saatlerini KESİNLİKLE ENGELLER
    if (_closedSlots['class_$classId']?.contains(slotKey) == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$className sınıfının $day $hourIndex. saati kapalıdır! Ders atanamaz.'),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 3),
        ),
      );
      if (closePicker) Navigator.pop(context);
      return;
    }

    if (teacherId != null && _closedSlots['teacher_$teacherId']?.contains(slotKey) == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$teacherName öğretmeninin $day $hourIndex. saati kapalı olarak işaretlenmiştir! Kapatılan saate ders atanamaz.'),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 3),
        ),
      );
      if (closePicker) Navigator.pop(context);
      return;
    }

    // Birleştirilmiş sınıfları kontrol et
    List<String> targetClassIds = [classId];
    for (var merge in _lessonClassMerges) {
      final mName = (merge['lessonName'] ?? '').toString().trim();
      final mClassIds = List<String>.from(merge['classIds'] ?? []);
      if (mName.toLowerCase() == lessonName.toLowerCase() && mClassIds.contains(classId)) {
        targetClassIds = mClassIds;
        break;
      }
    }

    // Öğretmen çakışma kontrolü (birleştirilmiş sınıflar haricindeki diğer derslerle)
    if (teacherId != null) {
      for (var entry in _scheduleData.entries) {
        final data = entry.value;
        if (data['day'] == day && data['hourIndex'] == hourIndex) {
          final assignedClassId = data['classId']?.toString();
          if (data['teacherId'] == teacherId && !targetClassIds.contains(assignedClassId)) {
            final conflictClassName = _classes.firstWhere(
              (c) => c['id'] == assignedClassId,
              orElse: () => {'className': 'Bilinmeyen'},
            )['className'];

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '$teacherName bu saatte $conflictClassName sınıfında ders veriyor!',
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
            if (closePicker) Navigator.pop(context);
            return;
          }
        }
      }
    }

    // Öğretmen günlük ders limiti kontrolü ve uyarısı (Birleştirilmiş sınıflar tek ders saati sayılır)
    if (teacherId != null) {
      final Set<int> teacherDailySlots = {};
      for (var entry in _scheduleData.values) {
        if (entry['day'] == day) {
          final tId = entry['teacherId']?.toString();
          final tIds = (entry['teacherIds'] as List?)?.map((e) => e.toString()).toList();
          if (tId == teacherId || (tIds != null && tIds.contains(teacherId))) {
            final h = entry['hourIndex'] is int
                ? entry['hourIndex'] as int
                : int.tryParse(entry['hourIndex'].toString()) ?? -1;
            if (h >= 0) teacherDailySlots.add(h);
          }
        }
      }
      final currentDailyCount = teacherDailySlots.length;

      final dayMax = _dailyLessonCounts[day] ?? 8;
      final maxLimit = _teacherMaxDailyHours[teacherId] ?? (dayMax > 1 ? dayMax - 1 : dayMax);

      if (currentDailyCount >= maxLimit) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                const Text('Ders Limiti Uyarısı', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              '$teacherName öğretmeninin $day günü için tanımlanan günlük ders limiti ($maxLimit saat) dolmuştur.\nŞu an $day gününe $currentDailyCount saat ders atanmış durumdadır.\n\nYine de devam edip bu dersi eklemek istiyor musunuz?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Yine de Atansın', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );

        if (proceed != true) {
          return;
        }
      }
    }

    if (closePicker) {
      Navigator.pop(context);
    }

    // Her hedef (birleştirilmiş) sınıf için atamayı gerçekleştir
    final syncService = ClassScheduleSyncService();

    for (var targetCId in targetClassIds) {
      final key = '${targetCId}_${day}_$hourIndex';
      final lessonKey = '${targetCId}_${lesson['lessonId']}';
      final oldAssignment = _scheduleData[key];

      // Zaten aynı ders atanmışsa atla
      if (oldAssignment != null && oldAssignment['lessonId'] == lesson['lessonId']) {
        continue;
      }

      // Eski atamayı kaldır (varsa)
      if (oldAssignment != null) {
        final oldLessonKey = '${targetCId}_${oldAssignment['lessonId']}';
        _remainingHours[oldLessonKey] = (_remainingHours[oldLessonKey] ?? 0) + 1;
        if (oldAssignment['id'] != null) {
          try {
            await FirebaseFirestore.instance
                .collection('classSchedules')
                .doc(oldAssignment['id'])
                .delete();
          } catch (e) {
            print('⚠️ Eski atama silinemedi: $e');
          }
        }
      }

      final targetClassName = _classes.firstWhere(
        (c) => c['id'] == targetCId,
        orElse: () => {'className': targetCId},
      )['className'];

      setState(() {
        _scheduleData[key] = {
          'classId': targetCId,
          'day': day,
          'hourIndex': hourIndex,
          'lessonId': lesson['lessonId'],
          'lessonName': lessonName,
          'className': targetClassName,
          'teacherId': teacherId,
          'teacherName': teacherName,
        };
        _remainingHours[lessonKey] = (_remainingHours[lessonKey] ?? 1) - 1;
      });

      try {
        await syncService.syncLessonAssignment(
          institutionId: widget.institutionId,
          periodId: widget.periodId,
          classId: targetCId,
          className: targetClassName,
          day: day,
          hourIndex: hourIndex,
          lessonId: lesson['lessonId'],
          lessonName: lessonName,
          teacherIds: teacherIds?.map((e) => e.toString()).toList() ?? [],
        );
      } catch (e) {
        print('⚠️ Ders senkronize edilemedi (Firestore): $e');
      }
    }
  }

  Future<void> _removeAssignment(
    String classId,
    String day,
    int hourIndex,
  ) async {
    final key = '${classId}_${day}_$hourIndex';
    final assignment = _scheduleData[key];

    if (assignment == null) {
      Navigator.pop(context);
      return;
    }

    final lessonName = (assignment['lessonName'] ?? '').toString().trim();

    // Birleştirilmiş sınıfları kontrol et
    List<String> targetClassIds = [classId];
    for (var merge in _lessonClassMerges) {
      final mName = (merge['lessonName'] ?? '').toString().trim();
      final mClassIds = List<String>.from(merge['classIds'] ?? []);
      if (mName.toLowerCase() == lessonName.toLowerCase() && mClassIds.contains(classId)) {
        targetClassIds = mClassIds;
        break;
      }
    }

    Navigator.pop(context);

    final syncService = ClassScheduleSyncService();

    for (var targetCId in targetClassIds) {
      final targetKey = '${targetCId}_${day}_$hourIndex';
      final targetAssignment = _scheduleData[targetKey];

      if (targetAssignment != null) {
        final lessonKey = '${targetCId}_${targetAssignment['lessonId']}';

        setState(() {
          _scheduleData.remove(targetKey);
          _remainingHours[lessonKey] = (_remainingHours[lessonKey] ?? 0) + 1;
        });

        try {
          await syncService.removeLessonAssignment(
            periodId: widget.periodId,
            classId: targetCId,
            day: day,
            hourIndex: hourIndex,
          );
        } catch (e) {
          print('⚠️ Ders silinemedi (Firestore): $e');
        }
      }
    }
  }

  Future<void> _showScheduleSettings() async {
    final result = await showModalBottomSheet<ScheduleSettings>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ScheduleSettingsPanel(
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        periodId: widget.periodId,
        periodData: widget.periodData,
        initialSettings: ScheduleSettings(
          lessonBlockPatterns: Map.from(_lessonBlockPatterns),
          lessonAllowSplit: Map.from(_lessonAllowSplit),
          lessonAvoidFirstHour: Map.from(_lessonAvoidFirstHour),
          lessonAvoidLastHour: Map.from(_lessonAvoidLastHour),
          lessonClassMerges: List.from(_lessonClassMerges),
          closedSlots: Map.fromEntries(
            _closedSlots.entries.map((e) => MapEntry(e.key, Set.from(e.value))),
          ),
          teacherMaxDailyHours: Map.from(_teacherMaxDailyHours),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _lessonBlockPatterns = result.lessonBlockPatterns;
        _lessonAllowSplit = result.lessonAllowSplit;
        _lessonAvoidFirstHour = result.lessonAvoidFirstHour;
        _lessonAvoidLastHour = result.lessonAvoidLastHour;
        _lessonClassMerges = result.lessonClassMerges;
        _closedSlots = result.closedSlots;
        _teacherMaxDailyHours = result.teacherMaxDailyHours;
      });

      // Firestore'a kalıcı olarak kaydet!
      try {
        await FirebaseFirestore.instance
            .collection('workPeriods')
            .doc(widget.periodId)
            .set({
          'scheduleSettings': {
            'lessonBlockPatterns': result.lessonBlockPatterns,
            'lessonAllowSplit': result.lessonAllowSplit,
            'lessonAvoidFirstHour': result.lessonAvoidFirstHour,
            'lessonAvoidLastHour': result.lessonAvoidLastHour,
            'lessonClassMerges': result.lessonClassMerges,
            'closedSlots':
                result.closedSlots.map((k, v) => MapEntry(k, v.toList())),
            'teacherMaxDailyHours': result.teacherMaxDailyHours,
          }
        }, SetOptions(merge: true));
        print('💾 Dağıtım ayarları Firestore\'a kalıcı kaydedildi!');
      } catch (e) {
        print('⚠️ Dağıtım ayarları Firestore\'a kaydedilemedi: $e');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Dağıtım ayarları kalıcı olarak kaydedildi!'),
          backgroundColor: Colors.indigo.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _clearSchedule() async {
    // Adım 1: Genel onay
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 12),
            Text('Programı Temizle'),
          ],
        ),
        content: Text('Mevcut ders programı temizlenecek. Devam etmek istiyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Devam', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // Adım 2: Manuel girişler de silinsin mi?
    bool deleteManual = false;
    if (mounted) {
      final manualConfirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.pan_tool_rounded, color: Colors.orange),
              SizedBox(width: 12),
              Text('Manuel Yerleşimler'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Otomatik dağıtım öncesinde manuel olarak yaptığınız yerleşimler var.',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 8),
              Text(
                'Bu manuel girişler de silinsin mi?',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Hayır, Sadece Otomatikleri Sil', style: TextStyle(color: Colors.green.shade700)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: Text('Evet, Hepsini Sil', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      deleteManual = manualConfirm == true;
    }

    setState(() => _isLoading = true);
    try {
      final allDocs = await FirebaseFirestore.instance
          .collection('classSchedules')
          .where('periodId', isEqualTo: widget.periodId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      int deletedCount = 0;
      int keptCount = 0;
      for (var doc in allDocs.docs) {
        final isAuto = doc.data()['isAutoDistributed'] == true;
        if (deleteManual || isAuto) {
          batch.delete(doc.reference);
          deletedCount++;
        } else {
          keptCount++;
        }
      }
      await batch.commit();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(keptCount > 0
                ? '$deletedCount atama silindi. $keptCount manuel yerleşim korundu.'
                : 'Tüm program temizlendi.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _autoDistributeSchedule() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.smart_toy_rounded, color: Colors.orange.shade800),
            ),
            const SizedBox(width: 12),
            const Text('Otomatik Ders Dağıtımı', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Otomatik dağıtım algoritması (Monte Carlo simülasyonu) çalıştırılarak dersler yerleştirilecektir.',
            ),
            const SizedBox(height: 12),
            Text(
              '📌 Elle yapılan yerleşimler korunacak, birleştirilmiş dersler ve öğretmen günlük ders limitleri dikkate alınacaktır.',
              style: TextStyle(color: Colors.indigo.shade800, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dağıtımı Başlat', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Show Animated Progress Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 54,
                height: 54,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.orange.shade800),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Otomatik Dağıtım Yapılıyor...',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Simülasyonlar çalıştırılıyor ve öğretmen kısıtları hesaplanıyor...',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final service = AutoScheduleService();
      final result = await service.distributeSchedule(
        periodId: widget.periodId,
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        lessonBlockPatterns: _lessonBlockPatterns.isNotEmpty ? _lessonBlockPatterns : null,
        lessonAllowSplit: _lessonAllowSplit.isNotEmpty ? _lessonAllowSplit : null,
        lessonAvoidFirstHour: _lessonAvoidFirstHour.isNotEmpty ? _lessonAvoidFirstHour : null,
        lessonAvoidLastHour: _lessonAvoidLastHour.isNotEmpty ? _lessonAvoidLastHour : null,
        lessonClassMerges: _lessonClassMerges.isNotEmpty ? _lessonClassMerges : null,
        closedSlots: _closedSlots.isNotEmpty ? _closedSlots : null,
        teacherMaxDailyHours: _teacherMaxDailyHours.isNotEmpty ? _teacherMaxDailyHours : null,
      );

      // Dismiss Progress Dialog
      if (mounted) Navigator.pop(context);

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(
                  result.unassignedCount == 0 ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                  color: result.unassignedCount == 0 ? Colors.green.shade700 : Colors.orange.shade800,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(
                  result.unassignedCount == 0 ? 'Dağıtım Başarılı!' : 'Dağıtım Tamamlandı',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: result.unassignedCount == 0 ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '✅ ${result.assignedCount} saat ders yerleştirildi.',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: result.unassignedCount == 0 ? Colors.green.shade900 : Colors.orange.shade900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (result.unassignedCount > 0) ...[
                    const SizedBox(height: 14),
                    Text(
                      '⚠️ ${result.unassignedCount} adet ders bloğu yerleştirilemedi:',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: result.unassignedDetails.map((detail) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Expanded(
                                    child: Text(
                                      detail,
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '💡 Tavsiye: Dağıtım ayarlarından öğretmen kapalı saatlerini azaltabilir veya öğretmen günlük limitlerini artırabilirsiniz.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade700,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Tamam', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );

        _loadData();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _clearAllSchedule() async {
    // Adım 1: Genel onay
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 12),
            Text('Programı Temizle'),
          ],
        ),
        content: Text(
          'Bu dönemdeki ders programı temizlenecek. Devam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Devam', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // Adım 2: Manuel girişler de silinsin mi?
    bool deleteManual = false;
    if (mounted) {
      final manualConfirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.pan_tool_rounded, color: Colors.orange),
              SizedBox(width: 12),
              Text('Manuel Yerleşimler'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Otomatik dağıtım öncesinde manuel olarak yaptığınız yerleşimler var.',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 8),
              Text(
                'Bu manuel girişler de silinsin mi?\n'
                '• Hayır → Sadece otomatik dağıtılan dersler silinir, manuel yerleşimleriniz korunur.\n'
                '• Evet → Tüm program (manuel dahil) sıfırlanır.',
                style: TextStyle(color: Colors.grey.shade700, height: 1.5),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Hayır, Sadece Otomatikleri Sil',
                  style: TextStyle(color: Colors.green.shade700)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: Text('Evet, Hepsini Sil', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      deleteManual = manualConfirm == true;
    }

    setState(() => _isLoading = true);
    try {
      final scheduleSnapshot = await FirebaseFirestore.instance
          .collection('classSchedules')
          .where('periodId', isEqualTo: widget.periodId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      // Batch silme (500'er işlem limiti)
      List<WriteBatch> batches = [];
      WriteBatch currentBatch = FirebaseFirestore.instance.batch();
      int opCount = 0;
      int deletedCount = 0;
      int keptCount = 0;

      for (var doc in scheduleSnapshot.docs) {
        final isAuto = doc.data()['isAutoDistributed'] == true;
        if (deleteManual || isAuto) {
          currentBatch.delete(doc.reference);
          deletedCount++;
          opCount++;
          if (opCount >= 450) {
            batches.add(currentBatch);
            currentBatch = FirebaseFirestore.instance.batch();
            opCount = 0;
          }
        } else {
          keptCount++;
        }
      }
      batches.add(currentBatch);
      for (var b in batches) await b.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(keptCount > 0
                ? '$deletedCount atama silindi. $keptCount manuel yerleşim korundu.'
                : 'Tüm program temizlendi.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final periodName = widget.periodData['periodName'] ?? 'Ders Programı';

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.purple),
          onPressed: widget.onBack,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ders Programı',
              style: TextStyle(
                color: Colors.grey.shade900,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              periodName,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
        actions: [
          // Filtre butonu
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: (_selectedClassLevel != null || _selectedClassType != null)
                  ? Colors.purple
                  : Colors.grey.shade700,
            ),
            onPressed: _showFilterDialog,
            tooltip: 'Filtrele',
          ),
          // Yazdır butonu
          IconButton(
            icon: Icon(Icons.print, color: Colors.purple),
            onPressed: _showPrintDialog,
            tooltip: 'Yazdır',
          ),
          // 3 nokta menüsü (kopyala vb.)
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.grey.shade700),
            onSelected: (value) {
              if (value == 'copy') {
                _showCopyToAnotherPeriodDialog();
              } else if (value == 'clear') {
                _clearSchedule();
              } else if (value == 'settings') {
                _showScheduleSettings();
              } else if (value == 'auto_distribute') {
                _autoDistributeSchedule();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Text('Başka Döneme Kopyala'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('Programı Temizle'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, color: Colors.indigo, size: 20),
                    SizedBox(width: 8),
                    Text('Dağıtım Ayarları'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'auto_distribute',
                child: Row(
                  children: [
                    Icon(Icons.smart_toy, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Text('Otomatik Dağıt'),
                  ],
                ),
              ),
            ],
          ),
          if (widget.isViewingPastTerm)
            Container(
              margin: EdgeInsets.only(right: 8),
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 14, color: Colors.orange.shade700),
                  SizedBox(width: 4),
                  Text(
                    'Geçmiş',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildViewModeToggle(),
                    Expanded(child: _buildScheduleGrid()),
                    _buildUnassignedLessonsBar(),
                  ],
                ),
    );
  }

  Widget _buildViewModeToggle() {
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildToggleItem(
                  'Sınıf Programı',
                  Icons.class_rounded,
                  !_isTeacherView,
                  () => setState(() => _isTeacherView = false),
                ),
                _buildToggleItem(
                  'Öğretmen Programı',
                  Icons.person_rounded,
                  _isTeacherView,
                  () => setState(() => _isTeacherView = true),
                ),
              ],
            ),
          ),
          if (_selectedUnassignedLesson != null) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.touch_app_rounded, size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Seçili: ${_selectedUnassignedLesson!['lessonName']} (${_selectedUnassignedLesson!['className']}) → Yeşil saatlere dokunun',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade900,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 14),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _selectedUnassignedLesson = null),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToggleItem(
    String title,
    IconData icon,
    bool active,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? Colors.indigo.shade700 : Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
                color: active ? Colors.indigo.shade900 : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getUnassignedLessons() {
    final List<Map<String, dynamic>> result = [];
    for (var entry in _classLessons.entries) {
      final classId = entry.key;
      final className = _classes.firstWhere(
        (c) => c['id'] == classId,
        orElse: () => {'className': 'Sınıf'},
      )['className'] as String;

      for (var lesson in entry.value) {
        final lessonKey = '${classId}_${lesson['lessonId']}';
        final remaining = _remainingHours[lessonKey] ?? 0;
        if (remaining > 0) {
          result.add({
            ...lesson,
            'classId': classId,
            'className': className,
            'remainingHours': remaining,
          });
        }
      }
    }
    result.sort((a, b) => (b['remainingHours'] as int).compareTo(a['remainingHours'] as int));
    return result;
  }

  Widget _buildUnassignedLessonsBar() {
    final unassigned = _getUnassignedLessons();
    if (unassigned.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade800),
              const SizedBox(width: 6),
              Text(
                'Yerleşemeyen Dersler (${unassigned.length} Ders)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '• Dokunup yerleşebileceği yeşil saatleri görün',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: unassigned.length,
                itemBuilder: (context, idx) {
                final item = unassigned[idx];
                final isSelected = _selectedUnassignedLesson != null &&
                    _selectedUnassignedLesson!['classId'] == item['classId'] &&
                    _selectedUnassignedLesson!['lessonId'] == item['lessonId'];
                final remaining = item['remainingHours'] as int;
                final lessonName = item['lessonName'] as String? ?? 'Ders';
                final className = item['className'] as String? ?? '';
                final teacherName = (item['teacherNames'] as List?)?.isNotEmpty == true
                    ? item['teacherNames'][0]
                    : (item['teacherName'] ?? '');

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedUnassignedLesson = null;
                      } else {
                        _selectedUnassignedLesson = item;
                      }
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.green.shade50 : Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? Colors.green.shade500 : Colors.indigo.shade200,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: isSelected ? Colors.green.shade200 : Colors.indigo.shade100,
                              child: Text(
                                lessonName.isNotEmpty ? lessonName[0].toUpperCase() : '?',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.green.shade800 : Colors.indigo.shade800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  lessonName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.green.shade900 : Colors.grey.shade900,
                                  ),
                                ),
                                Text(
                                  '$className • $teacherName',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isSelected ? Colors.green.shade700 : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 14),
                          ],
                        ),
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.green.shade600 : Colors.red.shade600,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                            child: Center(
                              child: Text(
                                '$remaining',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.class_, size: 64, color: Colors.grey.shade400),
          SizedBox(height: 16),
          Text(
            'Henüz şube tanımlanmamış',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'Önce şube ekleyin',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleGrid() {
    if (_lessonHours.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time, size: 64, color: Colors.orange.shade300),
            const SizedBox(height: 16),
            Text(
              'Bu dönem için ders saati tanımlanmamış',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Önce "Ders Saatleri" bölümünden ders saatlerini tanımlayın',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final cellWidth = 50.0;
    final cellHeight = 38.0;
    final headerHeight = 60.0;
    final rowHeaderWidth = _isTeacherView ? 115.0 : 65.0;
    final rows = _isTeacherView ? _teachers : _classes;

    int getHourCountForDay(String day) {
      return _dailyLessonCounts[day] ?? _lessonHours.length;
    }

    double totalWidth = 0;
    for (var day in _days) {
      totalWidth += getHourCountForDay(day) * cellWidth + 2;
    }

    // Seçili yerleşemeyen ders bilgileri
    final targetClassId = _selectedUnassignedLesson?['classId']?.toString();
    final targetClassName = _selectedUnassignedLesson?['className']?.toString();
    final targetTeacherId = _selectedUnassignedLesson?['teacherId']?.toString();
    final targetTeacherIds = (_selectedUnassignedLesson?['teacherIds'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        (targetTeacherId != null ? [targetTeacherId] : []);

    return Row(
      children: [
        // Sol sütun - Şube veya Öğretmen başlığı ve isimleri
        Column(
          children: [
            Container(
              width: rowHeaderWidth,
              height: headerHeight,
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                border: Border(
                  right: BorderSide(color: Colors.grey.shade300),
                  bottom: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Center(
                child: Text(
                  _isTeacherView ? 'Öğretmen' : 'Şube',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.purple.shade700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Container(
                width: rowHeaderWidth,
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(
                    right: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: ListView.builder(
                  controller: _verticalScrollController,
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final rowData = rows[index];
                    final name = _isTeacherView
                        ? (rowData['name'] ?? 'Öğretmen')
                        : (rowData['className'] ?? 'Sınıf');

                    return Container(
                      height: cellHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: index % 2 == 0
                            ? Colors.white
                            : Colors.grey.shade50,
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            color: Colors.grey.shade800,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),

        // Sağ taraf - Günler/saatler ve program hücreleri
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
            ),
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                child: Column(
                  children: [
                    // Üst başlık satırı (Günler ve Saatler)
                    Container(
                      height: headerHeight,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: Row(
                        children: _days.map((day) {
                          final dayHourCount = getHourCountForDay(day);
                          return Container(
                            width: dayHourCount * cellWidth + 2,
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                  color: Colors.grey.shade300,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: Colors.purple.shade100,
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.purple.shade200,
                                      ),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      day,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purple.shade800,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Row(
                                    children: List.generate(dayHourCount, (hourIndex) {
                                      final dayHours = _dayLessonTimes[day] ?? _lessonHours;
                                      final hour = hourIndex < dayHours.length ? dayHours[hourIndex] : null;
                                      final startTime = hour?['startTime'] ?? '';
                                      final hourNumber = hourIndex + 1;
                                      return Container(
                                        width: cellWidth,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade50,
                                          border: Border(
                                            right: BorderSide(
                                              color: Colors.grey.shade200,
                                            ),
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              startTime.toString(),
                                              style: TextStyle(
                                                fontSize: 8,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                            Text(
                                              '$hourNumber',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 10,
                                                color: Colors.grey.shade800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    // Program Hücreleri
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is ScrollUpdateNotification) {
                            if (_verticalScrollController.hasClients) {
                              _verticalScrollController.jumpTo(
                                notification.metrics.pixels,
                              );
                            }
                          }
                          return true;
                        },
                        child: ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (context, rowIndex) {
                            final rowData = rows[rowIndex];
                            final rowId = rowData['id'] as String;

                            return Container(
                              height: cellHeight,
                              decoration: BoxDecoration(
                                color: rowIndex % 2 == 0
                                    ? Colors.white
                                    : Colors.grey.shade50,
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: _days.map((day) {
                                  final dayHourCount = getHourCountForDay(day);
                                  return Container(
                                    width: dayHourCount * cellWidth + 2,
                                    decoration: BoxDecoration(
                                      border: Border(
                                        right: BorderSide(
                                          color: Colors.grey.shade300,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: List.generate(dayHourCount, (hourIndex) {
                                        // Hücre atamasını bul
                                        Map<String, dynamic>? assignment;
                                        if (!_isTeacherView) {
                                          assignment = _scheduleData['${rowId}_${day}_$hourIndex'];
                                        } else {
                                          for (var data in _scheduleData.values) {
                                            if (data['day'] == day && data['hourIndex'] == hourIndex) {
                                              final tId = data['teacherId']?.toString();
                                              final tIds = (data['teacherIds'] as List?)?.map((e) => e.toString()).toList();
                                              if (tId == rowId || (tIds != null && tIds.contains(rowId))) {
                                                assignment = data;
                                                break;
                                              }
                                            }
                                          }
                                        }

                                        // Kapalı slot kontrolü
                                        final slotKey = '${day}_$hourIndex';
                                        final cellClassId = !_isTeacherView
                                            ? rowId
                                            : (assignment?['classId']?.toString() ?? targetClassId ?? '');
                                        final isClassClosed = _closedSlots['class_$cellClassId']?.contains(slotKey) ?? false;

                                        // Bu hücre veya seçili ders için öğretmen kapalı mı?
                                        final Set<String> relevantTeacherIds = {};
                                        if (assignment != null) {
                                          if (assignment['teacherId'] != null) relevantTeacherIds.add(assignment['teacherId'].toString());
                                          if (assignment['teacherIds'] != null) {
                                            relevantTeacherIds.addAll((assignment['teacherIds'] as List).map((e) => e.toString()));
                                          }
                                        }
                                        if (_isTeacherView) {
                                          relevantTeacherIds.add(rowId);
                                        }

                                        final isTargetRow = !_isTeacherView
                                            ? rowId == targetClassId
                                            : (targetTeacherIds.contains(rowId));

                                        if (_selectedUnassignedLesson != null && isTargetRow) {
                                          relevantTeacherIds.addAll(targetTeacherIds);
                                        }

                                        bool isTeacherClosed = false;
                                        for (var t in relevantTeacherIds) {
                                          if (_closedSlots['teacher_$t']?.contains(slotKey) == true) {
                                            isTeacherClosed = true;
                                            break;
                                          }
                                        }

                                        final isClosed = isClassClosed || isTeacherClosed;

                                        // İnteraktif yeşil & turuncu vurgu hesabı
                                        bool isHighlightGreen = false;
                                        bool isHighlightOrange = false;
                                        if (_selectedUnassignedLesson != null &&
                                            targetClassId != null &&
                                            !isClosed &&
                                            isTargetRow) {
                                          final classFree = _scheduleData['${targetClassId}_${day}_$hourIndex'] == null;
                                          bool teachersFree = true;
                                          for (var entry in _scheduleData.values) {
                                            if (entry['day'] == day && entry['hourIndex'] == hourIndex) {
                                              final entTId = entry['teacherId']?.toString();
                                              final entTIds = (entry['teacherIds'] as List?)?.map((e) => e.toString()).toList();
                                              if ((entTId != null && targetTeacherIds.contains(entTId)) ||
                                                  (entTIds != null && entTIds.any((t) => targetTeacherIds.contains(t)))) {
                                                teachersFree = false;
                                                break;
                                              }
                                            }
                                          }
                                          if (classFree && teachersFree) {
                                            isHighlightGreen = true;
                                          } else if (!classFree && teachersFree) {
                                            // Öğretmen müsait ama şube dolu → turuncu vurgu
                                            isHighlightOrange = true;
                                          }
                                        }

                                        // Turuncu hücre için şubenin o saatteki dersini bul
                                        Map<String, dynamic>? classAssignment;
                                        if (isHighlightOrange && targetClassId != null) {
                                          classAssignment = _scheduleData['${targetClassId}_${day}_$hourIndex'];
                                          if (classAssignment == null) {
                                            // birleştirilmiş sınıf olabilir, values üzerinden ara
                                            for (var d in _scheduleData.values) {
                                              if (d['day'] == day &&
                                                  d['hourIndex'] == hourIndex &&
                                                  d['classId']?.toString() == targetClassId) {
                                                classAssignment = d;
                                                break;
                                              }
                                            }
                                          }
                                        }

                                        return GestureDetector(
                                          onTap: widget.isViewingPastTerm
                                              ? null
                                              : () {
                                                  if (isHighlightGreen && _selectedUnassignedLesson != null) {
                                                    _assignLesson(
                                                      targetClassId!,
                                                      day,
                                                      hourIndex,
                                                      _selectedUnassignedLesson!,
                                                      targetClassName ?? 'Sınıf',
                                                    );
                                                    final remaining = _remainingHours['${targetClassId}_${_selectedUnassignedLesson!['lessonId']}'] ?? 0;
                                                    if (remaining <= 0) {
                                                      setState(() => _selectedUnassignedLesson = null);
                                                    }
                                                  } else if (isHighlightOrange && _selectedUnassignedLesson != null) {
                                                    // Turuncu hücre: şube dolu, öğretmen müsait — bilgi ver
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          'Öğretmen bu saatte müsait ancak şube programı dolu!\n'
                                                          'Bu saati önce boşaltın, sonra ${_selectedUnassignedLesson!["lessonName"]} dersini buraya ekleyebilirsiniz.',
                                                        ),
                                                        backgroundColor: Colors.orange.shade800,
                                                        duration: const Duration(seconds: 4),
                                                        action: SnackBarAction(
                                                          label: 'Tamam',
                                                          textColor: Colors.white,
                                                          onPressed: () {},
                                                        ),
                                                      ),
                                                    );
                                                  } else if (isClosed && assignment == null) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: const Text('Bu ders saati öğretmen veya şube için kapalıdır! Ders atanamaz.'),
                                                        backgroundColor: Colors.blueGrey.shade800,
                                                        duration: const Duration(seconds: 2),
                                                      ),
                                                    );
                                                  } else {
                                                    final targetCId = !_isTeacherView
                                                        ? rowId
                                                        : (assignment?['classId']?.toString() ?? _classes.first['id']);
                                                    _showLessonPicker(
                                                      targetCId,
                                                      day,
                                                      hourIndex,
                                                    );
                                                  }
                                                },
                                          child: Container(
                                            width: cellWidth - 4,
                                            height: cellHeight - 4,
                                            margin: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: isHighlightGreen
                                                  ? Colors.green.shade100
                                                  : (isHighlightOrange
                                                      ? Colors.orange.shade100
                                                      : (isClosed
                                                          ? Colors.blueGrey.shade700
                                                          : (assignment != null
                                                              ? Colors.red.shade500
                                                              : Colors.grey.shade100))),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(
                                                color: isHighlightGreen
                                                    ? Colors.green.shade600
                                                    : (isHighlightOrange
                                                        ? Colors.orange.shade600
                                                        : (isClosed
                                                            ? Colors.blueGrey.shade900
                                                            : (assignment != null
                                                                ? Colors.red.shade700
                                                                : Colors.grey.shade300))),
                                                width: (isHighlightGreen || isHighlightOrange) ? 2 : 1,
                                              ),
                                            ),
                                            child: Center(
                                              child: isHighlightGreen
                                                  ? Icon(
                                                      Icons.add_circle_rounded,
                                                      size: 14,
                                                      color: Colors.green.shade800,
                                                    )
                                                  : (isHighlightOrange
                                                      ? Text(
                                                          _isTeacherView
                                                              ? '${_getShortName(classAssignment?['lessonName'] ?? assignment?['lessonName'] ?? '')}\n${_resolveClassName(classAssignment ?? assignment ?? {})}'
                                                              : _getShortName(classAssignment?['lessonName'] ?? assignment?['lessonName'] ?? ''),
                                                          style: TextStyle(
                                                            color: Colors.orange.shade900,
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 9,
                                                          ),
                                                          textAlign: TextAlign.center,
                                                        )
                                                      : (isClosed && assignment == null
                                                          ? Icon(
                                                              Icons.lock_rounded,
                                                              size: 12,
                                                              color: Colors.blueGrey.shade300,
                                                            )
                                                          : (assignment != null
                                                              ? Text(
                                                                  _isTeacherView
                                                                      ? '${_getShortName(assignment['lessonName'] ?? '')}\n${_resolveClassName(assignment)}'
                                                                      : _getShortName(assignment['lessonName'] ?? ''),
                                                                  style: const TextStyle(
                                                                    color: Colors.white,
                                                                    fontWeight: FontWeight.bold,
                                                                    fontSize: 9,
                                                                  ),
                                                                  textAlign: TextAlign.center,
                                                                )
                                                              : null))),
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _getShortName(String lessonName) {
    if (lessonName.length <= 3) return lessonName.toUpperCase();

    // İlk 3 harfi al
    final words = lessonName.split(' ');
    if (words.length > 1) {
      return words.map((w) => w.isNotEmpty ? w[0] : '').join('').toUpperCase();
    }
    return lessonName.substring(0, 3).toUpperCase();
  }

  /// Atama verisindeki classId'yi kullanarak sınıf adını çözer.
  /// Birleştirilmiş sınıfları tespit ederek sınıf adlarını tire (-) ile birleştirir (Örn: 801-802-803).
  String _resolveClassName(Map<String, dynamic> data) {
    final day = data['day']?.toString();
    final hourIndex = data['hourIndex'];
    final teacherId = data['teacherId']?.toString();
    final lessonName = (data['lessonName'] ?? '').toString().trim();

    // 1) Explicit 'mergedClassIds' alanı varsa
    final mergedIds = (data['mergedClassIds'] as List?)?.map((e) => e.toString()).toList();
    if (mergedIds != null && mergedIds.isNotEmpty) {
      final names = mergedIds.map((cId) {
        final found = _classes.firstWhere(
          (c) => c['id']?.toString() == cId,
          orElse: () => <String, dynamic>{},
        );
        return found.isNotEmpty ? (found['className']?.toString() ?? cId) : cId;
      }).toList();
      return names.join('-');
    }

    // 2) _lessonClassMerges yapılandırmasından kontrol et
    final classId = data['classId']?.toString();
    if (classId != null && lessonName.isNotEmpty) {
      for (var merge in _lessonClassMerges) {
        final mName = (merge['lessonName'] ?? '').toString().trim();
        final mClassIds = List<String>.from(merge['classIds'] ?? []);
        if (mName.toLowerCase() == lessonName.toLowerCase() && mClassIds.contains(classId)) {
          final names = mClassIds.map((cId) {
            final found = _classes.firstWhere(
              (c) => c['id']?.toString() == cId,
              orElse: () => <String, dynamic>{},
            );
            return found.isNotEmpty ? (found['className']?.toString() ?? cId) : cId;
          }).toList();
          return names.join('-');
        }
      }
    }

    // 3) _scheduleData içinde aynı gün ve saatte bu öğretmenin girdiği diğer sınıfları birleştir
    if (day != null && hourIndex != null && teacherId != null && lessonName.isNotEmpty) {
      final Set<String> relatedClassNames = {};
      for (var entry in _scheduleData.values) {
        if (entry['day'] == day &&
            entry['hourIndex'] == hourIndex &&
            entry['teacherId']?.toString() == teacherId &&
            (entry['lessonName'] ?? '').toString().trim().toLowerCase() == lessonName.toLowerCase()) {
          final cId = entry['classId']?.toString();
          if (cId != null) {
            final found = _classes.firstWhere(
              (c) => c['id']?.toString() == cId,
              orElse: () => <String, dynamic>{},
            );
            final cName = found.isNotEmpty
                ? (found['className']?.toString() ?? cId)
                : (entry['className']?.toString() ?? cId);
            relatedClassNames.add(cName);
          }
        }
      }
      if (relatedClassNames.length > 1) {
        final sortedList = relatedClassNames.toList()..sort();
        return sortedList.join('-');
      }
    }

    if (classId == null) return data['className']?.toString() ?? 'Bilinmeyen';
    final found = _classes.firstWhere(
      (c) => c['id']?.toString() == classId,
      orElse: () => <String, dynamic>{},
    );
    if (found.isNotEmpty) return found['className']?.toString() ?? 'Bilinmeyen';
    // Fallback: stored className field
    return data['className']?.toString() ?? 'Bilinmeyen';
  }
}

class _MultiSelectionContent extends StatefulWidget {
  final String title;
  final List<String> items;
  final IconData icon;
  final bool isDialog;

  const _MultiSelectionContent({
    required this.title,
    required this.items,
    required this.icon,
    this.isDialog = false,
  });

  @override
  State<_MultiSelectionContent> createState() => _MultiSelectionContentState();
}

class _MultiSelectionContentState extends State<_MultiSelectionContent> {
  List<String> selectedItems = [];
  late Map<String, List<String>> levelGroups;
  late List<String> sortedLevels;

  @override
  void initState() {
    super.initState();
    _initializeGroups();
  }

  void _initializeGroups() {
    levelGroups = {};
    for (var item in widget.items) {
      String level = 'Diğer';
      final digitsMatch = RegExp(r'^(\d+)').firstMatch(item);
      if (digitsMatch != null) {
        String digits = digitsMatch.group(1)!;
        if (digits.length >= 3) {
          level = '${digits.substring(0, digits.length - 2)}. Sınıf';
        } else {
          level = '$digits. Sınıf';
        }
      }
      if (!levelGroups.containsKey(level)) levelGroups[level] = [];
      levelGroups[level]!.add(item);
    }
    sortedLevels = levelGroups.keys.toList()..sort((a, b) {
      if (a == 'Diğer') return 1;
      if (b == 'Diğer') return -1;
      return a.compareTo(b);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.isDialog ? 600 : double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: widget.isDialog ? BorderRadius.circular(28) : null,
      ),
      child: Column(
        mainAxisSize: widget.isDialog ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(24, widget.isDialog ? 24 : 48, 16, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.purple.shade700, Colors.indigo.shade700]),
              borderRadius: widget.isDialog ? BorderRadius.vertical(top: Radius.circular(28)) : null,
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(16)),
                  child: Icon(widget.icon, color: Colors.white, size: 28),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                      Text('Lütfen yazdırılacak öğeleri seçin', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hızlı Seçim', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: Text('Tümünü Seç'),
                      selected: selectedItems.length == widget.items.length && widget.items.isNotEmpty,
                      onSelected: (val) {
                        setState(() {
                          if (val) selectedItems = List.from(widget.items);
                          else selectedItems.clear();
                        });
                      },
                    ),
                    if (levelGroups.length > 1)
                      ...sortedLevels.map((lvl) {
                        final lvlItems = levelGroups[lvl]!;
                        final isAllSelected = lvlItems.every((i) => selectedItems.contains(i));
                        return FilterChip(
                          label: Text('$lvl ler'),
                          selected: isAllSelected,
                          selectedColor: Colors.purple.withOpacity(0.2),
                          onSelected: (val) {
                            setState(() {
                              if (val) {
                                for (var i in lvlItems) if (!selectedItems.contains(i)) selectedItems.add(i);
                              } else {
                                for (var i in lvlItems) selectedItems.remove(i);
                              }
                            });
                          },
                        );
                      }),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1),
          Expanded(
            flex: widget.isDialog ? 0 : 1,
            child: Container(
              constraints: widget.isDialog ? BoxConstraints(maxHeight: 400) : null,
              padding: EdgeInsets.all(20),
              child: widget.items.length > 8
                ? GridView.builder(
                    shrinkWrap: widget.isDialog,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
                      childAspectRatio: 3.5,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) => _buildItemCard(widget.items[index]),
                  )
                : ListView.builder(
                    shrinkWrap: widget.isDialog,
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: _buildItemCard(widget.items[index]),
                    ),
                  ),
            ),
          ),
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: widget.isDialog ? BorderRadius.vertical(bottom: Radius.circular(28)) : null,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: Offset(0, -5))],
            ),
            child: Row(
              children: [
                Text('${selectedItems.length} öğe seçildi', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('İptal', style: TextStyle(color: Colors.grey.shade600)),
                ),
                SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.purple.shade600, Colors.indigo.shade600]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.3), blurRadius: 8, offset: Offset(0, 4))],
                  ),
                  child: ElevatedButton(
                    onPressed: selectedItems.isEmpty ? null : () => Navigator.pop(context, selectedItems),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('Hemen Yazdır', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(String item) {
    final isSelected = selectedItems.contains(item);
    return InkWell(
      onTap: () {
        setState(() {
          if (isSelected) selectedItems.remove(item);
          else selectedItems.add(item);
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? Colors.purple.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.purple.shade300 : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [BoxShadow(color: Colors.purple.withOpacity(0.1), blurRadius: 4, offset: Offset(0, 2))] : null,
        ),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected ? Colors.purple : Colors.grey.shade400,
              size: 20,
            ),
            SizedBox(width: 8),
            Expanded(child: Text(item, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

class FullSelectionPage extends StatelessWidget {
  final String title;
  final List<String> items;
  final IconData icon;

  const FullSelectionPage({required this.title, required this.items, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _MultiSelectionContent(title: title, items: items, icon: icon, isDialog: false),
    );
  }
}
