import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'class_lesson_hub_screen.dart';

class ClassScheduleViewScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const ClassScheduleViewScreen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<ClassScheduleViewScreen> createState() =>
      _ClassScheduleViewScreenState();
}

class _ClassScheduleViewScreenState extends State<ClassScheduleViewScreen> {
  List<Map<String, dynamic>> _allClasses = [];
  List<Map<String, dynamic>> _classes = [];
  Map<String, dynamic>? _selectedClass;
  Map<String, Map<String, dynamic>> _scheduleData = {};
  List<String> _days = [];
  Map<String, int> _dailyLessonCounts = {};
  Map<String, List<Map<String, dynamic>>> _dayLessonTimes = {};
  bool _isLoading = true;
  String? _activePeriodId;
  bool _showTableViewWide = true;
  DateTime _weekStart = DateTime.now();

  // Filtre değişkenleri
  int? _selectedClassLevel;
  String? _selectedClassType;
  Set<int> _availableClassLevels = {};
  Set<String> _availableClassTypes = {};
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _weekStart = _startOfWeek(DateTime.now());
    _loadData();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  DateTime _startOfWeek(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  MaterialColor _getColorFor(String text) {
    if (text.isEmpty) return Colors.blue;
    final colors = [
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.brown,
      Colors.blueGrey,
    ];
    final hash = text.hashCode;
    return colors[hash.abs() % colors.length];
  }

  String _monthNameTr(int month) {
    const months = <String>[
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    if (month < 1 || month > 12) return '';
    return months[month - 1];
  }

  String _formatWeekRange(DateTime weekStart) {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = start.add(Duration(days: 6));
    if (start.month == end.month && start.year == end.year) {
      return '${start.day} - ${end.day} ${_monthNameTr(end.month)} ${end.year}';
    }
    return '${start.day} ${_monthNameTr(start.month)} - ${end.day} ${_monthNameTr(end.month)} ${end.year}';
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Yayınlanmış aktif dönemi bul
      final periodsSnapshot = await FirebaseFirestore.instance
          .collection('workPeriods')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .where('schedulePublished', isEqualTo: true)
          .get();

      if (periodsSnapshot.docs.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      // En son dönemi al
      final periodDoc = periodsSnapshot.docs.first;
      _activePeriodId = periodDoc.id;
      final periodData = periodDoc.data();

      // Ders saatlerini yükle
      final lessonHoursData =
          periodData['lessonHours'] as Map<String, dynamic>?;
      if (lessonHoursData != null) {
        _days = List<String>.from(lessonHoursData['selectedDays'] ?? []);

        final dailyCountsRaw =
            lessonHoursData['dailyLessonCounts'] as Map<String, dynamic>?;
        if (dailyCountsRaw != null) {
          _dailyLessonCounts = dailyCountsRaw.map(
            (k, v) =>
                MapEntry(k, v is int ? v : int.tryParse(v.toString()) ?? 0),
          );
        }

        // Ders saatlerini parse et
        final lessonTimesRaw = lessonHoursData['lessonTimes'];
        if (lessonTimesRaw != null && lessonTimesRaw is Map) {
          final lessonTimesMap = Map<String, dynamic>.from(lessonTimesRaw);
          final firstKey = lessonTimesMap.keys.first;
          final isNumericKey = int.tryParse(firstKey) != null;

          if (isNumericKey) {
            final sortedKeys = lessonTimesMap.keys.toList()
              ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

            final hours = sortedKeys.map((key) {
              final time = Map<String, dynamic>.from(lessonTimesMap[key]);
              return {
                'hourNumber': int.parse(key) + 1,
                'startTime':
                    '${(time['startHour'] ?? 0).toString().padLeft(2, '0')}:${(time['startMinute'] ?? 0).toString().padLeft(2, '0')}',
                'endTime':
                    '${(time['endHour'] ?? 0).toString().padLeft(2, '0')}:${(time['endMinute'] ?? 0).toString().padLeft(2, '0')}',
              };
            }).toList();

            for (var day in _days) {
              _dayLessonTimes[day] = List.from(hours);
            }
          } else {
            for (var day in _days) {
              final dayData = lessonTimesMap[day];
              if (dayData != null && dayData is List) {
                _dayLessonTimes[day] = dayData.asMap().entries.map((entry) {
                  final time = Map<String, dynamic>.from(entry.value);
                  return {
                    'hourNumber': entry.key + 1,
                    'startTime':
                        '${(time['startHour'] ?? 0).toString().padLeft(2, '0')}:${(time['startMinute'] ?? 0).toString().padLeft(2, '0')}',
                    'endTime':
                        '${(time['endHour'] ?? 0).toString().padLeft(2, '0')}:${(time['endMinute'] ?? 0).toString().padLeft(2, '0')}',
                  };
                }).toList();
              }
            }
          }
        }
      }

      // Şubeleri yükle
      final classesSnapshot = await FirebaseFirestore.instance
          .collection('classes')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      final classes = classesSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

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

      // Filtre seçeneklerini topla
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
        _availableClassLevels = classLevels;
        _availableClassTypes = classTypes;
        _isLoading = false;
      });
    } catch (e) {
      print('Veri yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadClassSchedule(String classId) async {
    if (_activePeriodId == null) return;

    try {
      // Paralel olarak hem schedule hem lessonAssignments çek
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('classSchedules')
            .where('periodId', isEqualTo: _activePeriodId)
            .where('classId', isEqualTo: classId)
            .where('isActive', isEqualTo: true)
            .get(),
        FirebaseFirestore.instance
            .collection('lessonAssignments')
            .where('classId', isEqualTo: classId)
            .where('isActive', isEqualTo: true)
            .get(),
      ]);

      final scheduleSnapshot = results[0];
      final assignmentsSnapshot = results[1];

      // lessonId -> teacherName map'i oluştur
      final Map<String, String> teacherNameMap = {};
      for (var doc in assignmentsSnapshot.docs) {
        final data = doc.data();
        final lessonId = data['lessonId'] as String?;
        final teacherNames = data['teacherNames'] as List<dynamic>?;
        if (lessonId != null &&
            teacherNames != null &&
            teacherNames.isNotEmpty) {
          teacherNameMap[lessonId] = teacherNames.first?.toString() ?? '';
        }
      }

      final Map<String, Map<String, dynamic>> scheduleData = {};
      for (var doc in scheduleSnapshot.docs) {
        final data = doc.data();
        final key = '${data['classId']}_${data['day']}_${data['hourIndex']}';

        // teacherName boş veya "Öğretmen" ise map'ten al
        String? teacherName = data['teacherName'] as String?;
        if (teacherName == null ||
            teacherName.isEmpty ||
            teacherName == 'Öğretmen') {
          final lessonId = data['lessonId'] as String?;
          if (lessonId != null) {
            teacherName = teacherNameMap[lessonId];
          }
        }

        scheduleData[key] = {...data, 'id': doc.id, 'teacherName': teacherName};
      }

      setState(() {
        _scheduleData = scheduleData;
      });
    } catch (e) {
      print('Program yükleme hatası: $e');
    }
  }

