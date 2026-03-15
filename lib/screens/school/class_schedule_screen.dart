import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/term_service.dart';
import '../../services/class_schedule_sync_service.dart';
import '../../services/auto_schedule_service.dart';

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
  bool _isLoading = true;

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

      // Şubeleri yükle
      final classesSnapshot = await FirebaseFirestore.instance
          .collection('classes')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      print('📚 Bulunan şube sayısı: ${classesSnapshot.docs.length}');

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

      setState(() {
        _allClasses = classes;
        _classes = classes;
        _lessonHours = hours;
        _classLessons = classLessons;
        _remainingHours = remainingHours;
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
          title: Row(
            children: [
              Icon(Icons.filter_list, color: Colors.purple),
              SizedBox(width: 8),
              Text('Filtrele'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sınıf Seviyesi',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('Tümü'),
                    selected: _selectedClassLevel == null,
                    onSelected: (selected) {
                      setDialogState(() => _selectedClassLevel = null);
                    },
                  ),
                  ...(_availableClassLevels.toList()..sort()).map(
                    (level) => ChoiceChip(
                      label: Text('$level. Sınıf'),
                      selected: _selectedClassLevel == level,
                      onSelected: (selected) {
                        setDialogState(
                          () => _selectedClassLevel = selected ? level : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Text('Sınıf Tipi', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('Tümü'),
                    selected: _selectedClassType == null,
                    onSelected: (selected) {
                      setDialogState(() => _selectedClassType = null);
                    },
                  ),
                  ..._availableClassTypes.map(
                    (type) => ChoiceChip(
                      label: Text(type),
                      selected: _selectedClassType == type,
                      onSelected: (selected) {
                        setDialogState(
                          () => _selectedClassType = selected ? type : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
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
              child: Text('Temizle'),
            ),
            ElevatedButton(
              onPressed: () {
                _applyFilter();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
              child: Text('Uygula', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPrintOptions() {
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
              'Yazdır',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.person, color: Colors.blue),
              title: Text('Öğretmen Programı Yazdır'),
              subtitle: Text('Tek öğretmenin haftalık programı'),
              onTap: () {
                Navigator.pop(context);
                _showTeacherPrintSelector();
              },
            ),
            ListTile(
              leading: Icon(Icons.class_, color: Colors.green),
              title: Text('Sınıf Programı Yazdır'),
              subtitle: Text('Tek sınıfın haftalık programı'),
              onTap: () {
                Navigator.pop(context);
                _showClassPrintSelector();
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.grid_on, color: Colors.orange),
              title: Text('Öğretmen Çarşaf Program'),
              subtitle: Text('Tüm öğretmenlerin programı tek sayfada'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Öğretmen çarşaf programı hazırlanıyor...'),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.table_chart, color: Colors.purple),
              title: Text('Sınıf Çarşaf Program'),
              subtitle: Text('Tüm sınıfların programı tek sayfada'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Sınıf çarşaf programı hazırlanıyor...'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTeacherPrintSelector() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Öğretmen seçici yakında eklenecek')),
    );
  }

  void _showClassPrintSelector() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Sınıf seçici yakında eklenecek')));
  }

  void _showCopyToAnotherPeriodDialog() async {
    // Diğer dönemleri yükle
    final periodsSnapshot = await FirebaseFirestore.instance
        .collection('workPeriods')
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('institutionId', isEqualTo: widget.institutionId)
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
    String className,
  ) async {
    final key = '${classId}_${day}_$hourIndex';
    final lessonKey = '${classId}_${lesson['lessonId']}';
    final oldAssignment = _scheduleData[key];

    // teacherIds ve teacherNames array olarak geliyor, ilk elemanı al
    final teacherIds = lesson['teacherIds'] as List<dynamic>?;
    final teacherNames = lesson['teacherNames'] as List<dynamic>?;
    final teacherId = (teacherIds != null && teacherIds.isNotEmpty)
        ? teacherIds.first?.toString()
        : null;
    final teacherName = (teacherNames != null && teacherNames.isNotEmpty)
        ? teacherNames.first?.toString() ?? 'Öğretmen'
        : 'Öğretmen';

    print(
      '📝 Ders atama: $key - ${lesson['lessonName']} - Öğretmen: $teacherName (ID: $teacherId)',
    );

    // Eğer aynı ders zaten atanmışsa, kaldır
    if (oldAssignment != null &&
        oldAssignment['lessonId'] == lesson['lessonId']) {
      await _removeAssignment(classId, day, hourIndex);
      return;
    }

    // Öğretmen çakışma kontrolü
    if (teacherId != null) {
      for (var entry in _scheduleData.entries) {
        final data = entry.value;
        // Aynı gün ve saat mi?
        if (data['day'] == day && data['hourIndex'] == hourIndex) {
          // Aynı öğretmen mi?
          if (data['teacherId'] == teacherId && entry.key != key) {
            // Farklı bir sınıfta aynı saatte ders var
            final conflictClassName = _classes.firstWhere(
              (c) => c['id'] == data['classId'],
              orElse: () => {'className': 'Bilinmeyen'},
            )['className'];

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '$teacherName bu saatte $conflictClassName sınıfında ders veriyor!',
                ),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
            Navigator.pop(context);
            return;
          }
        }
      }
    }

    // Eski atamayı kaldır (varsa)
    if (oldAssignment != null) {
      final oldLessonKey = '${classId}_${oldAssignment['lessonId']}';
      _remainingHours[oldLessonKey] = (_remainingHours[oldLessonKey] ?? 0) + 1;

      // Firestore'dan sil
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

    // Önce UI'ı güncelle
    setState(() {
      _scheduleData[key] = {
        'classId': classId,
        'day': day,
        'hourIndex': hourIndex,
        'lessonId': lesson['lessonId'],
        'lessonName': lesson['lessonName'],
        'className': className,
        'teacherId': teacherId,
        'teacherName': teacherName,
      };
      _remainingHours[lessonKey] = (_remainingHours[lessonKey] ?? 1) - 1;
    });

    Navigator.pop(context);

    // Sonra Firestore'a kaydet (arka planda) - using sync service
    try {
      final syncService = ClassScheduleSyncService();
      await syncService.syncLessonAssignment(
        institutionId: widget.institutionId,
        periodId: widget.periodId,
        classId: classId,
        className: className,
        day: day,
        hourIndex: hourIndex,
        lessonId: lesson['lessonId'],
        lessonName: lesson['lessonName'],
        teacherIds: teacherIds?.map((e) => e.toString()).toList() ?? [],
      );
      print('✅ Ders senkronize edildi (ClassScheduleSyncService)');
      print(
        'DEBUG SYNC: teacherIds=${teacherIds?.map((e) => e.toString()).toList()}, teacherId=$teacherId',
      );
    } catch (e) {
      print('⚠️ Ders senkronize edilemedi (Firestore): $e');
      // UI zaten güncellendi, kullanıcı deneyimi etkilenmez
    }
  }

  Future<void> _removeAssignment(
    String classId,
    String day,
    int hourIndex,
  ) async {
    final key = '${classId}_${day}_$hourIndex';
    final assignment = _scheduleData[key];

    if (assignment != null) {
      final lessonKey = '${classId}_${assignment['lessonId']}';

      // Önce UI'ı güncelle
      setState(() {
        _scheduleData.remove(key);
        _remainingHours[lessonKey] = (_remainingHours[lessonKey] ?? 0) + 1;
      });

      Navigator.pop(context);

      // Sonra Firestore'dan sil (arka planda) - using sync service
      try {
        final syncService = ClassScheduleSyncService();
        await syncService.removeLessonAssignment(
          periodId: widget.periodId,
          classId: classId,
          day: day,
          hourIndex: hourIndex,
        );
        print('✅ Ders senkronize edildi (ClassScheduleSyncService - removed)');
      } catch (e) {
        print('⚠️ Ders silinemedi (Firestore): $e');
      }
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _autoDistributeSchedule() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.smart_toy, color: Colors.orange),
            SizedBox(width: 12),
            Text('Otomatik Ders Dağıtımı'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bu işlem mevcut ders programını SİLECEK ve dersleri otomatik dağıtacaktır.',
            ),
            SizedBox(height: 12),
            Text(
              '⚠️ Bu işlem geri alınamaz.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              'Ders atamaları ve öğretmen uygunluklarına göre dağıtım yapılacaktır.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Dağıtımı Başlat'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final service = AutoScheduleService();
      final result = await service.distributeSchedule(
        periodId: widget.periodId,
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
      );

      if (mounted) {
        String message = 'Dağıtım Tamamlandı!\n\n';
        message += '✅ ${result.assignedCount} saat ders yerleştirildi.\n';

        if (result.unassignedCount > 0) {
          message +=
              '⚠️ ${result.unassignedCount} saat ders yerleştirilemedi (Çakışma/Doluluk).\n';
        } else {
          message += '🎉 Tüm dersler başarıyla dağıtıldı!';
        }

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Sonuç'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Tamam'),
              ),
            ],
          ),
        );

        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _clearAllSchedule() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 12),
            Text('Programı Temizle'),
          ],
        ),
        content: Text(
          'Bu dönemdeki TÜM ders programı silinecek.\nBu işlem geri alınamaz!\n\nEminseniz "Temizle" butonuna dokunun.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Temizle', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      // Mevcut programı al
      final scheduleSnapshot = await FirebaseFirestore.instance
          .collection('classSchedules')
          .where('periodId', isEqualTo: widget.periodId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in scheduleSnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tüm program temizlendi'),
            backgroundColor: Colors.green,
          ),
        );
        // Verileri tekrar yükle (kalan saatleri resetlemek için)
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
            icon: Icon(Icons.print, color: Colors.grey.shade700),
            onPressed: _showPrintOptions,
            tooltip: 'Yazdır',
          ),
          // 3 nokta menüsü (kopyala vb.)
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.grey.shade700),
            onSelected: (value) {
              if (value == 'copy') {
                _showCopyToAnotherPeriodDialog();
              } else if (value == 'clear') {
                _clearAllSchedule();
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
          ? Center(child: CircularProgressIndicator())
          : _classes.isEmpty
          ? _buildEmptyState()
          : _buildScheduleGrid(),
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
    // Ders saatleri yoksa uyarı göster
    if (_lessonHours.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time, size: 64, color: Colors.orange.shade300),
            SizedBox(height: 16),
            Text(
              'Bu dönem için ders saati tanımlanmamış',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
            SizedBox(height: 8),
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
    final classColumnWidth = 65.0;

    // Her gün için ders sayısını al
    int getHourCountForDay(String day) {
      return _dailyLessonCounts[day] ?? _lessonHours.length;
    }

    // Toplam genişliği hesapla (her günün ders sayısına göre + border genişlikleri)
    double totalWidth = 0;
    for (var day in _days) {
      totalWidth +=
          getHourCountForDay(day) * cellWidth + 2; // +2 for right border
    }

    return Row(
      children: [
        // Sol sütun - Şube başlığı ve şube isimleri (sabit)
        Column(
          children: [
            // Sol üst köşe (Şube başlığı)
            Container(
              width: classColumnWidth,
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
                  'Şube',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.purple.shade700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            // Şube isimleri listesi
            Expanded(
              child: Container(
                width: classColumnWidth,
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(
                    right: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: ListView.builder(
                  controller: _verticalScrollController,
                  itemCount: _classes.length,
                  itemBuilder: (context, index) {
                    final classData = _classes[index];
                    return Container(
                      height: cellHeight,
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
                          classData['className'] ?? '',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            color: Colors.grey.shade800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        // Sağ taraf - Günler/saatler ve program kutuları (birlikte scroll)
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
                            width:
                                dayHourCount * cellWidth + 2, // +2 for border
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
                                // Gün başlığı
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
                                // Saat başlıkları - o güne ait saatlerden al
                                Expanded(
                                  child: Row(
                                    children: List.generate(dayHourCount, (
                                      hourIndex,
                                    ) {
                                      // Gün bazlı saatleri kullan
                                      final dayHours =
                                          _dayLessonTimes[day] ?? _lessonHours;
                                      final hour = hourIndex < dayHours.length
                                          ? dayHours[hourIndex]
                                          : null;
                                      final startTime =
                                          hour?['startTime'] ?? '';
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
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
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
                    // Program kutuları
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
                          itemCount: _classes.length,
                          itemBuilder: (context, classIndex) {
                            final classData = _classes[classIndex];
                            final classId = classData['id'] as String;
                            return Container(
                              height: cellHeight,
                              decoration: BoxDecoration(
                                color: classIndex % 2 == 0
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
                                    width:
                                        dayHourCount * cellWidth +
                                        2, // +2 for border
                                    decoration: BoxDecoration(
                                      border: Border(
                                        right: BorderSide(
                                          color: Colors.grey.shade300,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: List.generate(dayHourCount, (
                                        hourIndex,
                                      ) {
                                        final key =
                                            '${classId}_${day}_$hourIndex';
                                        final assignment = _scheduleData[key];

                                        return GestureDetector(
                                          onTap: widget.isViewingPastTerm
                                              ? null
                                              : () => _showLessonPicker(
                                                  classId,
                                                  day,
                                                  hourIndex,
                                                ),
                                          child: Container(
                                            width: cellWidth - 4,
                                            height: cellHeight - 4,
                                            margin: EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: assignment != null
                                                  ? Colors.red.shade500
                                                  : Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: assignment != null
                                                    ? Colors.red.shade700
                                                    : Colors.grey.shade300,
                                                width: 1,
                                              ),
                                            ),
                                            child: Center(
                                              child: assignment != null
                                                  ? Text(
                                                      _getShortName(
                                                        assignment['lessonName'] ??
                                                            '',
                                                      ),
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 10,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                    )
                                                  : null,
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
}
