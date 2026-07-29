import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class CurriculumTrackingScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;

  const CurriculumTrackingScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
  }) : super(key: key);

  @override
  State<CurriculumTrackingScreen> createState() => _CurriculumTrackingScreenState();
}

class _CurriculumTrackingScreenState extends State<CurriculumTrackingScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _workPeriods = [];
  String? _selectedPeriodId;
  List<Map<String, dynamic>> _yearlyPlans = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _lessons = [];

  // Filter States
  String? _selectedLevel;
  String? _selectedLessonId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // 1. Fetch target classes
      final classesSnap = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();
      _classes = classesSnap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();

      // 2. Fetch lessons
      final lessonsSnap = await FirebaseFirestore.instance
          .collection('lessons')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .get();
      _lessons = lessonsSnap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();

      // 3. Fetch Work Periods (Alt Dönemler)
      var periodsSnap = await FirebaseFirestore.instance
          .collection('workPeriods')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      if (periodsSnap.docs.isEmpty) {
        periodsSnap = await FirebaseFirestore.instance
            .collection('workPeriods')
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .where('institutionId', isEqualTo: widget.institutionId.toLowerCase())
            .get();
      }

      _workPeriods = periodsSnap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      _workPeriods.sort((a, b) {
        final startA = (a['startDate'] as Timestamp?)?.toDate();
        final startB = (b['startDate'] as Timestamp?)?.toDate();
        if (startA == null || startB == null) return 0;
        return startB.compareTo(startA); // Newest first
      });

      // Default selected period (isActive == true)
      if (_selectedPeriodId == null && _workPeriods.isNotEmpty) {
        final activePeriod = _workPeriods.firstWhere((p) => p['isActive'] == true, orElse: () => _workPeriods.first);
        _selectedPeriodId = activePeriod['id'];
      }

      // 4. Fetch Yearly Plans (Filtered by selected periodId)
      if (_selectedPeriodId != null) {
        final plansSnap = await FirebaseFirestore.instance
            .collection('yearlyPlans')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .where('periodId', isEqualTo: _selectedPeriodId)
            .where('isActive', isEqualTo: true)
            .get();

        List<Map<String, dynamic>> fetchedPlans = [];

        for (var planDoc in plansSnap.docs) {
          final planData = planDoc.data();
          final planId = planDoc.id;

          // Fetch weekly plans
          final weeksSnap = await planDoc.reference
              .collection('weeklyPlans')
              .orderBy('weekNumber')
              .get();

          final weeks = weeksSnap.docs.map((w) => {'id': w.id, ...w.data()}).toList();
          final List<String> targetClassIds = List<String>.from(planData['classIds'] ?? []);

          fetchedPlans.add({
            'id': planId,
            ...planData,
            'weeks': weeks,
            'classIds': targetClassIds,
          });
        }
        _yearlyPlans = fetchedPlans;
      } else {
        _yearlyPlans = [];
      }

      setState(() {
        _loading = false;
      });
    } catch (e) {
      print('Kazanım takip verileri yüklenirken hata oluştu: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veriler yüklenemedi: $e'), backgroundColor: Colors.red),
        );
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Unique Class Levels for Filtering
    final levels = _classes
        .map((c) => (c['classLevel'] ?? '').toString())
        .where((l) => l.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    // Filter Yearly Plans
    final filteredPlans = _yearlyPlans.where((plan) {
      // Filter by Lesson
      if (_selectedLessonId != null && plan['lessonId'] != _selectedLessonId) {
        return false;
      }
      // Filter by Class Level
      if (_selectedLevel != null) {
        final planClassIds = List<String>.from(plan['classIds'] ?? []);
        final hasClassInLevel = _classes.any((c) =>
            planClassIds.contains(c['id']) &&
            c['classLevel']?.toString() == _selectedLevel);
        if (!hasClassInLevel) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kazanım Takip Sistemi',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo),
            ),
            Text(
              'Yıllık Plan İlerleme Analizi',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.indigo),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSummaryHeader(filteredPlans),
                _buildFilterBar(levels),
                Expanded(
                  child: filteredPlans.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: filteredPlans.length,
                          itemBuilder: (context, index) {
                            return _buildPlanCard(filteredPlans[index]);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryHeader(List<Map<String, dynamic>> plans) {
    int totalWeeks = 0;
    int coveredWeeksSum = 0;
    int activePlansCount = plans.length;

    for (var plan in plans) {
      final weeks = plan['weeks'] as List;
      final classIds = List<String>.from(plan['classIds'] ?? []);
      if (weeks.isNotEmpty && classIds.isNotEmpty) {
        totalWeeks += weeks.length * classIds.length;
        for (var week in weeks) {
          final covered = List<String>.from(week['coveredClassIds'] ?? []);
          coveredWeeksSum += covered.where((cId) => classIds.contains(cId)).length;
        }
      }
    }

    final double avgProgress = totalWeeks > 0 ? (coveredWeeksSum / totalWeeks) * 100 : 0.0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade700, Colors.indigo.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.shade200.withOpacity(0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Genel Tamamlanma Seviyesi',
                      style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '%${avgProgress.toStringAsFixed(1)}',
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$activePlansCount Aktif Plan',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: avgProgress / 100,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Toplam kazanım hedeflerinin $coveredWeeksSum adedi sınıflarda işlendi.',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(List<String> levels) {
    Widget buildLevelDropdown() {
      return DropdownButtonFormField<String>(
        value: _selectedLevel,
        isExpanded: true,
        menuMaxHeight: 250,
        borderRadius: BorderRadius.circular(12),
        style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600),
        icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.indigo.shade600),
        decoration: InputDecoration(
          labelText: 'Sınıf Seviyesi',
          labelStyle: TextStyle(color: Colors.indigo.shade700, fontSize: 12, fontWeight: FontWeight.bold),
          filled: true,
          fillColor: Colors.grey.shade50,
          prefixIcon: Icon(Icons.filter_list_rounded, color: Colors.indigo.shade400, size: 18),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.indigo.shade300, width: 2),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        items: [
          const DropdownMenuItem<String>(
            value: null, 
            child: Text('Tümü', overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
          ...levels.map((lvl) => DropdownMenuItem(
                value: lvl,
                child: Text('$lvl. Sınıflar', overflow: TextOverflow.ellipsis, maxLines: 1),
              )),
        ],
        onChanged: (val) => setState(() => _selectedLevel = val),
      );
    }

    Widget buildLessonDropdown() {
      return DropdownButtonFormField<String>(
        value: _selectedLessonId,
        isExpanded: true,
        menuMaxHeight: 250,
        borderRadius: BorderRadius.circular(12),
        style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600),
        icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.indigo.shade600),
        decoration: InputDecoration(
          labelText: 'Ders / Branş',
          labelStyle: TextStyle(color: Colors.indigo.shade700, fontSize: 12, fontWeight: FontWeight.bold),
          filled: true,
          fillColor: Colors.grey.shade50,
          prefixIcon: Icon(Icons.book_outlined, color: Colors.indigo.shade400, size: 18),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.indigo.shade300, width: 2),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        items: [
          const DropdownMenuItem<String>(
            value: null, 
            child: Text('Tümü', overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
          ..._lessons.map((ls) => DropdownMenuItem(
                value: ls['id'],
                child: Text(
                  ls['lessonName'] ?? 'Ders',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              )),
        ],
        onChanged: (val) => setState(() => _selectedLessonId = val),
      );
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          // Period Filter Dropdown
          if (_workPeriods.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              value: _selectedPeriodId,
              isExpanded: true,
              menuMaxHeight: 250,
              borderRadius: BorderRadius.circular(12),
              style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600),
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.indigo.shade600),
              decoration: InputDecoration(
                labelText: 'Aktif Dönem / Çalışma Dönemi',
                labelStyle: TextStyle(color: Colors.indigo.shade700, fontSize: 12, fontWeight: FontWeight.bold),
                filled: true,
                fillColor: Colors.grey.shade50,
                prefixIcon: Icon(Icons.date_range_rounded, color: Colors.indigo.shade400, size: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.indigo.shade300, width: 2),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: _workPeriods.map((p) {
                final name = p['periodName'] ?? 'Dönem';
                final isActive = p['isActive'] == true ? ' (Aktif)' : '';
                return DropdownMenuItem(
                  value: p['id'].toString(),
                  child: Text('$name$isActive', overflow: TextOverflow.ellipsis, maxLines: 1),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedPeriodId = val;
                  });
                  _loadData();
                }
              },
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(child: buildLevelDropdown()),
              const SizedBox(width: 12),
              Expanded(child: buildLessonDropdown()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final weeks = plan['weeks'] as List? ?? [];
    final targetClassIds = List<String>.from(plan['classIds'] ?? []);
    final lessonName = plan['planTitle'] ?? plan['lessonName'] ?? 'Ders Planı';
    final teacherName = plan['teacherName'] ?? 'Öğretmen Belirtilmemiş';

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lessonName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Sorumlu: $teacherName',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.menu_book, color: Colors.indigo.shade400, size: 22),
              ],
            ),
            const Divider(height: 20),
            const Text(
              'Şube İlerleme Durumları:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            if (targetClassIds.isEmpty)
              Text('Bu plana atanmış şube bulunmamaktadır.',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontStyle: FontStyle.italic))
            else
              ...targetClassIds.map((cId) {
                final classInfo = _classes.firstWhere((c) => c['id'] == cId, orElse: () => {});
                final className = classInfo.isNotEmpty ? classInfo['className']?.toString() ?? cId : cId;

                // Calculate completed weeks for this class
                int completedWeeks = 0;
                for (var w in weeks) {
                  final covered = List<String>.from(w['coveredClassIds'] ?? []);
                  if (covered.contains(cId)) {
                    completedWeeks++;
                  }
                }

                final totalWeeks = weeks.length;
                final double progress = totalWeeks > 0 ? (completedWeeks / totalWeeks) : 0.0;

                int currentWeekNum = 1;
                for (var w in weeks) {
                  final covered = List<String>.from(w['coveredClassIds'] ?? []);
                  if (covered.contains(cId)) {
                    currentWeekNum = (w['weekNumber'] as int? ?? 0) + 1;
                  }
                }
                if (currentWeekNum > totalWeeks) currentWeekNum = totalWeeks;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$className Şubesi',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          Text(
                            '$completedWeeks/$totalWeeks Hafta (%${(progress * 100).toStringAsFixed(0)})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: progress > 0.8
                                  ? Colors.green
                                  : (progress > 0.4 ? Colors.orange : Colors.red),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress,
                                backgroundColor: Colors.grey.shade200,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  progress > 0.8
                                      ? Colors.green
                                      : (progress > 0.4 ? Colors.orange : Colors.red),
                                ),
                                minHeight: 5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Şu an: $currentWeekNum. Hafta',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _showPlanDetailsDialog(plan),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.indigo,
                  side: BorderSide(color: Colors.indigo.shade200),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.analytics_outlined, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Haftalık Kazanım Plan Detayları',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPlanDetailsDialog(Map<String, dynamic> plan) {
    final weeks = plan['weeks'] as List? ?? [];
    final targetClassIds = List<String>.from(plan['classIds'] ?? []);
    final lessonName = plan['planTitle'] ?? plan['lessonName'] ?? 'Ders Planı';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '$lessonName - Haftalık Kazanımlar',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: weeks.length,
                  itemBuilder: (context, idx) {
                    final week = weeks[idx];
                    final weekNum = week['weekNumber'] ?? (idx + 1);
                    final topic = week['topic'] ?? 'Konu Tanımsız';
                    final outcome = week['outcome'] ?? 'Kazanım Tanımsız';
                    final covered = List<String>.from(week['coveredClassIds'] ?? []);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '$weekNum. Hafta',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Konu: $topic',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Kazanım: $outcome',
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('İşleyen Şubeler: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Wrap(
                                  spacing: 6,
                                  children: targetClassIds.map((cId) {
                                    final classInfo = _classes.firstWhere((c) => c['id'] == cId, orElse: () => {});
                                    final className = classInfo.isNotEmpty ? classInfo['className']?.toString() ?? cId : cId;
                                    final isCovered = covered.contains(cId);

                                    return Chip(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      backgroundColor: isCovered ? Colors.green.shade50 : Colors.red.shade50,
                                      side: BorderSide(color: isCovered ? Colors.green.shade200 : Colors.red.shade200),
                                      label: Text(
                                        className,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isCovered ? Colors.green.shade800 : Colors.red.shade800,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Aktif Yıllık Plan Bulunmamaktadır.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Filtreleri değiştirmeyi veya yeni bir plan eklemeyi deneyin.',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
