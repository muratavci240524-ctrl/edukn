import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';

import '../../../models/school/dynamic_course_group_model.dart';
import '../../../services/dynamic_group_service.dart';
import '../../../services/term_service.dart';

class CourseGroupEditScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final DynamicCourseGroupType type;
  final DynamicCourseGroup? existingGroup;

  const CourseGroupEditScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.type,
    this.existingGroup,
  });

  @override
  State<CourseGroupEditScreen> createState() => _CourseGroupEditScreenState();
}

class _CourseGroupEditScreenState extends State<CourseGroupEditScreen> {
  final DynamicGroupService _groupService = DynamicGroupService();

  bool _loading = true;
  bool _saving = false;

  late TextEditingController _nameController;

  // Alt Dönemler
  String? _academicTermId;
  List<Map<String, dynamic>> _workPeriods = [];
  String? _selectedPeriodId;
  String? _selectedPeriodName;

  // Dersler
  List<Map<String, dynamic>> _periodLessons = [];
  String? _selectedLessonId;
  String? _selectedLessonName;

  // Sınıflar (Sınıf seviyesine göre gruplanmış)
  // Map<int, List<Map<String, dynamic>>>: key = level (5, 6, 7...), value = classes
  Map<int, List<Map<String, dynamic>>> _classesByLevel = {};
  List<int> _sortedLevels = [];
  Set<String> _selectedClassIds = {};
  Map<String, String> _classNamesById = {};

  // Öğretmenler
  List<Map<String, dynamic>> _teachers = [];

  // Derslikler (Classrooms)
  List<Map<String, dynamic>> _classrooms = [];

  // Alt Gruplar (Kurlar veya Kulüpler)
  List<DynamicSubGroup> _subGroups = [];

  bool get isEdit => widget.existingGroup != null;
  bool get isClub => widget.type == DynamicCourseGroupType.club;