  void _applyFilter() {
    setState(() {
      _classes = _allClasses.where((c) {
        // Arama filtresi
        if (_searchQuery.isNotEmpty) {
          final name = (c['className'] ?? '').toString().toLowerCase();
          if (!name.contains(_searchQuery.toLowerCase())) return false;
        }
        if (_selectedClassLevel != null) {
          final level = c['classLevel'];
          final classLevel = level is int
              ? level
              : int.tryParse(level.toString()) ?? 0;
          if (classLevel != _selectedClassLevel) return false;
        }
        if (_selectedClassType != null) {
          final type = c['classTypeName'] as String?;
          if (type != _selectedClassType) return false;
        }
        return true;
      }).toList();
    });
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.purple : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              'Şube Ders Programı',
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
            icon: Icon(Icons.print, color: Colors.purple),
            onPressed: () {
              // Yazdır fonksiyonu
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Yazdırma özelliği yakında eklenecek')),
              );
            },
            tooltip: 'Yazdır',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _activePeriodId == null
          ? _buildNoPublishedSchedule()
          : _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    final isWideScreen = MediaQuery.of(context).size.width > 900;

    // Mobil görünümde sadece liste göster
    if (!isWideScreen) {
      return _buildClassList();
    }

    // Geniş ekranda sol-sağ panel
    return Row(
      children: [
        // Sol panel - Şube listesi
        Container(
          width: 320,
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(right: BorderSide(color: Colors.grey.shade300)),
          ),
          child: _buildClassList(),
        ),
        // Sağ panel - Program görünümü
        Expanded(
          child: _selectedClass == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.touch_app,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Programı görmek için bir şube seçin',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : _buildScheduleView(),
        ),
      ],
    );
  }

  Widget _buildClassList() {
    return Column(
      children: [
        // Filtreler - Şube listesi tarzında
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.purple.shade600, Colors.purple.shade400],
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Başlık
              Row(
                children: [
                  Icon(Icons.class_outlined, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Şubeler',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_classes.length}',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              // Arama
              SizedBox(
                height: 40,
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Şube ara...',
                    hintStyle: TextStyle(color: Colors.white70, fontSize: 14),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 20,
                      color: Colors.white70,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear,
                              size: 18,
                              color: Colors.white70,
                            ),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                                _searchQuery = '';
                              });
                              _applyFilter();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.2),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 0,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                    _applyFilter();
                  },
                ),
              ),
              SizedBox(height: 12),
              // Filtre butonları - Sınıf Seviyesi ve Sınıf Tipi
              Row(
                children: [
                  Expanded(
                    child: _buildFilterChip(
                      'Tümü',
                      _selectedClassLevel == null && _selectedClassType == null,
                      () {
                        setState(() {
                          _selectedClassLevel = null;
                          _selectedClassType = null;
                        });
                        _applyFilter();
                      },
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: PopupMenuButton<int>(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _selectedClassLevel != null
                              ? Colors.white
                              : Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.school,
                              size: 14,
                              color: _selectedClassLevel != null
                                  ? Colors.purple
                                  : Colors.white,
                            ),
                            SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _selectedClassLevel != null
                                    ? '${_selectedClassLevel}. Sınıf'
                                    : 'Seviye',
                                style: TextStyle(
                                  color: _selectedClassLevel != null
                                      ? Colors.purple
                                      : Colors.white,
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      onSelected: (level) {
                        setState(() {
                          _selectedClassLevel = level;
                        });
                        _applyFilter();
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(value: null, child: Text('Tümü')),
                        ...(_availableClassLevels.toList()..sort()).map(
                          (level) => PopupMenuItem(
                            value: level,
                            child: Text('$level. Sınıf'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: PopupMenuButton<String>(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _selectedClassType != null
                              ? Colors.white
                              : Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.category,
                              size: 14,
                              color: _selectedClassType != null
                                  ? Colors.purple
                                  : Colors.white,
                            ),
                            SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _selectedClassType ?? 'Tip',
                                style: TextStyle(
                                  color: _selectedClassType != null
                                      ? Colors.purple
                                      : Colors.white,
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      onSelected: (type) {
                        setState(() {
                          _selectedClassType = type;
                        });
                        _applyFilter();
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(value: null, child: Text('Tümü')),
                        ..._availableClassTypes.map(
                          (type) =>
                              PopupMenuItem(value: type, child: Text(type)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Şube listesi
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(vertical: 8),
            itemCount: _classes.length,
            itemBuilder: (context, index) {
              final classData = _classes[index];
              final isSelected = _selectedClass?['id'] == classData['id'];
              return Card(
                margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                elevation: isSelected ? 3 : 1,
                color: isSelected ? Colors.purple.shade50 : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? Colors.purple : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: isSelected
                        ? Colors.purple
                        : Colors.purple.shade100,
                    child: Text(
                      classData['className']?.toString().substring(0, 1) ?? '?',
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : Colors.purple.shade700,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    classData['className'] ?? '',
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: isSelected
                          ? Colors.purple.shade700
                          : Colors.grey.shade800,
                    ),
                  ),
                  subtitle: Text(
                    classData['classTypeName'] ?? '',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: isSelected ? Colors.purple : Colors.grey,
                  ),
                  onTap: () {
                    setState(() {
                      _selectedClass = classData;
                    });
                    _loadClassSchedule(classData['id']);
                    // Mobil görünümde program sayfasına git
                    if (MediaQuery.of(context).size.width <= 900) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => _ClassScheduleDetailView(
                            institutionId: widget.institutionId,
                            schoolTypeId: widget.schoolTypeId,
                            classData: classData,
                            scheduleData: _scheduleData,
                            days: _days,
                            dailyLessonCounts: _dailyLessonCounts,
                            dayLessonTimes: _dayLessonTimes,
                            activePeriodId: _activePeriodId,
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
  }

  Widget _buildNoPublishedSchedule() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today, size: 64, color: Colors.grey.shade400),
          SizedBox(height: 16),
          Text(
            'Yayınlanmış ders programı bulunamadı',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'Ders programı yönetici tarafından yayınlandığında burada görünecektir',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleView() {
    if (_days.isEmpty) {
      return Center(child: Text('Ders saati tanımlanmamış'));
    }

    final maxHours = _dailyLessonCounts.values.isNotEmpty
        ? _dailyLessonCounts.values.reduce((a, b) => a > b ? a : b)
        : 8;

    return Column(
      children: [
        // Başlık
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.purple.shade400, Colors.purple.shade600],
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_view_week, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_selectedClass!['className']} - Haftalık Program',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () {
                        setState(() {
                          _weekStart = _weekStart.subtract(Duration(days: 7));
                        });
                      },
                      icon: Icon(Icons.chevron_left, color: Colors.white),
                    ),
                    SizedBox(width: 6),
                    Text(
                      _formatWeekRange(_weekStart),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 6),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () {
                        setState(() {
                          _weekStart = _weekStart.add(Duration(days: 7));
                        });
                      },
                      icon: Icon(Icons.chevron_right, color: Colors.white),
                    ),
                    SizedBox(width: 10),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () {
                        setState(() {
                          _showTableViewWide = !_showTableViewWide;
                        });
                      },
                      icon: Icon(
                        _showTableViewWide
                            ? Icons.view_agenda_outlined
                            : Icons.table_rows_outlined,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _showTableViewWide
              ? _buildTableScheduleWide(maxHours)
              : _buildCardScheduleWide(),
        ),
      ],
    );
  }

  Widget _buildTableScheduleWide(int maxHours) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
      ),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _horizontalScrollController,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row
                    Row(
                      children: [
                        Container(
                          width: 100,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.purple.shade500,
                                Colors.purple.shade700,
                              ],
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'GÜN',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                        ...List.generate(
                          maxHours,
                          (hourIndex) => Container(
                            width: 90,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.purple.shade500,
                                  Colors.purple.shade700,
                                ],
                              ),
                              border: Border(
                                left: BorderSide(
                                  color: Colors.purple.shade400,
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${hourIndex + 1}. Ders',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Data rows
                    ...List.generate(_days.length, (dayIndex) {
                      final day = _days[dayIndex];
                      final dayHourCount = _dailyLessonCounts[day] ?? maxHours;
                      final isLast = dayIndex == _days.length - 1;
                      final isEvenRow = dayIndex % 2 == 0;

                      return Row(
                        children: [
                          // Day label
                          Container(
                            width: 100,
                            height: 72,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isEvenRow
                                    ? [
                                        Colors.purple.shade50,
                                        Colors.purple.shade100,
                                      ]
                                    : [Colors.white, Colors.purple.shade50],
                              ),
                              border: Border(
                                top: BorderSide(
                                  color: Colors.purple.shade100,
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                day,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: Colors.purple.shade700,
                                ),
                              ),
                            ),
                          ),
                          // Hour cells
                          ...List.generate(maxHours, (hourIndex) {
                            if (hourIndex >= dayHourCount) {
                              return Container(
                                width: 90,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  border: Border(
                                    top: BorderSide(
                                      color: Colors.grey.shade200,
                                      width: 1,
                                    ),
                                    left: BorderSide(
                                      color: Colors.grey.shade200,
                                      width: 1,
                                    ),
                                  ),
                                ),
                              );
                            }

                            final key =
                                '${_selectedClass!['id']}_${day}_$hourIndex';
                            final assignment = _scheduleData[key];

                            MaterialColor? cellColor;
                            if (assignment != null) {
                              cellColor = _getColorFor(
                                (assignment['lessonName'] ?? '').toString(),
                              );
                            }

                            return InkWell(
                              onTap: assignment == null
                                  ? null
                                  : () {
                                      final classId =
                                          (_selectedClass?['id'] ?? '')
                                              .toString();
                                      final lessonId =
                                          (assignment['lessonId'] ?? '')
                                              .toString();
                                      if (classId.isEmpty || lessonId.isEmpty)
                                        return;

                                      final dayIndex = _days.indexOf(day);
                                      final initialDate = dayIndex >= 0
                                          ? _weekStart.add(
                                              Duration(days: dayIndex),
                                            )
                                          : null;
                                      final List<int> availableLessonHours = [];
                                      for (int i = 0; i < maxHours; i++) {
                                        final checkKey =
                                            '${_selectedClass!['id']}_${day}_$i';
                                        final a = _scheduleData[checkKey];
                                        final aLessonId = (a?['lessonId'] ?? '')
                                            .toString();
                                        if (aLessonId == lessonId) {
                                          availableLessonHours.add(i + 1);
                                        }
                                      }

                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              ClassLessonHubScreen(
                                                institutionId:
                                                    widget.institutionId,
                                                schoolTypeId:
                                                    widget.schoolTypeId,
                                                periodId: _activePeriodId,
                                                classId: classId,
                                                lessonId: lessonId,
                                                className:
                                                    (_selectedClass?['className'] ??
                                                            '')
                                                        .toString(),
                                                lessonName:
                                                    (assignment['lessonName'] ??
                                                            '')
                                                        .toString(),
                                                initialDate: initialDate,
                                                initialLessonHour:
                                                    hourIndex + 1,
                                                availableLessonHours:
                                                    availableLessonHours,
                                              ),
                                        ),
                                      );
                                    },
                              child: Container(
                                width: 90,
                                height: 72,
                                decoration: BoxDecoration(
                                  gradient: assignment != null
                                      ? LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            cellColor!.shade100,
                                            cellColor.shade200,
                                          ],
                                        )
                                      : null,
                                  color: assignment == null
                                      ? (isEvenRow
                                            ? Colors.grey.shade50
                                            : Colors.white)
                                      : null,
                                  border: Border(
                                    top: BorderSide(
                                      color: assignment != null
                                          ? cellColor!.shade300
                                          : Colors.grey.shade200,
                                      width: 1,
                                    ),
                                    left: BorderSide(
                                      color: assignment != null
                                          ? cellColor!.shade300
                                          : Colors.grey.shade200,
                                      width: 1,
                                    ),
                                    bottom: isLast
                                        ? BorderSide(
                                            color: assignment != null
                                                ? cellColor!.shade300
                                                : Colors.grey.shade200,
                                            width: 1,
                                          )
                                        : BorderSide.none,
                                  ),
                                ),
                                child: assignment != null
                                    ? Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: Center(
                                                child: Text(
                                                  (assignment['lessonName'] ??
                                                          '')
                                                      .toString(),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: cellColor!.shade900,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            if ((assignment['teacherName'] ??
                                                    '')
                                                .toString()
                                                .isNotEmpty)
                                              Text(
                                                (assignment['teacherName'] ??
                                                        '')
                                                    .toString(),
                                                style: TextStyle(
                                                  fontSize: 8,
                                                  color: cellColor.shade700,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                          ],
                                        ),
                                      )
                                    : null,
                              ),
                            );
                          }),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardScheduleWide() {
    final classId = (_selectedClass?['id'] ?? '').toString();
    if (classId.isEmpty) return SizedBox.shrink();

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _days.map((day) {
            final dayHourCount = _dailyLessonCounts[day] ?? 8;
            final dayTimes = _dayLessonTimes[day] ?? [];

            return Container(
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.purple.shade400,
                          Colors.purple.shade600,
                        ],
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            day,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$dayHourCount ders',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...List.generate(dayHourCount, (hourIndex) {
                    final timeInfo = hourIndex < dayTimes.length
                        ? dayTimes[hourIndex]
                        : null;
                    final startTime = timeInfo != null
                        ? (timeInfo['startTime'] ?? '').toString()
                        : '';
                    final endTime = timeInfo != null
                        ? (timeInfo['endTime'] ?? '').toString()
                        : '';
                    final key = '${classId}_${day}_$hourIndex';
                    final assignment = _scheduleData[key];

                    return InkWell(
                      onTap: assignment == null
                          ? null
                          : () {
                              final lessonId = (assignment['lessonId'] ?? '')
                                  .toString();
                              if (classId.isEmpty || lessonId.isEmpty) return;

                              final dayIndex = _days.indexOf(day);
                              final initialDate = dayIndex >= 0
                                  ? _weekStart.add(Duration(days: dayIndex))
                                  : null;
                              final List<int> availableLessonHours = [];
                              for (int i = 0; i < dayHourCount; i++) {
                                final checkKey = '${classId}_${day}_$i';
                                final a = _scheduleData[checkKey];
                                final aLessonId = (a?['lessonId'] ?? '')
                                    .toString();
                                if (aLessonId == lessonId) {
                                  availableLessonHours.add(i + 1);
                                }
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ClassLessonHubScreen(
                                    institutionId: widget.institutionId,
                                    schoolTypeId: widget.schoolTypeId,
                                    periodId: _activePeriodId,
                                    classId: classId,
                                    lessonId: lessonId,
                                    className:
                                        (_selectedClass?['className'] ?? '')
                                            .toString(),
                                    lessonName: (assignment['lessonName'] ?? '')
                                        .toString(),
                                    initialDate: initialDate,
                                    initialLessonHour: hourIndex + 1,
                                    availableLessonHours: availableLessonHours,
                                  ),
                                ),
                              );
                            },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: hourIndex == dayHourCount - 1
                                  ? Colors.transparent
                                  : Colors.grey.shade200,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 60,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${hourIndex + 1}. Ders',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.purple,
                                    ),
                                  ),
                                  if (startTime.isNotEmpty)
                                    Text(
                                      startTime,
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  if (endTime.isNotEmpty)
                                    Text(
                                      endTime,
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: assignment != null
                                  ? _buildCardItemLogic(assignment)
                                  : Container(
                                      padding: EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            _getColorFor(
                                              (assignment?['lessonName'] ?? '')
                                                  .toString(),
                                            ).shade300,
                                            _getColorFor(
                                              (assignment?['lessonName'] ?? '')
                                                  .toString(),
                                            ).shade400,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'Boş',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCardItemLogic(Map<String, dynamic>? assignment) {
    if (assignment == null) return SizedBox.shrink();

    final cellColor = _getColorFor((assignment['lessonName'] ?? '').toString());

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cellColor.shade300, cellColor.shade400],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (assignment['lessonName'] ?? '').toString(),
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if ((assignment['teacherName'] ?? '').toString().isNotEmpty) ...[
            SizedBox(height: 4),
            Text(
              (assignment['teacherName'] ?? '').toString(),
              style: TextStyle(color: Colors.white70, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// Mobil görünüm için detay sayfası
class _ClassScheduleDetailView extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final Map<String, dynamic> classData;
  final Map<String, Map<String, dynamic>> scheduleData;
  final List<String> days;
  final Map<String, int> dailyLessonCounts;
  final Map<String, List<Map<String, dynamic>>> dayLessonTimes;
  final String? activePeriodId;

  const _ClassScheduleDetailView({
    required this.institutionId,
    required this.schoolTypeId,
    required this.classData,
    required this.scheduleData,
    required this.days,
    required this.dailyLessonCounts,
    required this.dayLessonTimes,
    this.activePeriodId,
  });

  @override
  State<_ClassScheduleDetailView> createState() =>
      _ClassScheduleDetailViewState();
}

class _ClassScheduleDetailViewState extends State<_ClassScheduleDetailView> {
  Map<String, Map<String, dynamic>> _scheduleData = {};
  final ScrollController _horizontalScrollController = ScrollController();
  bool _showTableView = false;
  DateTime _weekStart = DateTime.now();

  @override
  void initState() {
    super.initState();
    _weekStart = _startOfWeek(DateTime.now());
    _loadSchedule();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  DateTime _startOfWeek(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  MaterialColor _getColorFor(String text) {
    if (text.isEmpty) return Colors.blue;
    final colors = [
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.brown,
      Colors.purple,
    ];
    final hash = text.hashCode;
    return colors[hash.abs() % colors.length];
  }

  String _monthNameTr(int month) {
    const months = <String>[
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    if (month < 1 || month > 12) return '';
    return months[month - 1];
  }

  String _formatWeekRange(DateTime weekStart) {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = start.add(Duration(days: 6));
    if (start.month == end.month && start.year == end.year) {
      return '${start.day} - ${end.day} ${_monthNameTr(end.month)} ${end.year}';
    }
    return '${start.day} ${_monthNameTr(start.month)} - ${end.day} ${_monthNameTr(end.month)} ${end.year}';
  }

  Future<void> _loadSchedule() async {
    if (widget.activePeriodId == null) return;

    try {
      final scheduleSnapshot = await FirebaseFirestore.instance
          .collection('classSchedules')
          .where('periodId', isEqualTo: widget.activePeriodId)
          .where('classId', isEqualTo: widget.classData['id'])
          .where('isActive', isEqualTo: true)
          .get();

      final classId = widget.classData['id'];

      // lessonAssignments'ı da paralel çek
      final assignmentsSnapshot = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('classId', isEqualTo: classId)
          .where('isActive', isEqualTo: true)
          .get();

      // lessonId -> teacherName map'i oluştur
      final Map<String, String> teacherNameMap = {};
      for (var doc in assignmentsSnapshot.docs) {
        final data = doc.data();
        final lessonId = data['lessonId'] as String?;
        final teacherNames = data['teacherNames'] as List<dynamic>?;
        if (lessonId != null &&
            teacherNames != null &&
            teacherNames.isNotEmpty) {
          teacherNameMap[lessonId] = teacherNames.first?.toString() ?? '';
        }
      }

      final Map<String, Map<String, dynamic>> scheduleData = {};
      for (var doc in scheduleSnapshot.docs) {
        final data = doc.data();
        final key = '${data['classId']}_${data['day']}_${data['hourIndex']}';

        // teacherName boş veya "Öğretmen" ise map'ten al
        String? teacherName = data['teacherName'] as String?;
        if (teacherName == null ||
            teacherName.isEmpty ||
            teacherName == 'Öğretmen') {
          final lessonId = data['lessonId'] as String?;
          if (lessonId != null) {
            teacherName = teacherNameMap[lessonId];
          }
        }

        scheduleData[key] = {...data, 'id': doc.id, 'teacherName': teacherName};
      }

      setState(() {
        _scheduleData = scheduleData;
      });
    } catch (e) {
      print('Program yükleme hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final className = widget.classData['className'] ?? '';

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.purple),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Container(
            margin: EdgeInsets.only(right: 4),
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () {
                    setState(() {
                      _weekStart = _weekStart.subtract(Duration(days: 7));
                    });
                  },
                  icon: Icon(Icons.chevron_left, color: Colors.purple),
                ),
                Text(
                  _formatWeekRange(_weekStart),
                  style: TextStyle(
                    color: Colors.purple,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () {
                    setState(() {
                      _weekStart = _weekStart.add(Duration(days: 7));
                    });
                  },
                  icon: Icon(Icons.chevron_right, color: Colors.purple),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              _showTableView
                  ? Icons.view_agenda_outlined
                  : Icons.table_rows_outlined,
              color: Colors.purple,
            ),
            onPressed: () {
              setState(() {
                _showTableView = !_showTableView;
              });
            },
          ),
        ],
        title: Text(
          '$className - Ders Programı',
          style: TextStyle(
            color: Colors.grey.shade900,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _showTableView
          ? _buildTableScheduleView()
          : _buildCardScheduleView(),
    );
  }

  Widget _buildTableScheduleView() {
    if (widget.days.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule, size: 64, color: Colors.grey.shade400),
            SizedBox(height: 16),
            Text(
              'Ders saati tanımlanmamış',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            SizedBox(height: 8),
            Text(
              'Lütfen önce ders saatlerini tanımlayın',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final maxHours = widget.dailyLessonCounts.values.isNotEmpty
        ? widget.dailyLessonCounts.values.reduce((a, b) => a > b ? a : b)
        : 8;

    return Column(
      children: [
        // Program tablosu - Günler düşey, ders saatleri yatay
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
            ),
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _horizontalScrollController,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header row
                          Row(
                            children: [
                              Container(
                                width: 80,
                                height: 45,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.purple.shade500,
                                      Colors.purple.shade700,
                                    ],
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    'GÜN',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.white,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                              ...List.generate(
                                maxHours,
                                (hourIndex) => Container(
                                  width: 75,
                                  height: 45,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.purple.shade500,
                                        Colors.purple.shade700,
                                      ],
                                    ),
                                    border: Border(
                                      left: BorderSide(
                                        color: Colors.purple.shade400,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${hourIndex + 1}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // Data rows
                          ...List.generate(widget.days.length, (dayIndex) {
                            final day = widget.days[dayIndex];
                            final dayHourCount =
                                widget.dailyLessonCounts[day] ?? maxHours;
                            final isLast = dayIndex == widget.days.length - 1;
                            final isEvenRow = dayIndex % 2 == 0;

                            return Row(
                              children: [
                                // Day label
                                Container(
                                  width: 80,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: isEvenRow
                                          ? [
                                              Colors.purple.shade50,
                                              Colors.purple.shade100,
                                            ]
                                          : [
                                              Colors.white,
                                              Colors.purple.shade50,
                                            ],
                                    ),
                                    border: Border(
                                      top: BorderSide(
                                        color: Colors.purple.shade100,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      day.length > 3
                                          ? day.substring(0, 3)
                                          : day,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Colors.purple.shade700,
                                      ),
                                    ),
                                  ),
                                ),
                                // Hour cells
                                ...List.generate(maxHours, (hourIndex) {
                                  if (hourIndex >= dayHourCount) {
                                    return Container(
                                      width: 75,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        border: Border(
                                          top: BorderSide(
                                            color: Colors.grey.shade200,
                                            width: 1,
                                          ),
                                          left: BorderSide(
                                            color: Colors.grey.shade200,
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  final key =
                                      '${widget.classData['id']}_${day}_$hourIndex';
                                  final assignment = _scheduleData[key];

                                  MaterialColor? cellColor;
                                  if (assignment != null) {
                                    cellColor = _getColorFor(
                                      (assignment['lessonName'] ?? '')
                                          .toString(),
                                    );
                                  }

                                  return InkWell(
                                    onTap: assignment == null
                                        ? null
                                        : () {
                                            final classId =
                                                (widget.classData['id'] ?? '')
                                                    .toString();
                                            final lessonId =
                                                (assignment['lessonId'] ?? '')
                                                    .toString();
                                            if (classId.isEmpty ||
                                                lessonId.isEmpty)
                                              return;

                                            final dayIndex = widget.days
                                                .indexOf(day);
                                            final initialDate = dayIndex >= 0
                                                ? _weekStart.add(
                                                    Duration(days: dayIndex),
                                                  )
                                                : null;
                                            final List<int>
                                            availableLessonHours = [];
                                            for (
                                              int i = 0;
                                              i < dayHourCount;
                                              i++
                                            ) {
                                              final checkKey =
                                                  '${widget.classData['id']}_${day}_$i';
                                              final a = _scheduleData[checkKey];
                                              final aLessonId =
                                                  (a?['lessonId'] ?? '')
                                                      .toString();
                                              if (aLessonId == lessonId) {
                                                availableLessonHours.add(i + 1);
                                              }
                                            }

                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    ClassLessonHubScreen(
                                                      institutionId:
                                                          widget.institutionId,
                                                      schoolTypeId:
                                                          widget.schoolTypeId,
                                                      periodId:
                                                          widget.activePeriodId,
                                                      classId: classId,
                                                      lessonId: lessonId,
                                                      className:
                                                          (widget.classData['className'] ??
                                                                  '')
                                                              .toString(),
                                                      lessonName:
                                                          (assignment['lessonName'] ??
                                                                  '')
                                                              .toString(),
                                                      initialDate: initialDate,
                                                      initialLessonHour:
                                                          hourIndex + 1,
                                                      availableLessonHours:
                                                          availableLessonHours,
                                                    ),
                                              ),
                                            );
                                          },
                                    child: Container(
                                      width: 75,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        gradient: assignment != null
                                            ? LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  cellColor!.shade100,
                                                  cellColor.shade200,
                                                ],
                                              )
                                            : null,
                                        color: assignment == null
                                            ? (isEvenRow
                                                  ? Colors.grey.shade50
                                                  : Colors.white)
                                            : null,
                                        border: Border(
                                          top: BorderSide(
                                            color: assignment != null
                                                ? cellColor!.shade300
                                                : Colors.grey.shade200,
                                            width: 1,
                                          ),
                                          left: BorderSide(
                                            color: assignment != null
                                                ? cellColor!.shade300
                                                : Colors.grey.shade200,
                                            width: 1,
                                          ),
                                          bottom: isLast
                                              ? BorderSide(
                                                  color: assignment != null
                                                      ? cellColor!.shade300
                                                      : Colors.grey.shade200,
                                                  width: 1,
                                                )
                                              : BorderSide.none,
                                        ),
                                      ),
                                      child: assignment != null
                                          ? Padding(
                                              padding: EdgeInsets.all(3),
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Expanded(
                                                    child: Center(
                                                      child: Text(
                                                        (assignment['lessonName'] ??
                                                                '')
                                                            .toString(),
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: cellColor!
                                                              .shade900,
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                  if (assignment['teacherName'] !=
                                                      null)
                                                    Text(
                                                      (assignment['teacherName'] ??
                                                              '')
                                                          .toString(),
                                                      style: TextStyle(
                                                        fontSize: 7,
                                                        color:
                                                            cellColor.shade700,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                ],
                                              ),
                                            )
                                          : null,
                                    ),
                                  );
                                }),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCardScheduleView() {
    if (widget.days.isEmpty) {
      return Center(child: Text('Ders saati tanımlanmamış'));
    }

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widget.days.map((day) => _buildDayCard(day)).toList(),
        ),
      ),
    );
  }

  Widget _buildDayCard(String day) {
    final dayHourCount = widget.dailyLessonCounts[day] ?? 8;
    final dayTimes = widget.dayLessonTimes[day] ?? [];

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade400, Colors.purple.shade600],
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  day,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ...List.generate(dayHourCount, (hourIndex) {
            final timeInfo = hourIndex < dayTimes.length
                ? dayTimes[hourIndex]
                : null;
            final key = '${widget.classData['id']}_${day}_$hourIndex';
            final assignment = _scheduleData[key];

            final startTime = timeInfo != null
                ? (timeInfo['startTime'] ?? '').toString()
                : '';
            final endTime = timeInfo != null
                ? (timeInfo['endTime'] ?? '').toString()
                : '';

            return InkWell(
              onTap: assignment == null
                  ? null
                  : () {
                      final classId = (widget.classData['id'] ?? '').toString();
                      final lessonId = (assignment['lessonId'] ?? '')
                          .toString();
                      if (classId.isEmpty || lessonId.isEmpty) return;

                      final dayIndex = widget.days.indexOf(day);
                      final initialDate = dayIndex >= 0
                          ? _weekStart.add(Duration(days: dayIndex))
                          : null;
                      final List<int> availableLessonHours = [];
                      for (int i = 0; i < dayHourCount; i++) {
                        final checkKey = '${widget.classData['id']}_${day}_$i';
                        final a = _scheduleData[checkKey];
                        final aLessonId = (a?['lessonId'] ?? '').toString();
                        if (aLessonId == lessonId) {
                          availableLessonHours.add(i + 1);
                        }
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ClassLessonHubScreen(
                            institutionId: widget.institutionId,
                            schoolTypeId: widget.schoolTypeId,
                            periodId: widget.activePeriodId,
                            classId: classId,
                            lessonId: lessonId,
                            className: (widget.classData['className'] ?? '')
                                .toString(),
                            lessonName: (assignment['lessonName'] ?? '')
                                .toString(),
                            initialDate: initialDate,
                            initialLessonHour: hourIndex + 1,
                            availableLessonHours: availableLessonHours,
                          ),
                        ),
                      );
                    },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: hourIndex == dayHourCount - 1
                          ? Colors.transparent
                          : Colors.grey.shade200,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${hourIndex + 1}. Ders',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple,
                            ),
                          ),
                          if (startTime.isNotEmpty)
                            Text(
                              startTime,
                              style: TextStyle(fontSize: 9, color: Colors.grey),
                            ),
                          if (endTime.isNotEmpty)
                            Text(
                              endTime,
                              style: TextStyle(fontSize: 9, color: Colors.grey),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: assignment != null
                          ? _buildCardItemLogic(assignment)
                          : Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Boş',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCardItemLogic(Map<String, dynamic>? assignment) {
    if (assignment == null) return SizedBox.shrink();

    final cellColor = _getColorFor((assignment['lessonName'] ?? '').toString());

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cellColor.shade300, cellColor.shade400],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (assignment['lessonName'] ?? '').toString(),
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if ((assignment['teacherName'] ?? '').toString().isNotEmpty) ...[
            SizedBox(height: 4),
            Text(
              (assignment['teacherName'] ?? '').toString(),
              style: TextStyle(color: Colors.white70, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
