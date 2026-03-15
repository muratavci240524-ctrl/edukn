import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/term_service.dart';

class LessonHoursScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const LessonHoursScreen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<LessonHoursScreen> createState() => _LessonHoursScreenState();
}

class _LessonHoursScreenState extends State<LessonHoursScreen> with WidgetsBindingObserver {
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
        _isViewingPastTerm = selectedTermId != null && selectedTermId != activeTermId;
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
          icon: Icon(Icons.arrow_back, color: Colors.blue),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ders Saatleri',
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
                        borderSide: BorderSide(color: Colors.blue, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      constraints: BoxConstraints(maxHeight: 40),
                    ),
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                SizedBox(height: 8),
                // Alt Dönemler Listesi
                Expanded(
                  child: _buildPeriodsList(),
                ),
              ],
            ),
          ),
          // Sağ Panel - Ders Saatleri Detay
          if (isWideScreen)
            Expanded(
              child: _selectedPeriod != null
                  ? _LessonHoursDetailScreen(
                      periodId: _selectedPeriodId!,
                      periodData: _selectedPeriod!,
                      schoolTypeId: widget.schoolTypeId,
                      institutionId: widget.institutionId,
                      onCopyFromPeriod: _showCopyFromPeriodDialog,
                      isViewingPastTerm: _isViewingPastTerm,
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

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_today, size: 64, color: Colors.grey.shade400),
                SizedBox(height: 16),
                Text(
                  'Henüz alt dönem tanımlanmamış',
                  style: TextStyle(color: Colors.grey.shade600),
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

        // Tarihe göre sırala (en eski üstte)
        periods.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aDate = (aData['startDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
          final bDate = (bData['startDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
          return aDate.compareTo(bDate);
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
              color: isSelected ? Colors.blue.shade50 : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? Colors.blue : Colors.transparent,
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
                        builder: (context) => Scaffold(
                          body: _LessonHoursDetailScreen(
                            periodId: doc.id,
                            periodData: {...data, 'id': doc.id},
                            schoolTypeId: widget.schoolTypeId,
                            institutionId: widget.institutionId,
                            onCopyFromPeriod: _showCopyFromPeriodDialog,
                            isViewingPastTerm: _isViewingPastTerm,
                          ),
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
                            backgroundColor: Colors.blue.shade100,
                            child: Icon(Icons.access_time, color: Colors.blue, size: 20),
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
                          // Ders saati tanımlı mı badge (workPeriods içindeki lessonHours alanından kontrol)
                          Builder(
                            builder: (context) {
                              final hasHours = data['lessonHours'] != null;
                              return Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: hasHours ? Colors.green.shade100 : Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  hasHours ? 'Tanımlı' : 'Tanımsız',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: hasHours ? Colors.green.shade700 : Colors.orange.shade700,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.date_range, size: 16, color: Colors.grey),
                          SizedBox(width: 8),
                          Text(
                            startDate != null ? _dateFormat.format(startDate) : '-',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          Text(' - ', style: TextStyle(color: Colors.grey)),
                          Text(
                            endDate != null ? _dateFormat.format(endDate) : '-',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
          Icon(Icons.access_time, size: 80, color: Colors.grey.shade300),
          SizedBox(height: 24),
          Text(
            'Ders saatlerini düzenlemek için\nbir alt dönem seçin',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  void _showCopyFromPeriodDialog(String targetPeriodId) async {
    final periodsSnapshot = await FirebaseFirestore.instance
        .collection('workPeriods')
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('isActive', isEqualTo: true)
        .get();

    final periods = periodsSnapshot.docs
        .where((doc) => doc.id != targetPeriodId)
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
            Text('Dönemden Kopyala'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ders saatlerini hangi dönemden kopyalamak istiyorsunuz?',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              SizedBox(height: 16),
              ...periods.map((doc) {
                final data = doc.data();
                return Card(
                  margin: EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade100,
                      child: Icon(Icons.calendar_month, color: Colors.blue, size: 20),
                    ),
                    title: Text(data['periodName'] ?? ''),
                    trailing: Icon(Icons.arrow_forward),
                    onTap: () async {
                      Navigator.pop(context);
                      await _copyLessonHours(doc.id, targetPeriodId);
                    },
                  ),
                );
              }).toList(),
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

  Future<void> _copyLessonHours(String sourcePeriodId, String targetPeriodId) async {
    try {
      // workPeriods koleksiyonundan lessonHours alanını oku
      final sourceDoc = await FirebaseFirestore.instance
          .collection('workPeriods')
          .doc(sourcePeriodId)
          .get();

      if (!sourceDoc.exists || sourceDoc.data()?['lessonHours'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kaynak dönemde ders saati tanımı bulunamadı'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final sourceData = Map<String, dynamic>.from(sourceDoc.data()!['lessonHours']);
      sourceData['copiedFrom'] = sourcePeriodId;
      sourceData['copiedAt'] = FieldValue.serverTimestamp();

      // Hedef döneme kopyala
      await FirebaseFirestore.instance
          .collection('workPeriods')
          .doc(targetPeriodId)
          .update({'lessonHours': sourceData});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ders saatleri kopyalandı'),
          backgroundColor: Colors.green,
        ),
      );

      // Refresh
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

// Ders Saatleri Detay Ekranı
class _LessonHoursDetailScreen extends StatefulWidget {
  final String periodId;
  final Map<String, dynamic> periodData;
  final String schoolTypeId;
  final String institutionId;
  final Function(String) onCopyFromPeriod;
  final bool isViewingPastTerm;

  const _LessonHoursDetailScreen({
    required this.periodId,
    required this.periodData,
    required this.schoolTypeId,
    required this.institutionId,
    required this.onCopyFromPeriod,
    this.isViewingPastTerm = false,
  });

  @override
  State<_LessonHoursDetailScreen> createState() => _LessonHoursDetailScreenState();
}

class _LessonHoursDetailScreenState extends State<_LessonHoursDetailScreen> {
  final DateFormat _dateFormat = DateFormat('dd.MM.yyyy');
  
  // Günler
  final List<String> _allDays = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
  Set<String> _selectedDays = {'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma'};
  
  // Her gün için ayrı ders sayısı
  Map<String, int> _dailyLessonCounts = {};
  
  // Ders saatleri - her gün için ayrı
  Map<String, List<Map<String, TimeOfDay>>> _lessonTimes = {};
  
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadLessonHours();
  }

  @override
  void didUpdateWidget(covariant _LessonHoursDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Dönem değiştiğinde verileri yeniden yükle
    if (oldWidget.periodId != widget.periodId) {
      _loadLessonHours();
    }
  }

  Future<void> _loadLessonHours() async {
    // State'i temizle - dönem değiştiğinde eski veriler kalmasın
    _selectedDays = {'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma'};
    _dailyLessonCounts = {};
    _lessonTimes = {};
    
    try {
      // workPeriods koleksiyonundan lessonHours alanını oku
      final doc = await FirebaseFirestore.instance
          .collection('workPeriods')
          .doc(widget.periodId)
          .get();

      if (doc.exists) {
        final periodData = doc.data()!;
        final data = periodData['lessonHours'] as Map<String, dynamic>?;
        
        if (data != null) {
          // Seçili günler
          if (data['selectedDays'] != null) {
            _selectedDays = Set<String>.from(data['selectedDays'] as List);
          }
          
          // Günlük ders sayıları (gün bazlı)
          if (data['dailyLessonCounts'] != null) {
            final counts = data['dailyLessonCounts'] as Map<String, dynamic>;
            _dailyLessonCounts = counts.map((k, v) => MapEntry(k, v as int));
          } else if (data['dailyLessonCount'] != null) {
            // Eski format - tüm günlere aynı sayı
            final count = data['dailyLessonCount'] as int;
            for (var day in _selectedDays) {
              _dailyLessonCounts[day] = count;
            }
          }
          
          // Ders saatleri
          if (data['lessonTimes'] != null) {
            final times = data['lessonTimes'] as Map<String, dynamic>;
            _lessonTimes = {};
            times.forEach((day, lessons) {
              _lessonTimes[day] = (lessons as List).map((lesson) {
                return {
                  'start': TimeOfDay(
                    hour: lesson['startHour'] ?? 8,
                    minute: lesson['startMinute'] ?? 0,
                  ),
                  'end': TimeOfDay(
                    hour: lesson['endHour'] ?? 8,
                    minute: lesson['endMinute'] ?? 40,
                  ),
                };
              }).toList();
            });
          }
        }
      }
      
      // Eğer ders saatleri yoksa varsayılan oluştur
      _initializeDefaultTimes();
      
      setState(() => _isLoading = false);
    } catch (e) {
      print('Ders saatleri yükleme hatası: $e');
      _initializeDefaultTimes();
      setState(() => _isLoading = false);
    }
  }

  // Belirli bir gün için ders sayısını al (varsayılan 8)
  int _getLessonCount(String day) {
    return _dailyLessonCounts[day] ?? 8;
  }

  void _initializeDefaultTimes() {
    for (var day in _selectedDays) {
      _initializeDefaultTimesForDay(day);
    }
  }

  void _initializeDefaultTimesForDay(String day) {
    final lessonCount = _getLessonCount(day);
    if (!_lessonTimes.containsKey(day) || _lessonTimes[day]!.length != lessonCount) {
      _lessonTimes[day] = List.generate(lessonCount, (index) {
        // Her ders 40dk, teneffüs 10dk = toplam 50dk aralık
        final startMinutes = 8 * 60 + (index * 50); // 08:00'dan başla
        final endMinutes = startMinutes + 40; // 40dk ders süresi
        return {
          'start': TimeOfDay(hour: startMinutes ~/ 60, minute: startMinutes % 60),
          'end': TimeOfDay(hour: endMinutes ~/ 60, minute: endMinutes % 60),
        };
      });
    }
  }

  Future<void> _saveLessonHours() async {
    setState(() => _isSaving = true);

    try {
      // Ders saatlerini Firestore formatına çevir
      final lessonTimesData = <String, dynamic>{};
      _lessonTimes.forEach((day, lessons) {
        lessonTimesData[day] = lessons.map((lesson) {
          return {
            'startHour': lesson['start']!.hour,
            'startMinute': lesson['start']!.minute,
            'endHour': lesson['end']!.hour,
            'endMinute': lesson['end']!.minute,
          };
        }).toList();
      });

      // workPeriods koleksiyonuna lessonHours olarak kaydet
      await FirebaseFirestore.instance
          .collection('workPeriods')
          .doc(widget.periodId)
          .update({
        'lessonHours': {
          'selectedDays': _selectedDays.toList(),
          'dailyLessonCounts': _dailyLessonCounts,
          'lessonTimes': lessonTimesData,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ders saatleri kaydedildi'), backgroundColor: Colors.green),
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

  @override
  Widget build(BuildContext context) {
    final periodName = widget.periodData['periodName'] ?? '';
    final startDate = (widget.periodData['startDate'] as Timestamp?)?.toDate();
    final endDate = (widget.periodData['endDate'] as Timestamp?)?.toDate();

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.blue),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              periodName,
              style: TextStyle(
                color: Colors.grey.shade900,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (startDate != null && endDate != null)
              Text(
                '${_dateFormat.format(startDate)} - ${_dateFormat.format(endDate)}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
          ],
        ),
        actions: [
          // Kopyala butonu
          TextButton.icon(
            onPressed: () => widget.onCopyFromPeriod(widget.periodId),
            icon: Icon(Icons.copy, size: 18),
            label: Text('Kopyala'),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
          ),
          SizedBox(width: 8),
        ],
      ),
      floatingActionButton: (!_isLoading && !widget.isViewingPastTerm)
          ? FloatingActionButton.extended(
              onPressed: _isSaving ? null : _saveLessonHours,
              backgroundColor: _isSaving ? Colors.grey : Colors.blue,
              icon: _isSaving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Eğitim Günleri Seçimi
                  _buildDaysSelectionCard(),
                  SizedBox(height: 16),
                  // Günlük Ders Sayısı
                  _buildLessonCountCard(),
                  SizedBox(height: 16),
                  // Ders Saatleri
                  _buildLessonTimesCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildDaysSelectionCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_today, color: Colors.blue),
                SizedBox(width: 12),
                Text(
                  'Eğitim Günleri',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allDays.map((day) {
                final isSelected = _selectedDays.contains(day);
                return FilterChip(
                  label: Text(day),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedDays.add(day);
                        _initializeDefaultTimes();
                      } else {
                        _selectedDays.remove(day);
                        _lessonTimes.remove(day);
                      }
                    });
                  },
                  selectedColor: Colors.blue.shade100,
                  checkmarkColor: Colors.blue,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.blue.shade700 : Colors.grey.shade700,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // Gün kısaltmaları (karışıklık olmaması için)
  String _getDayShortName(String day) {
    switch (day) {
      case 'Pazartesi': return 'Pzt';
      case 'Salı': return 'Sal';
      case 'Çarşamba': return 'Çar';
      case 'Perşembe': return 'Per';
      case 'Cuma': return 'Cum';
      case 'Cumartesi': return 'Cmt';
      case 'Pazar': return 'Paz';
      default: return day.substring(0, 3);
    }
  }

  // İlk günün ders sayısını tüm günlere uygula
  void _applyFirstDayCountToAll() {
    final sortedDays = _allDays.where((d) => _selectedDays.contains(d)).toList();
    if (sortedDays.isEmpty) return;

    final firstDay = sortedDays.first;
    final firstDayCount = _getLessonCount(firstDay);

    setState(() {
      for (var day in sortedDays) {
        if (day != firstDay) {
          _dailyLessonCounts[day] = firstDayCount;
          _initializeDefaultTimesForDay(day);
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$firstDay ders sayısı ($firstDayCount) tüm günlere uygulandı'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildLessonCountCard() {
    final sortedDays = _allDays.where((d) => _selectedDays.contains(d)).toList();
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 400;
                return Row(
                  children: [
                    Icon(Icons.format_list_numbered, color: Colors.blue),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Günlük Ders Sayıları',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    isNarrow
                        ? IconButton(
                            onPressed: _applyFirstDayCountToAll,
                            icon: Icon(Icons.copy_all, color: Colors.blue),
                            tooltip: 'Tümüne Uygula',
                          )
                        : TextButton.icon(
                            onPressed: _applyFirstDayCountToAll,
                            icon: Icon(Icons.copy_all, size: 18),
                            label: Text('Tümüne Uygula'),
                            style: TextButton.styleFrom(foregroundColor: Colors.blue),
                          ),
                  ],
                );
              },
            ),
            SizedBox(height: 20),
            Center(
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: sortedDays.map((day) {
                final count = _getLessonCount(day);
                return Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blue.shade200, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.1),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        _getDayShortName(day),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: count > 1 ? () {
                              setState(() {
                                _dailyLessonCounts[day] = count - 1;
                                _initializeDefaultTimesForDay(day);
                              });
                            } : null,
                            borderRadius: BorderRadius.circular(12),
                            child: Icon(
                              Icons.remove_circle,
                              color: count > 1 ? Colors.blue : Colors.grey.shade400,
                              size: 28,
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            margin: EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: count < 15 ? () {
                              setState(() {
                                _dailyLessonCounts[day] = count + 1;
                                _initializeDefaultTimesForDay(day);
                              });
                            } : null,
                            borderRadius: BorderRadius.circular(12),
                            child: Icon(
                              Icons.add_circle,
                              color: count < 15 ? Colors.blue : Colors.grey.shade400,
                              size: 28,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLessonTimesCard() {
    // Günleri sırala
    final sortedDays = _allDays.where((d) => _selectedDays.contains(d)).toList();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 400;
                return Row(
                  children: [
                    Icon(Icons.schedule, color: Colors.blue),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ders Saatleri',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    isNarrow
                        ? IconButton(
                            onPressed: _applyFirstDayToAll,
                            icon: Icon(Icons.copy_all, color: Colors.blue),
                            tooltip: 'Tümüne Uygula',
                          )
                        : TextButton.icon(
                            onPressed: _applyFirstDayToAll,
                            icon: Icon(Icons.copy_all, size: 18),
                            label: Text('Tümüne Uygula'),
                            style: TextButton.styleFrom(foregroundColor: Colors.blue),
                          ),
                  ],
                );
              },
            ),
            SizedBox(height: 16),
            // Günler için tab
            DefaultTabController(
              length: sortedDays.length,
              child: Builder(
                builder: (context) {
                  // En yüksek ders sayısını bul
                  int maxLessons = 8;
                  for (var day in sortedDays) {
                    final count = _getLessonCount(day);
                    if (count > maxLessons) maxLessons = count;
                  }
                  return Column(
                    children: [
                      TabBar(
                        isScrollable: true,
                        labelColor: Colors.blue,
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: Colors.blue,
                        tabs: sortedDays.map((day) {
                          final count = _getLessonCount(day);
                          return Tab(text: '$day ($count)');
                        }).toList(),
                      ),
                      SizedBox(
                        height: (maxLessons * 60.0) + 50,
                        child: TabBarView(
                          children: sortedDays.map((day) => _buildDayLessonTimes(day)).toList(),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayLessonTimes(String day) {
    final lessons = _lessonTimes[day] ?? [];
    final lessonCount = _getLessonCount(day);

    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: lessonCount,
      itemBuilder: (context, index) {
        final lesson = index < lessons.length
            ? lessons[index]
            : {'start': TimeOfDay(hour: 8, minute: 0), 'end': TimeOfDay(hour: 8, minute: 40)};

        return Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              // Ders numarası
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              // Başlangıç saati
              Expanded(
                child: InkWell(
                  onTap: () => _selectTime(day, index, true),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_arrow, size: 18, color: Colors.green),
                        SizedBox(width: 8),
                        Text(
                          _formatTime(lesson['start']!),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, color: Colors.grey, size: 20),
              ),
              // Bitiş saati
              Expanded(
                child: InkWell(
                  onTap: () => _selectTime(day, index, false),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.stop, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text(
                          _formatTime(lesson['end']!),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  // TimeOfDay'i dakikaya çevir (karşılaştırma için)
  int _timeToMinutes(TimeOfDay time) {
    return time.hour * 60 + time.minute;
  }

  // Dakikayı TimeOfDay'e çevir
  TimeOfDay _minutesToTime(int minutes) {
    return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }

  Future<void> _selectTime(String day, int lessonIndex, bool isStart) async {
    final dayTimes = _lessonTimes[day];
    final currentTime = dayTimes != null && lessonIndex < dayTimes.length
        ? dayTimes[lessonIndex][isStart ? 'start' : 'end'] ?? TimeOfDay(hour: 8, minute: 0)
        : TimeOfDay(hour: 8, minute: 0);

    final picked = await showTimePicker(
      context: context,
      initialTime: currentTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: Colors.blue),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      // Başlangıç saati seçildiyse validasyon yap
      if (isStart) {
        // Bir önceki dersin bitiş saatini kontrol et
        if (lessonIndex > 0) {
          final prevLesson = _lessonTimes[day]?[lessonIndex - 1];
          if (prevLesson != null) {
            final prevEnd = prevLesson['end'] as TimeOfDay?;
            if (prevEnd != null && _timeToMinutes(picked) < _timeToMinutes(prevEnd)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Başlangıç saati bir önceki dersin bitiş saatinden (${_formatTime(prevEnd)}) önce olamaz!',
                  ),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
          }
        }
      }

      setState(() {
        if (!_lessonTimes.containsKey(day)) {
          _lessonTimes[day] = [];
        }
        while (_lessonTimes[day]!.length <= lessonIndex) {
          _lessonTimes[day]!.add({
            'start': TimeOfDay(hour: 8, minute: 0),
            'end': TimeOfDay(hour: 8, minute: 40),
          });
        }
        
        if (isStart) {
          // Başlangıç saatini ayarla
          _lessonTimes[day]![lessonIndex]['start'] = picked;
          
          // Bitiş saatini otomatik olarak +40 dk yap
          final endMinutes = _timeToMinutes(picked) + 40;
          _lessonTimes[day]![lessonIndex]['end'] = _minutesToTime(endMinutes);
          
          // Sonraki dersleri de otomatik güncelle (her biri +10dk teneffüs + 40dk ders)
          _updateFollowingLessons(day, lessonIndex);
        } else {
          // Bitiş saatini manuel ayarla
          _lessonTimes[day]![lessonIndex]['end'] = picked;
          
          // Sonraki dersleri de otomatik güncelle
          _updateFollowingLessons(day, lessonIndex);
        }
      });
    }
  }

  // Sonraki dersleri otomatik güncelle
  void _updateFollowingLessons(String day, int fromIndex) {
    final lessons = _lessonTimes[day];
    if (lessons == null) return;
    
    for (int i = fromIndex + 1; i < lessons.length; i++) {
      final prevEnd = lessons[i - 1]['end'] as TimeOfDay;
      // Önceki dersin bitişine 10dk teneffüs ekle
      final newStartMinutes = _timeToMinutes(prevEnd) + 10;
      final newEndMinutes = newStartMinutes + 40;
      
      lessons[i]['start'] = _minutesToTime(newStartMinutes);
      lessons[i]['end'] = _minutesToTime(newEndMinutes);
    }
  }

  void _applyFirstDayToAll() {
    final sortedDays = _allDays.where((d) => _selectedDays.contains(d)).toList();
    if (sortedDays.isEmpty) return;

    final firstDay = sortedDays.first;
    final firstDayTimes = _lessonTimes[firstDay];
    if (firstDayTimes == null) return;

    setState(() {
      for (var day in sortedDays) {
        if (day != firstDay) {
          _lessonTimes[day] = firstDayTimes.map((lesson) {
            return {
              'start': lesson['start']!,
              'end': lesson['end']!,
            };
          }).toList();
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$firstDay saatleri tüm günlere uygulandı'),
        backgroundColor: Colors.green,
      ),
    );
  }
}