  Color get _primaryColor => isClub ? const Color(0xFF059669) : const Color(0xFF4F46E5);
  Color get _primaryLightColor => isClub ? const Color(0xFFD1FAE5) : const Color(0xFFEEF2FF);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existingGroup?.name ?? '',
    );

    if (widget.existingGroup != null) {
      _subGroups = widget.existingGroup!.subGroups.map((g) => g.copyWith()).toList();
      _selectedClassIds = Set<String>.from(widget.existingGroup!.targetClassIds);
      _selectedLessonId = widget.existingGroup!.lessonId;
      _selectedLessonName = widget.existingGroup!.lessonName;
    } else {
      _subGroups = [];
    }

    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final selectedTermId = await TermService().getSelectedTermId();
      final activeTermId = await TermService().getActiveTermId();
      final effectiveTermId = selectedTermId ?? activeTermId;
      _academicTermId = effectiveTermId;

      final instUpper = widget.institutionId.toUpperCase();
      final instLower = widget.institutionId.toLowerCase();

      // 1. Alt Dönemleri Çek (Sadece aktif / seçili akademik döneme ait olanlar)
      Query<Map<String, dynamic>> periodsQuery = FirebaseFirestore.instance
          .collection('workPeriods')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', whereIn: [instUpper, instLower])
          .where('isActive', isEqualTo: true);

      if (effectiveTermId != null && effectiveTermId.isNotEmpty) {
        periodsQuery = periodsQuery.where('termId', isEqualTo: effectiveTermId);
      }

      final periodsSnap = await periodsQuery.get();

      var periods = periodsSnap.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList();

      // Tarihe göre sırala (startDate)
      periods.sort((a, b) {
        final aStart = (a['startDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
        final bStart = (b['startDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
        return aStart.compareTo(bStart);
      });

      _workPeriods = periods;

      // Otomatik aktif alt dönemi belirle
      final now = DateTime.now();
      Map<String, dynamic>? currentPeriod;

      // Eğer düzenleme yapılıyorsa ve grupta kayıtlı periodId veya termId varsa onu seç
      final existingPId = widget.existingGroup?.periodId ?? widget.existingGroup?.subTermId ?? widget.existingGroup?.termId;
      if (existingPId != null && existingPId.isNotEmpty) {
        final match = periods.where((p) => p['id'] == existingPId);
        if (match.isNotEmpty) {
          currentPeriod = match.first;
        }
      }

      if (currentPeriod == null) {
        for (var p in periods) {
          final start = (p['startDate'] as Timestamp?)?.toDate();
          final end = (p['endDate'] as Timestamp?)?.toDate();
          if (start != null && end != null) {
            if (!now.isBefore(start) && !now.isAfter(end.add(const Duration(days: 1)))) {
              currentPeriod = p;
              break;
            }
          }
        }
      }
      currentPeriod ??= periods.isNotEmpty ? periods.first : null;

      _selectedPeriodId = currentPeriod?['id'];
      _selectedPeriodName = currentPeriod?['periodName'] ?? 'Alt Dönem';

      // 2. Sınıfları Çek ve Seviyelerine Göre Sıralı Grupla (Sadece seçili/aktif döneme ait sınıflar)
      final classesSnap = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', whereIn: [instUpper, instLower])
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      final Map<int, List<Map<String, dynamic>>> grouped = {};
      _classNamesById.clear();

      // Sadece aktif/seçili döneme (effectiveTermId) ait sınıfları al (Şube Listesi ile %100 aynı mantık)
      var validClassDocs = classesSnap.docs.where((doc) {
        final data = doc.data();
        if (effectiveTermId != null && data['termId'] != null) {
          return data['termId'] == effectiveTermId;
        }
        return true;
      }).toList();

      // Eğer dönem filtresiyle hiç sınıf bulunamadıysa fallback olarak tüm aktifleri al
      if (validClassDocs.isEmpty) {
        validClassDocs = classesSnap.docs;
      }

      // Aynı isimdeki mükerrer şubeleri önlemek için kontrol
      final Set<String> seenClassNames = {};

      for (var doc in validClassDocs) {
        final data = doc.data();
        data['id'] = doc.id;
        final cName = (data['className'] ?? data['name'] ?? '').toString().trim();
        if (cName.isEmpty) continue;

        // Eğer aynı isimde sınıf zaten eklendiyse tekrar ekleme
        final uniqueKey = '${data['classLevel']}_$cName';
        if (seenClassNames.contains(uniqueKey)) {
          continue;
        }
        seenClassNames.add(uniqueKey);

        _classNamesById[doc.id] = cName;

        int level = 0;
        if (data['classLevel'] is int) {
          level = data['classLevel'];
        } else if (data['classLevel'] != null) {
          level = int.tryParse(data['classLevel'].toString()) ?? 0;
        }

        // Eğer classLevel 0 ise sınıf adındaki ilk rakamdan çıkarım yap (Örn: 501 -> 5, 8-A -> 8)
        if (level == 0 && cName.isNotEmpty) {
          final firstDigit = RegExp(r'\d').firstMatch(cName);
          if (firstDigit != null) {
            level = int.tryParse(firstDigit.group(0)!) ?? 0;
          }
        }

        grouped.putIfAbsent(level, () => []).add(data);
      }

      // Her seviyedeki sınıfları kendi içinde alfabetik/nümerik sırala
      grouped.forEach((lvl, list) {
        list.sort((a, b) {
          final nameA = (a['className'] ?? a['name'] ?? '').toString();
          final nameB = (b['className'] ?? b['name'] ?? '').toString();
          return nameA.compareTo(nameB);
        });
      });

      _classesByLevel = grouped;
      _sortedLevels = grouped.keys.toList()..sort();

      // 3. Öğretmenleri Çek
      final teachersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', whereIn: [instUpper, instLower])
          .where('type', isEqualTo: 'staff')
          .where('isActive', isEqualTo: true)
          .get();

      _teachers = teachersSnap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        if (data['fullName'] == null || data['fullName'].toString().trim().isEmpty) {
          data['fullName'] = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
        }
        return data;
      }).toList();

      _teachers.sort((a, b) => (a['fullName'] ?? '').toString().compareTo((b['fullName'] ?? '').toString()));

      // 4. Derslikleri Çek (Kurumun tüm aktif derslikleri - eski/yeni tüm fiziksel mekanlar)
      try {
        final classroomsSnap = await FirebaseFirestore.instance
            .collection('classrooms')
            .where('institutionId', whereIn: {instUpper, instLower, widget.institutionId}.toList())
            .where('isActive', isEqualTo: true)
            .get();

        final Map<String, Map<String, dynamic>> uniqueRooms = {};
        for (var d in classroomsSnap.docs) {
          final data = <String, dynamic>{'id': d.id, ...d.data()};
          final name = (data['classroomName'] ?? data['name'] ?? '').toString().trim();
          if (name.isEmpty) continue;

          final sId = data['schoolTypeId']?.toString();
          // Eğer henüz eklenmediyse veya bu okul türüne aitse öncelikli olarak al
          if (!uniqueRooms.containsKey(name) || sId == widget.schoolTypeId) {
            uniqueRooms[name] = data;
          }
        }

        var cRooms = uniqueRooms.values.toList();

        // Doğal sıralama (Natural sort: 101, 102 ... 701, 702 ... Spor Salonu)
        cRooms.sort((a, b) {
          final nameA = (a['classroomName'] ?? a['name'] ?? '').toString();
          final nameB = (b['classroomName'] ?? b['name'] ?? '').toString();
          return _compareNatural(nameA, nameB);
        });
        _classrooms = cRooms;
      } catch (ce) {
        debugPrint('Derslikler çekilirken hata: $ce');
      }

      // 5. Alt Dönemin Derslerini Yükle (Tekilleştirilmiş)
      await _loadPeriodLessons();
    } catch (e) {
      debugPrint('Error loading data in CourseGroupEditScreen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Metin ve sayı içeren derslik adlarını doğal (natural) sırada karşılaştırır (1, 2, 10... gibi)
  int _compareNatural(String a, String b) {
    final RegExp re = RegExp(r'(\d+)|\D+');
    final Iterable<Match> aMatches = re.allMatches(a.toLowerCase());
    final Iterable<Match> bMatches = re.allMatches(b.toLowerCase());

    final itA = aMatches.iterator;
    final itB = bMatches.iterator;

    while (itA.moveNext() && itB.moveNext()) {
      final aPart = itA.current.group(0)!;
      final bPart = itB.current.group(0)!;

      final aIsNum = itA.current.group(1) != null;
      final bIsNum = itB.current.group(1) != null;

      if (aIsNum && bIsNum) {
        final aNum = int.tryParse(aPart) ?? 0;
        final bNum = int.tryParse(bPart) ?? 0;
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else {
        final cmp = aPart.compareTo(bPart);
        if (cmp != 0) return cmp;
      }
    }

    return a.length.compareTo(b.length);
  }

  /// Seçili alt döneme ait dersleri tekilleştirerek yükler (yalnızca seçilen alt döneme ait olanlar)
  Future<void> _loadPeriodLessons() async {
    try {
      final instUpper = widget.institutionId.toUpperCase();
      final instLower = widget.institutionId.toLowerCase();

      final Map<String, Map<String, dynamic>> uniqueLessons = {};

      if (_selectedPeriodId != null && _selectedPeriodId!.isNotEmpty) {
        // 1. lessons koleksiyonundan bu alt döneme ait dersleri çek
        final lessonsSnap = await FirebaseFirestore.instance
            .collection('lessons')
            .where('institutionId', whereIn: [instUpper, instLower])
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .where('isActive', isEqualTo: true)
            .get();

        for (var doc in lessonsSnap.docs) {
          final data = doc.data();
          final pId = (data['subTermId'] ?? data['periodId'])?.toString();
          if (pId == _selectedPeriodId) {
            final lName = (data['lessonName'] ?? data['name'] ?? '').toString().trim();
            if (lName.isNotEmpty && !uniqueLessons.containsKey(lName.toLowerCase())) {
              uniqueLessons[lName.toLowerCase()] = {
                'id': doc.id,
                'name': lName,
                'shortName': data['shortName'] ?? '',
                'branchName': (data['branchName'] ?? data['branchId'] ?? '').toString().trim(),
              };
            }
          }
        }

        // 2. lessonAssignments koleksiyonundan bu alt döneme ait atanmış dersleri de ekle
        final assignSnap = await FirebaseFirestore.instance
            .collection('lessonAssignments')
            .where('institutionId', whereIn: [instUpper, instLower])
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .where('isActive', isEqualTo: true)
            .get();

        for (var doc in assignSnap.docs) {
          final data = doc.data();
          final pId = (data['periodId'] ?? data['subTermId'])?.toString();
          if (pId == _selectedPeriodId) {
            final lId = data['lessonId']?.toString();
            final lName = (data['lessonName'] ?? data['name'] ?? '').toString().trim();
            if (lId != null && lName.isNotEmpty && !uniqueLessons.containsKey(lName.toLowerCase())) {
              uniqueLessons[lName.toLowerCase()] = {
                'id': lId,
                'name': lName,
                'shortName': data['shortName'] ?? '',
                'branchName': (data['branchName'] ?? data['branchId'] ?? '').toString().trim(),
              };
            }
          }
        }
      }

      final sortedLessons = uniqueLessons.values.toList()
        ..sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));

      if (mounted) {
        setState(() {
          _periodLessons = sortedLessons;
          if (sortedLessons.isEmpty) {
            _selectedLessonId = null;
            _selectedLessonName = null;
          } else {
            // Eğer mevcut seçim bu listede yoksa ilk uygun olanı veya varsayılanı ata
            if (_selectedLessonId == null || !sortedLessons.any((l) => l['id'] == _selectedLessonId)) {
              if (isClub) {
                final clubMatch = sortedLessons.firstWhere(
                  (l) => l['name'].toString().toLowerCase().contains('kulüp'),
                  orElse: () => sortedLessons.first,
                );
                _selectedLessonId = clubMatch['id'];
                _selectedLessonName = clubMatch['name'];
              } else {
                final engMatch = sortedLessons.firstWhere(
                  (l) => l['name'].toString().toLowerCase().contains('ingilizce') || l['name'].toString().toLowerCase().contains('almanca'),
                  orElse: () => sortedLessons.first,
                );
                _selectedLessonId = engMatch['id'];
                _selectedLessonName = engMatch['name'];
              }
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Ders yükleme hatası: $e');
    }
  }

  void _toggleLevelClasses(int level, bool selectAll) {
    setState(() {
      final classes = _classesByLevel[level] ?? [];
      for (var c in classes) {
        final id = c['id'].toString();
        if (selectAll) {
          _selectedClassIds.add(id);
        } else {
          _selectedClassIds.remove(id);
        }
      }
    });
  }

  /// Şık ve standart boyutta açılan Alt Dönem seçim modalı
  Future<void> _showWorkPeriodPickerModal() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.65,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _primaryLightColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.calendar_month_rounded, color: _primaryColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Alt Dönem (Çalışma Takvimi) Seçin',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          ),
                          Text(
                            '${_workPeriods.length} alt dönem listeleniyor',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(modalCtx),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              Flexible(
                child: _workPeriods.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Tanımlı alt dönem bulunamadı',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _workPeriods.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                        itemBuilder: (context, i) {
                          final p = _workPeriods[i];
                          final id = p['id'].toString();
                          final name = (p['periodName'] ?? 'Alt Dönem').toString();
                          final isSelected = _selectedPeriodId == id;

                          return ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            selected: isSelected,
                            selectedTileColor: _primaryLightColor.withOpacity(0.5),
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: isSelected ? _primaryColor : _primaryLightColor,
                              child: Icon(
                                Icons.date_range_rounded,
                                size: 18,
                                color: isSelected ? Colors.white : _primaryColor,
                              ),
                            ),
                            title: Text(
                              name,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? _primaryColor : const Color(0xFF1E293B),
                                fontSize: 14,
                              ),
                            ),
                            trailing: isSelected
                                ? Icon(Icons.check_circle_rounded, color: _primaryColor)
                                : null,
                            onTap: () {
                              setState(() {
                                _selectedPeriodId = id;
                                _selectedPeriodName = name;
                              });
                              _loadPeriodLessons();
                              Navigator.pop(modalCtx);
                            },
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

  /// Arama destekli, standart boyutta ve kaydırılabilir İlgili Ders seçim modalı
  Future<void> _showLessonPickerModal() async {
    final searchCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final query = searchCtrl.text.trim().toLowerCase();
            final filteredLessons = _periodLessons.where((l) {
              final name = (l['name'] ?? '').toString().toLowerCase();
              return query.isEmpty || name.contains(query);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _primaryLightColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.menu_book_rounded, color: _primaryColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'İlgili Dersi Seçin',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                              ),
                              Text(
                                '${_periodLessons.length} ders listeleniyor',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // En üstte arama çubuğu
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Ders adı ara...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  searchCtrl.clear();
                                  setModalState(() {});
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  // Kaydırılabilir Ders Listesi
                  Expanded(
                    child: filteredLessons.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off_rounded, size: 36, color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                Text(
                                  _periodLessons.isEmpty
                                      ? 'Bu alt döneme ait ders bulunamadı'
                                      : 'Aramaya uygun ders bulunamadı',
                                  style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: filteredLessons.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                            itemBuilder: (context, i) {
                              final l = filteredLessons[i];
                              final id = l['id'].toString();
                              final name = (l['name'] ?? '').toString();
                              final isSelected = _selectedLessonId == id;

                              return ListTile(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                selected: isSelected,
                                selectedTileColor: _primaryLightColor.withOpacity(0.5),
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: isSelected ? _primaryColor : _primaryLightColor,
                                  child: Icon(
                                    Icons.book_rounded,
                                    size: 18,
                                    color: isSelected ? Colors.white : _primaryColor,
                                  ),
                                ),
                                title: Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? _primaryColor : const Color(0xFF1E293B),
                                    fontSize: 14,
                                  ),
                                ),
                                trailing: isSelected
                                    ? Icon(Icons.check_circle_rounded, color: _primaryColor)
                                    : null,
                                onTap: () {
                                  setState(() {
                                    _selectedLessonId = id;
                                    _selectedLessonName = name;
                                  });
                                  Navigator.pop(modalCtx);
                                },
                              );
                            },
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

  String get _currentLessonBranch {
    if (_selectedLessonId != null) {
      final match = _periodLessons.where((l) => l['id'] == _selectedLessonId);
      if (match.isNotEmpty) {
        final b = (match.first['branchName'] ?? '').toString().trim();
        if (b.isNotEmpty) return b;
      }
    }
    if (isClub) return 'Kulüp';
    return _selectedLessonName ?? '';
  }

  bool _isTeacherBranchMatch(Map<String, dynamic> t, String targetBranch, String targetLesson) {
    if (targetBranch.isEmpty && targetLesson.isEmpty) return false;
    final tBranch = (t['branch'] ?? t['branchName'] ?? t['mainBranch'] ?? '').toString().trim().toLowerCase();
    final tRole = (t['role'] ?? '').toString().trim().toLowerCase();
    final target = targetBranch.trim().toLowerCase();
    final lName = targetLesson.trim().toLowerCase();

    final List<String> tBranches = [];
    if (t['branches'] is List) {
      tBranches.addAll((t['branches'] as List).map((e) => e.toString().trim().toLowerCase()));
    }

    if (target.isNotEmpty) {
      if (tBranch == target || tBranch.contains(target) || target.contains(tBranch)) return true;
      if (tRole == target || tRole.contains(target) || target.contains(tRole)) return true;
      if (tBranches.any((b) => b == target || b.contains(target) || target.contains(b))) return true;
    }

    if (lName.isNotEmpty) {
      if (tBranch.isNotEmpty && (lName.contains(tBranch) || tBranch.contains(lName))) return true;
      if (tBranches.any((b) => b.isNotEmpty && (lName.contains(b) || b.contains(lName)))) return true;
    }

    return false;
  }

  /// Arama destekli ve çoklu seçimli şık öğretmen/antrenör seçim modalı
  Future<void> _showTeacherMultiSelectModal({
    required BuildContext parentContext,
    required List<String> initialTeacherIds,
    required List<String> initialTeacherNames,
    required Function(List<String> ids, List<String> names) onSelected,
  }) async {
    final searchCtrl = TextEditingController();
    List<String> tempIds = List.from(initialTeacherIds);
    List<String> tempNames = List.from(initialTeacherNames);

    final targetBranch = _currentLessonBranch;
    final targetLessonName = _selectedLessonName ?? '';

    // Öğretmenleri sırala: İlgili branş öğretmenleri en üstte, ardından alfabetik
    final sortedTeachers = List<Map<String, dynamic>>.from(_teachers);
    sortedTeachers.sort((a, b) {
      final isMatchA = _isTeacherBranchMatch(a, targetBranch, targetLessonName);
      final isMatchB = _isTeacherBranchMatch(b, targetBranch, targetLessonName);

      if (isMatchA && !isMatchB) return -1;
      if (!isMatchA && isMatchB) return 1;

      final nameA = (a['fullName'] ?? '').toString().toLowerCase();
      final nameB = (b['fullName'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });

    await showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSt) {
            final query = searchCtrl.text.trim().toLowerCase();
            final filteredTeachers = sortedTeachers.where((t) {
              final name = (t['fullName'] ?? '').toString().toLowerCase();
              final branch = (t['branch'] ?? t['branchName'] ?? t['role'] ?? '').toString().toLowerCase();
              return query.isEmpty || name.contains(query) || branch.contains(query);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.78,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _primaryLightColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.people_alt_rounded, color: _primaryColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isClub ? 'Sorumlu Antrenör / Öğretmen Seç' : 'Sorumlu Öğretmen Seç',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${tempIds.length} kişi seçildi (Bir veya birden fazla seçebilirsiniz)',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Arama Çubuğu
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Öğretmen adı veya branş ara...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  searchCtrl.clear();
                                  setSt(() {});
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                      ),
                      onChanged: (_) => setSt(() {}),
                    ),
                  ),
                  if (targetBranch.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.auto_awesome_rounded, color: Color(0xFF059669), size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'İlgili Ders Branşı: "$targetBranch" • Branş öğretmenleri en başta listelenmektedir',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF065F46)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  // Öğretmen Listesi
                  Expanded(
                    child: filteredTeachers.isEmpty
                        ? Center(
                            child: Text(
                              'Aramaya uygun öğretmen bulunamadı',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: filteredTeachers.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                            itemBuilder: (context, i) {
                              final t = filteredTeachers[i];
                              final id = t['id'].toString();
                              final name = (t['fullName'] ?? '').toString();
                              final branch = (t['branch'] ?? t['branchName'] ?? t['role'] ?? '').toString();
                              final isSelected = tempIds.contains(id);
                              final isMatch = _isTeacherBranchMatch(t, targetBranch, targetLessonName);

                              return CheckboxListTile(
                                value: isSelected,
                                activeColor: _primaryColor,
                                checkboxShape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                secondary: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: isMatch
                                      ? (isSelected ? _primaryColor : const Color(0xFFD1FAE5))
                                      : (isSelected ? _primaryLightColor : Colors.grey.shade100),
                                  child: isMatch
                                      ? Icon(
                                          Icons.verified_user_rounded,
                                          size: 16,
                                          color: isSelected ? Colors.white : const Color(0xFF059669),
                                        )
                                      : Text(
                                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isSelected ? _primaryColor : Colors.grey.shade700,
                                            fontSize: 13,
                                          ),
                                        ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: TextStyle(
                                          fontWeight: (isSelected || isMatch) ? FontWeight.bold : FontWeight.w500,
                                          fontSize: 14,
                                          color: const Color(0xFF1E293B),
                                        ),
                                      ),
                                    ),
                                    if (isMatch)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFECFDF5),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFF6EE7B7)),
                                        ),
                                        child: const Text(
                                          'Branş Öğretmeni',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF047857),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: branch.isNotEmpty
                                    ? Text(
                                        branch,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isMatch ? const Color(0xFF059669) : Colors.grey.shade500,
                                          fontWeight: isMatch ? FontWeight.w600 : FontWeight.normal,
                                        ),
                                      )
                                    : null,
                                onChanged: (val) {
                                  setSt(() {
                                    if (val == true) {
                                      if (!tempIds.contains(id)) {
                                        tempIds.add(id);
                                        tempNames.add(name);
                                      }
                                    } else {
                                      final index = tempIds.indexOf(id);
                                      if (index != -1) {
                                        tempIds.removeAt(index);
                                        tempNames.removeAt(index);
                                      }
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.clear_all_rounded, size: 18),
                          label: const Text('Temizle'),
                          onPressed: () {
                            setSt(() {
                              tempIds.clear();
                              tempNames.clear();
                            });
                          },
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _primaryColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: Text('Seçimi Onayla (${tempIds.length})'),
                          onPressed: () {
                            onSelected(tempIds, tempNames);
                            Navigator.pop(ctx);
                          },
                        ),
                      ],
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

  /// Arama destekli ve şık derslik / mekan seçim modalı (Sınırlı yükseklik, taşmayan tasarım)
  Future<void> _showClassroomPickerModal({
    required BuildContext parentContext,
    required String selectedClassroom,
    required Function(String name) onSelected,
  }) async {
    final searchCtrl = TextEditingController();

    await showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSt) {
            final query = searchCtrl.text.trim().toLowerCase();
            final filteredClassrooms = _classrooms.where((c) {
              if (query.isEmpty) return true;
              final name = (c['classroomName'] ?? c['name'] ?? '').toString().toLowerCase();
              final code = (c['classroomCode'] ?? '').toString().toLowerCase();
              final type = (c['classroomType'] ?? '').toString().toLowerCase();
              final floor = (c['floor'] ?? '').toString().toLowerCase();
              final building = (c['building'] ?? '').toString().toLowerCase();
              return name.contains(query) ||
                  code.contains(query) ||
                  type.contains(query) ||
                  floor.contains(query) ||
                  building.contains(query);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.70,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _primaryLightColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.meeting_room_rounded, color: _primaryColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Derslik / Mekan Seç',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${_classrooms.length} derslik kayıtlı (Arama yapabilirsiniz)',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Arama Çubuğu
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Derslik adı, kat, bina veya tip ara...',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                        prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade600, size: 20),
                        suffixIcon: searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  searchCtrl.clear();
                                  setSt(() {});
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _primaryColor, width: 1.5),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                      ),
                      onChanged: (_) => setSt(() {}),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Liste
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      children: [
                        // Seçilmedi (Derslik Yok) seçeneği
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            onSelected('');
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: selectedClassroom.isEmpty ? _primaryLightColor.withOpacity(0.5) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selectedClassroom.isEmpty ? _primaryColor : Colors.grey.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.block_rounded, size: 18, color: Colors.grey.shade600),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Seçilmedi (Derslik Yok)',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: Color(0xFF64748B)),
                                  ),
                                ),
                                if (selectedClassroom.isEmpty)
                                  Icon(Icons.check_circle_rounded, color: _primaryColor, size: 20),
                              ],
                            ),
                          ),
                        ),

                        if (filteredClassrooms.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(Icons.meeting_room_outlined, size: 40, color: Colors.grey.shade300),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Eşleşen derslik bulunamadı',
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        ...filteredClassrooms.map((c) {
                          final name = (c['classroomName'] ?? c['name'] ?? '').toString();
                          final isSelected = selectedClassroom == name;
                          final cap = c['capacity'];
                          final floor = c['floor'];
                          final type = c['classroomType'];
                          final building = c['building'];

                          final List<String> details = [];
                          if (cap != null && cap > 0) details.add('Kap: $cap');
                          if (floor != null && floor.toString().trim().isNotEmpty) details.add('Kat: $floor');
                          if (building != null && building.toString().trim().isNotEmpty) details.add('Bina: $building');
                          if (type != null && type.toString().trim().isNotEmpty) details.add('$type');

                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              onSelected(name);
                              Navigator.pop(ctx);
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? _primaryLightColor.withOpacity(0.5) : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? _primaryColor : Colors.grey.shade200,
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isSelected ? _primaryColor : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.meeting_room_rounded,
                                      size: 18,
                                      color: isSelected ? Colors.white : const Color(0xFF475569),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: isSelected ? _primaryColor : const Color(0xFF1E293B),
                                          ),
                                        ),
                                        if (details.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              details.join(' • '),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isSelected ? _primaryColor.withOpacity(0.8) : Colors.grey.shade600,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(Icons.check_circle_rounded, color: _primaryColor, size: 20)
                                  else
                                    Icon(Icons.radio_button_unchecked_rounded, color: Colors.grey.shade300, size: 20),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
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

  /// Alttan açılan modern Kur / Branş ekleme ve düzenleme menüsü (Bottom Sheet)
  void _showAddSubGroupBottomSheet({DynamicSubGroup? editSubGroup, int? editIndex}) {
    final nameCtrl = TextEditingController(text: editSubGroup?.name ?? '');
    final shortNameCtrl = TextEditingController(text: editSubGroup?.shortName ?? '');
    final capCtrl = TextEditingController(text: editSubGroup?.capacity != null ? editSubGroup!.capacity.toString() : '');

    // Sorumlu Öğretmenler
    List<String> selTeacherIds = List.from(editSubGroup?.teacherIds ?? []);
    List<String> selTeacherNames = List.from(editSubGroup?.teacherNames ?? []);

    // Derslik / Oda (opsiyonel)
    String selectedClassroom = editSubGroup?.classroomName ?? '';

    // Otomatik kısa ad üretme
    bool autoShortName = (editSubGroup?.shortName ?? '').isEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomCtx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.88,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 20,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  // Sürükleme Tutamacı
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Başlık Alanı
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _primaryLightColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isClub ? Icons.sports_soccer_rounded : Icons.layers_rounded,
                            color: _primaryColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                editSubGroup != null
                                    ? (isClub ? 'Kulüp Branşını Düzenle' : 'Alt Kuru Düzenle')
                                    : (isClub ? 'Yeni Kulüp Branşı Ekle' : 'Yeni Alt Kur Ekle'),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                isClub
                                    ? 'Branş bilgileri, antrenörler ve mekan detayları'
                                    : 'Kur tam adı, ders programında görünecek kısa adı ve öğretmenler',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(bottomCtx),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Kur Adı ve Ders Programı Kısa Adı
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Kur / Kulüp Tam Adı
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isClub ? 'Kulüp / Branş Adı *' : 'Kur Adı *',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF334155),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    TextFormField(
                                      controller: nameCtrl,
                                      decoration: InputDecoration(
                                        hintText: isClub ? 'Örn: Yüzme Kulübü' : 'Örn: Kur 1 (Starter / A1)',
                                        prefixIcon: Icon(
                                          isClub ? Icons.sports_soccer_outlined : Icons.layers_outlined,
                                          color: _primaryColor,
                                          size: 20,
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.grey.shade300),
                                        ),
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                      ),
                                      onChanged: (val) {
                                        if (autoShortName && shortNameCtrl.text.isEmpty) {
                                          final matchKur = RegExp(r'(?:kur|k)\s*(\d+)', caseSensitive: false).firstMatch(val);
                                          if (matchKur != null) {
                                            shortNameCtrl.text = 'K${matchKur.group(1)}';
                                          } else if (val.trim().length >= 2) {
                                            final clean = val.replaceAll(RegExp(r'[^a-zA-Z0-9ğüşıöçĞÜŞİÖÇ]'), '');
                                            if (clean.length <= 4) {
                                              shortNameCtrl.text = clean.toUpperCase();
                                            }
                                          }
                                          setSt(() {});
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              // Kısa Adı (Ders Programında Görünecek)
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Text(
                                          'Kısa Adı *',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF334155),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Tooltip(
                                          message: 'Haftalık ders programı hücrelerinde bu kısa ad görünür.',
                                          child: Icon(Icons.info_outline_rounded, size: 14, color: _primaryColor),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    TextFormField(
                                      controller: shortNameCtrl,
                                      textCapitalization: TextCapitalization.characters,
                                      maxLength: 8,
                                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                                      decoration: InputDecoration(
                                        hintText: 'Örn: K1 / ROB',
                                        prefixIcon: Icon(Icons.short_text_rounded, color: _primaryColor, size: 20),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.grey.shade300),
                                        ),
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                      ),
                                      onChanged: (_) {
                                        autoShortName = false;
                                        setSt(() {});
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '💡 Ders programı tablosundaki kutucuklarda "Kısa Adı" gösterilecektir.',
                            style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600),
                          ),
                          const SizedBox(height: 18),

                          // 2. Sorumlu Öğretmen / Antrenör (Çoklu Seçim & Arama)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                isClub ? 'Sorumlu Antrenör(ler) / Öğretmen(ler)' : 'Sorumlu Öğretmen(ler)',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF334155),
                                ),
                              ),
                              if (selTeacherIds.isNotEmpty)
                                Text(
                                  '${selTeacherIds.length} Seçili',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryColor),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              _showTeacherMultiSelectModal(
                                parentContext: bottomCtx,
                                initialTeacherIds: selTeacherIds,
                                initialTeacherNames: selTeacherNames,
                                onSelected: (ids, names) {
                                  setSt(() {
                                    selTeacherIds = ids;
                                    selTeacherNames = names;
                                  });
                                },
                              );
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selTeacherIds.isNotEmpty ? _primaryColor.withOpacity(0.5) : Colors.grey.shade300,
                                ),
                              ),
                              child: selTeacherIds.isEmpty
                                  ? Row(
                                      children: [
                                        Icon(Icons.person_add_alt_1_outlined, color: _primaryColor, size: 20),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'Öğretmen / Antrenör seçmek için dokunun (Çoklu seçim)',
                                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                          ),
                                        ),
                                        Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade500),
                                      ],
                                    )
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: List.generate(selTeacherNames.length, (idx) {
                                            final tName = selTeacherNames[idx];
                                            return Chip(
                                              backgroundColor: _primaryLightColor,
                                              avatar: CircleAvatar(
                                                backgroundColor: _primaryColor,
                                                child: Text(
                                                  tName.isNotEmpty ? tName[0].toUpperCase() : '?',
                                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              label: Text(
                                                tName,
                                                style: TextStyle(
                                                  color: _primaryColor,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              deleteIcon: const Icon(Icons.close_rounded, size: 14),
                                              deleteIconColor: _primaryColor,
                                              onDeleted: () {
                                                setSt(() {
                                                  selTeacherIds.removeAt(idx);
                                                  selTeacherNames.removeAt(idx);
                                                });
                                              },
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                            );
                                          }),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Icon(Icons.add_circle_outline_rounded, size: 14, color: _primaryColor),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Öğretmen ekle / değiştir...',
                                              style: TextStyle(fontSize: 12, color: _primaryColor, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // 3. Derslik / Oda (Classroom - Opsiyonel, Kurumun derslik listesinden)
                          const Text(
                            'Derslik / Bulunacağı Mekan (Opsiyonel)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              _showClassroomPickerModal(
                                parentContext: bottomCtx,
                                selectedClassroom: selectedClassroom,
                                onSelected: (name) {
                                  setSt(() {
                                    selectedClassroom = name;
                                  });
                                },
                              );
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selectedClassroom.isNotEmpty ? _primaryColor.withOpacity(0.6) : Colors.grey.shade300,
                                  width: selectedClassroom.isNotEmpty ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selectedClassroom.isNotEmpty ? Icons.meeting_room_rounded : Icons.meeting_room_outlined,
                                    color: selectedClassroom.isNotEmpty ? _primaryColor : Colors.grey.shade600,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      selectedClassroom.isNotEmpty ? selectedClassroom : 'Derslik / Mekan seçin (Opsiyonel)',
                                      style: TextStyle(
                                        color: selectedClassroom.isNotEmpty ? const Color(0xFF1E293B) : Colors.grey.shade500,
                                        fontSize: 13.5,
                                        fontWeight: selectedClassroom.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  if (selectedClassroom.isNotEmpty)
                                    InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () {
                                        setSt(() => selectedClassroom = '');
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade500),
                                      ),
                                    ),
                                  Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade500),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ℹ️ Kurumunuza tanımlı aktif derslik listesinden çekilmektedir. Zorunlu değildir.',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                          ),

                          // 4. Kontenjan (Sadece Kulüpler için)
                          if (isClub) ...[
                            const SizedBox(height: 18),
                            const Text(
                              'Maksimum Kontenjan (Opsiyonel)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF334155),
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: capCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: 'Örn: 20 (Sınırsız için boş bırakın)',
                                prefixIcon: Icon(Icons.group_outlined, color: _primaryColor, size: 20),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  // Alt Eylem Butonları
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                            onPressed: () => Navigator.pop(bottomCtx),
                            child: const Text('İptal', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _primaryColor,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.check_rounded, size: 20),
                            label: Text(
                              editSubGroup != null ? 'Değişiklikleri Uygula' : (isClub ? 'Branşı Ekle' : 'Kuru Ekle'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                            ),
                            onPressed: () {
                              final name = nameCtrl.text.trim();
                              if (name.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Lütfen kur/branş adını girin')),
                                );
                                return;
                              }

                              String shortName = shortNameCtrl.text.trim().toUpperCase();
                              if (shortName.isEmpty) {
                                final matchKur = RegExp(r'(?:kur|k)\s*(\d+)', caseSensitive: false).firstMatch(name);
                                if (matchKur != null) {
                                  shortName = 'K${matchKur.group(1)}';
                                } else {
                                  final clean = name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
                                  shortName = clean.substring(0, clean.length > 4 ? 4 : clean.length).toUpperCase();
                                }
                              }

                              final sub = DynamicSubGroup(
                                id: editSubGroup?.id ?? 'sub_${DateTime.now().millisecondsSinceEpoch}',
                                name: name,
                                shortName: shortName,
                                teacherIds: selTeacherIds,
                                teacherNames: selTeacherNames,
                                classroomName: selectedClassroom,
                                capacity: int.tryParse(capCtrl.text.trim()),
                                studentIds: editSubGroup?.studentIds ?? [],
                              );

                              setState(() {
                                if (editIndex != null && editIndex < _subGroups.length) {
                                  _subGroups[editIndex] = sub;
                                } else {
                                  _subGroups.add(sub);
                                }
                              });

                              Navigator.pop(bottomCtx);
                            },
                          ),
                        ),
                      ],
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

  Future<void> _saveGroup() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen grup adını girin')));
      return;
    }
    if (_selectedClassIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen en az 1 şube seçin')));
      return;
    }
    if (_subGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('En az 1 alt kur veya branş eklemelisiniz')));
      return;
    }

    setState(() => _saving = true);
    try {
      final selectedClassNames = _selectedClassIds.map((id) => _classNamesById[id] ?? id).toList();

      final group = DynamicCourseGroup(
        id: widget.existingGroup?.id ?? '',
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        termId: _academicTermId ?? widget.existingGroup?.termId,
        periodId: _selectedPeriodId,
        subTermId: _selectedPeriodId,
        periodName: _selectedPeriodName,
        type: widget.type,
        name: _nameController.text.trim(),
        lessonId: _selectedLessonId ?? '',
        lessonName: _selectedLessonName ?? (isClub ? 'Kulüp Dersi' : 'İngilizce'),
        targetClassIds: _selectedClassIds.toList(),
        targetClassNames: selectedClassNames,
        subGroups: _subGroups,
        isActive: true,
      );

      await _groupService.saveGroup(group);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${group.name} başarıyla kaydedildi!')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydetme hatası: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: isEdit
            ? (isClub ? 'Kulüp Grubunu Düzenle' : 'Kur Grubunu Düzenle')
            : (isClub ? 'Yeni Kulüp Grubu Tanımla' : 'Yeni Kur Dersi Tanımla'),
        subtitle: widget.schoolTypeName,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_rounded, size: 18),
              label: const Text('Kaydet', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _saving ? null : _saveGroup,
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // KART 1: TEMEL BİLGİLER
                      _buildSectionCard(
                        title: '1. Temel Bilgiler ve Alt Dönem',
                        icon: Icons.info_outline_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Grup Adı
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isClub ? 'Kulüp Grubu Adı *' : 'Kur Grubu Adı *',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _nameController,
                                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                  decoration: InputDecoration(
                                    hintText: isClub ? 'Örn: Ortaokul Sosyal Kulüpleri' : 'Örn: 5. Sınıf İngilizce Kurları',
                                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13.5, fontWeight: FontWeight.normal),
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: _primaryColor, width: 1.8),
                                    ),
                                    prefixIcon: Icon(isClub ? Icons.sports_soccer_outlined : Icons.layers_outlined, color: _primaryColor, size: 20),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            Row(
                              children: [
                                // Alt Dönem Seçimi (Standart Boyutlu Şık Modal)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Alt Dönem (Çalışma Takvimi) *',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF334155),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      InkWell(
                                        onTap: _showWorkPeriodPickerModal,
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: const Color(0xFFE2E8F0),
                                              width: 1.2,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.calendar_month_outlined, color: _primaryColor, size: 20),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  _selectedPeriodName ?? 'Alt Dönem Seçin',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: _selectedPeriodName != null ? const Color(0xFF1E293B) : Colors.grey.shade500,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade500),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // İlgili Ders Seçimi (En Üstte Arama & Standart Kaydırılabilir Modal)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'İlgili Ders (Zaman Çizelgesi) *',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF334155),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      InkWell(
                                        onTap: _showLessonPickerModal,
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: const Color(0xFFE2E8F0),
                                              width: 1.2,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.book_outlined, color: _primaryColor, size: 20),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  _selectedLessonName != null && _selectedLessonName!.isNotEmpty
                                                      ? _selectedLessonName!
                                                      : 'Ders Seçin (Aramak için dokunun)',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: _selectedLessonName != null && _selectedLessonName!.isNotEmpty
                                                        ? const Color(0xFF1E293B)
                                                        : Colors.grey.shade500,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Icon(Icons.search_rounded, color: _primaryColor, size: 18),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // KART 2: KAPSAYAN SINIFLAR (Sınıf Seviyesine Göre Gruplu & 'Tümü' Seçimli)
                      _buildSectionCard(
                        title: '2. Kapsanan Şubeler (${_selectedClassIds.length} Şube Seçildi)',
                        subtitle: 'Bu şubeler ders programında aynı gün ve saatte derse girer.',
                        icon: Icons.groups_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _sortedLevels.map((lvl) {
                            final classes = _classesByLevel[lvl] ?? [];
                            final allInLevelSelected = classes.every((c) => _selectedClassIds.contains(c['id'].toString()));
                            final someInLevelSelected = classes.any((c) => _selectedClassIds.contains(c['id'].toString()));

                            final levelTitle = lvl > 0 ? '$lvl. Sınıflar' : 'Diğer Şubeler';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Seviye Başlığı ve 'Tümü' Butonu
                                  Row(
                                    children: [
                                      Text(
                                        levelTitle,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '${classes.length} Şube',
                                          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const Spacer(),
                                      // Tümü Seçimi
                                      ActionChip(
                                        avatar: Icon(
                                          allInLevelSelected ? Icons.check_box_rounded : (someInLevelSelected ? Icons.indeterminate_check_box_rounded : Icons.check_box_outline_blank_rounded),
                                          size: 17,
                                          color: allInLevelSelected ? _primaryColor : Colors.grey.shade700,
                                        ),
                                        label: Text(
                                          allInLevelSelected ? 'Tümünü Kaldır' : 'Tümünü Seç',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                            color: allInLevelSelected ? _primaryColor : Colors.grey.shade800,
                                          ),
                                        ),
                                        backgroundColor: allInLevelSelected ? _primaryLightColor : Colors.white,
                                        side: BorderSide(color: allInLevelSelected ? _primaryColor : Colors.grey.shade300),
                                        onPressed: () => _toggleLevelClasses(lvl, !allInLevelSelected),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  // Şube Kutuları
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: classes.map((c) {
                                      final cId = c['id'].toString();
                                      final cName = (c['className'] ?? c['name'] ?? '').toString();
                                      final isSelected = _selectedClassIds.contains(cId);

                                      return FilterChip(
                                        label: Text(cName),
                                        selected: isSelected,
                                        selectedColor: _primaryLightColor,
                                        checkmarkColor: _primaryColor,
                                        side: BorderSide(color: isSelected ? _primaryColor : Colors.grey.shade300),
                                        onSelected: (val) {
                                          setState(() {
                                            if (val) {
                                              _selectedClassIds.add(cId);
                                            } else {
                                              _selectedClassIds.remove(cId);
                                            }
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // KART 3: ALT KURLAR / BRANŞLAR
                      _buildSectionCard(
                        title: isClub ? '3. Kulüp Branşları (${_subGroups.length})' : '3. Seviye Kurları (${_subGroups.length})',
                        subtitle: isClub
                            ? 'Öğrencilerin tercihlerine göre dağılacağı branşlar (Futsal, Yüzme, Robotik vb.)'
                            : 'Öğrencilerin seviyelerine göre ayrılacağı kurlar (Kur 1, Kur 2 vb.)',
                        icon: isClub ? Icons.sports_soccer_rounded : Icons.layers_rounded,
                        action: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _primaryLightColor,
                            foregroundColor: _primaryColor,
                          ),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(isClub ? 'Branş Ekle' : 'Kur Ekle', style: const TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () => _showAddSubGroupBottomSheet(),
                        ),
                        child: Column(
                          children: [
                            if (_subGroups.isEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid),
                                ),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(
                                        isClub ? Icons.sports_soccer_outlined : Icons.layers_outlined,
                                        size: 36,
                                        color: Colors.grey.shade400,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        isClub ? 'Henüz kulüp branşı eklenmedi' : 'Henüz alt kur eklenmedi',
                                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Yukarıdaki "${isClub ? 'Branş Ekle' : 'Kur Ekle'}" butonuna basarak ekleyin.',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _subGroups.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, idx) {
                                  final sub = _subGroups[idx];
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: Colors.grey.shade200),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.015),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 20,
                                          backgroundColor: _primaryLightColor,
                                          child: Text(
                                            sub.shortName.isNotEmpty
                                                ? (sub.shortName.length > 4 ? sub.shortName.substring(0, 4) : sub.shortName)
                                                : '${idx + 1}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: _primaryColor,
                                              fontSize: (sub.shortName.length > 3) ? 10 : 12,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      sub.name,
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (sub.shortName.isNotEmpty) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: _primaryLightColor,
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: _primaryColor.withOpacity(0.3)),
                                                      ),
                                                      child: Text(
                                                        sub.shortName,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.bold,
                                                          color: _primaryColor,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Wrap(
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                children: [
                                                  Icon(Icons.person_outline_rounded, size: 13, color: Colors.grey.shade600),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    sub.teacherNames.isNotEmpty ? sub.teacherNames.join(", ") : "Öğretmen Atanmadı",
                                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Icon(Icons.meeting_room_outlined, size: 13, color: Colors.grey.shade600),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    sub.classroomName.isNotEmpty ? sub.classroomName : "Derslik Yok",
                                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                                  ),
                                                  if (sub.capacity != null) ...[
                                                    const SizedBox(width: 10),
                                                    Icon(Icons.group_outlined, size: 13, color: Colors.grey.shade600),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      'Kontenjan: ${sub.capacity}',
                                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.edit_outlined, color: _primaryColor, size: 20),
                                          tooltip: 'Düzenle',
                                          onPressed: () => _showAddSubGroupBottomSheet(editSubGroup: sub, editIndex: idx),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                                          tooltip: 'Sil',
                                          onPressed: () {
                                            setState(() {
                                              _subGroups.removeAt(idx);
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ALT KAYDET BUTONU
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _primaryColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: _saving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.check_circle_outline_rounded),
                          label: Text(
                            isEdit ? 'Değişiklikleri Kaydet' : (isClub ? 'Kulüp Grubunu Oluştur' : 'Kur Dersini Oluştur'),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          onPressed: _saving ? null : _saveGroup,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    String? subtitle,
    required IconData icon,
    Widget? action,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryLightColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _primaryColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    if (subtitle != null)
                      Text(subtitle, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              if (action != null) action,
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}
